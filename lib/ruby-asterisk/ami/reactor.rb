# frozen_string_literal: true

require 'socket'
require 'async'
require 'ruby-asterisk/ami/parser'
require 'ruby-asterisk/compat'

module RubyAsterisk
  module AMI
    # Hosts the AMI connection in two dedicated OS threads:
    #
    #   reactor_thread  — runs an Async reactor with a single reader Fiber that
    #                     reads from the socket, parses AMI frames, and resolves
    #                     Promises / fires the on_event callback.
    #
    #   writer_thread   — blocks on Thread::Queue#pop and writes commands to the
    #                     socket.  Thread::Queue wakeup works on all Ruby versions
    #                     without relying on the Fiber scheduler; closing the socket
    #                     on :stop unblocks the reader Fiber in the other thread.
    #
    # Thread-safety contract:
    #   - External callers use #send_command, #register_promise,
    #     #reject_all_promises, #stop — all thread-safe.
    #   - Promise resolution via Mutex+CV (Promise class unchanged).
    class Reactor
      def initialize(host, port, on_event: nil)
        @host     = host
        @port     = port
        @on_event = on_event

        @command_queue  = Thread::Queue.new
        @ready_queue    = Thread::Queue.new
        @promises_mutex = Mutex.new
        @promises       = {}
        @socket         = nil
        @reactor_thread = nil
        @writer_thread  = nil
      end

      # Start both threads and block until the socket is connected.
      # Raises if the connection fails.
      def start
        @reactor_thread = Thread.new { run }
        result = @ready_queue.pop
        raise result if result.is_a?(Exception)

        self
      end

      # Send a raw AMI command string from any external thread.
      def send_command(cmd)
        @command_queue.push(cmd.freeze)
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

      # Stop both threads gracefully. Blocks until they exit.
      def stop
        return unless @reactor_thread&.alive?

        @command_queue.push(:stop) # wakes writer_thread immediately
        @writer_thread&.join(2)
        @reactor_thread.join(2)
        @reactor_thread = nil
        @writer_thread  = nil
      end

      private

      def run
        @socket = TCPSocket.new(@host, @port)
        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
        @socket.gets # consume AMI banner ("Asterisk Call Manager/x.y\n")

        @writer_thread = Thread.new { writer_loop(@socket) }
        @ready_queue << nil # nil = success

        Sync do |root|
          root.async { reader_fiber(@socket) }
        end
      rescue StandardError => e
        @ready_queue << e # surface connection error to #start
        reject_all_promises(RuntimeError.new("Reactor failed: #{e.message}"))
      ensure
        close_socket
      end

      def writer_loop(socket)
        loop do
          cmd = @command_queue.pop
          break if cmd == :stop

          socket.write(cmd)
        rescue IOError, Errno::EBADF
          break
        end
      ensure
        close_socket # unblocks reader_fiber's readpartial in the reactor thread
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
        # Normal shutdown triggered by writer_loop closing the socket
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
