# frozen_string_literal: true

require 'socket'
require 'async'
require 'ruby-asterisk/ami/parser'
require 'ruby-asterisk/compat'

module RubyAsterisk
  module AMI
    # Single Async reactor running in a dedicated OS thread.
    #
    # Hosts two cooperative Fibers:
    #   - intake_fiber  : reads commands from external threads (IO.pipe doorbell
    #                     + Thread::Queue) and writes them to the AMI socket.
    #   - reader_fiber  : reads from the AMI socket, parses frames with Parser,
    #                     resolves pending Promises or fires the on_event callback.
    #
    # Thread-safety contract:
    #   - External threads communicate via #send_command, #register_promise,
    #     #reject_all_promises, #stop — all thread-safe.
    #   - Promise resolution is Mutex+CV (Promise class unchanged).
    #   - No Mutex is needed *inside* the reactor (all Fiber, single OS thread).
    class Reactor
      def initialize(host, port, on_event: nil)
        @host     = host
        @port     = port
        @on_event = on_event

        @command_queue = Thread::Queue.new
        @doorbell_r, @doorbell_w = IO.pipe
        @ready_queue    = Thread::Queue.new
        @promises_mutex = Mutex.new
        @promises       = {}
        @socket         = nil
        @thread         = nil
      end

      # Start the reactor thread and block until the socket is connected.
      # Raises if the connection fails.
      def start
        @thread = Thread.new { run }
        result = @ready_queue.pop
        raise result if result.is_a?(Exception)

        self
      end

      # Send a raw AMI command string from any external thread.
      def send_command(cmd)
        @command_queue.push(cmd.freeze)
        @doorbell_w.write_nonblock('.')
      end

      # Register a Promise keyed by ActionID.
      def register_promise(action_id, promise)
        @promises_mutex.synchronize { @promises[action_id] = promise }
      end

      # Reject all pending promises with the given error (thread-safe).
      def reject_all_promises(error)
        promises = @promises_mutex.synchronize do
          @promises.values.tap { @promises.clear }
        end
        promises.each { |p| p.reject(error) }
      end

      # Stop the reactor gracefully. Blocks until the reactor thread exits.
      def stop
        return unless @thread&.alive?

        @command_queue.push(:stop)
        @doorbell_w.write_nonblock('.')
        @thread.join(2)
        @thread = nil
      end

      private

      def run
        Sync do |root|
          connect_socket
          @ready_queue << nil # nil = success
          root.async { intake_fiber(@socket) }
          root.async { reader_fiber(@socket) }
        end
      rescue StandardError => e
        @ready_queue << e # surface connection error to #start
        reject_all_promises(RuntimeError.new("Reactor failed: #{e.message}"))
      ensure
        teardown_io
      end

      def connect_socket
        socket = TCPSocket.new(@host, @port)
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
        @socket = socket
        socket.gets # consume AMI banner ("Asterisk Call Manager/x.y\n")
      end

      def teardown_io
        close_socket
        begin
          @doorbell_r.close
        rescue StandardError
          nil
        end
        begin
          @doorbell_w.close
        rescue StandardError
          nil
        end
      end

      def intake_fiber(socket)
        loop do
          @doorbell_r.read(1)

          msg = begin
            @command_queue.pop(true)
          rescue ThreadError
            next
          end

          break if msg == :stop

          socket.write(msg)
        rescue IOError, Errno::EBADF
          break
        end
      ensure
        close_socket # unblocks reader_fiber's readpartial
      end

      def reader_fiber(socket)
        buffer = +''
        loop do
          chunk = socket.readpartial(4096)
          buffer << chunk
          Parser.drain(buffer) { |msg| dispatch(msg) }
        end
      rescue EOFError
        reject_all_promises(RuntimeError.new('Disconnected: EOF from server'))
      rescue IOError, Errno::EBADF
        # Normal shutdown triggered by intake_fiber closing the socket
      rescue StandardError => e
        reject_all_promises(RuntimeError.new("Reactor read error: #{e.message}"))
      end

      def dispatch(msg)
        case msg[:type]
        when :response
          resolve_promise(msg[:action_id], msg[:raw])
        when :event
          @on_event&.call(msg[:event])
        end
      end

      def resolve_promise(action_id, raw_data)
        promise = @promises_mutex.synchronize { @promises.delete(action_id) }
        promise&.resolve(raw_data)
      end

      def close_socket
        @socket&.close
        @socket = nil
      rescue StandardError
        nil
      end
    end
  end
end
