# frozen_string_literal: true

require 'socket'
require 'ruby-asterisk/ami/parser'

module RubyAsterisk
  module AMI
    # Hosts the AMI connection in two plain OS threads:
    #
    #   writer_thread — blocks on Thread::Queue#pop and writes commands to the
    #                   AMI socket.  On :stop it closes the socket, which unblocks
    #                   the reader thread's readpartial call.
    #
    #   reader_thread — loops on socket.readpartial, parses AMI frames with Parser,
    #                   resolves pending Promises or fires the on_event callback.
    #
    # Using plain Threads (no Fiber scheduler) ensures deterministic shutdown on
    # all Ruby versions: closing an IO from one Thread immediately raises IOError
    # in any other Thread blocked on that IO.
    #
    # Thread-safety contract:
    #   - External callers use #send_command, #register_promise,
    #     #reject_all_promises, #stop — all thread-safe.
    #   - Promise resolution via Mutex+CV (Promise class unchanged).
    #   - No cross-thread IO inside the reactor; one thread reads, one writes.
    class Reactor
      def initialize(host, port, on_event: nil)
        @host     = host
        @port     = port
        @on_event = on_event

        @command_queue  = Thread::Queue.new
        @promises_mutex = Mutex.new
        @promises       = {}
        @socket         = nil
        @writer_thread  = nil
        @reader_thread  = nil
      end

      # Open the socket, consume the AMI banner, and start both threads.
      # Raises if the connection fails.
      def start
        @socket = TCPSocket.new(@host, @port)
        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
        @socket.gets # consume AMI banner ("Asterisk Call Manager/x.y\n")

        @writer_thread = Thread.new { writer_loop }
        @reader_thread = Thread.new { reader_loop }
        self
      rescue StandardError
        close_socket
        raise
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
        return unless @writer_thread&.alive? || @reader_thread&.alive?

        @command_queue.push(:stop) # wakes writer_thread immediately
        @writer_thread&.join(2)
        @reader_thread&.join(2)
        @writer_thread = nil
        @reader_thread = nil
      end

      private

      def writer_loop
        loop do
          cmd = @command_queue.pop
          break if cmd == :stop

          @socket.write(cmd)
        rescue IOError, Errno::EBADF
          break
        end
      ensure
        close_socket # raises IOError in reader_thread's readpartial
      end

      def reader_loop
        buffer = +''
        loop do
          chunk = @socket.readpartial(4096)
          buffer << chunk
          Parser.drain(buffer) { |msg| dispatch(msg) }
        end
      rescue EOFError
        reject_all_promises(RuntimeError.new('Disconnected: EOF from server'))
      rescue IOError, Errno::EBADF
        # Normal shutdown: writer_loop closed the socket
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
