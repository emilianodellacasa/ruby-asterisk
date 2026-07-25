# frozen_string_literal: true

require 'socket'
require 'ruby-asterisk/ami/parser'
require 'ruby-asterisk/ami/event_list_aggregation'

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
      include EventListAggregation

      def initialize(host, port, on_event: nil, on_disconnect: nil)
        @host          = host
        @port          = port
        @on_event      = on_event
        @on_disconnect = on_disconnect

        @command_queue  = Thread::Queue.new
        @promises_mutex = Mutex.new
        @promises       = {}
        @buffers        = {} # action_id => Array<raw frame> for in-flight EventList replies
        @socket         = nil
        @writer_thread  = nil
        @reader_thread  = nil
        @stopping       = false
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

      # Remove a pending Promise without resolving it (e.g. after a caller
      # timeout) so the pending map does not grow unbounded.
      def unregister_promise(action_id)
        @promises_mutex.synchronize do
          @promises.delete(action_id)
          @buffers.delete(action_id)
        end
      end

      # Reject all pending promises with the given error (thread-safe).
      def reject_all_promises(error)
        promises = @promises_mutex.synchronize do
          @buffers.clear
          @promises.values.tap { @promises.clear }
        end
        promises.each { |p| p.reject(error) }
      end

      # Stop both threads gracefully. Blocks until they exit.
      def stop
        return unless @writer_thread&.alive? || @reader_thread&.alive?

        @stopping = true
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
        rescue IOError, SystemCallError
          break # socket closed or peer reset — reader_loop handles caller notification
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
        handle_unexpected_disconnect('Disconnected: EOF from server')
      rescue IOError, Errno::EBADF
        handle_unexpected_disconnect('Disconnected') unless @stopping
      rescue StandardError => e
        handle_unexpected_disconnect("Reactor read error: #{e.message}")
      end

      # Notify the client and fail every blocked caller when the link drops
      # without an explicit #stop request.
      def handle_unexpected_disconnect(message)
        @on_disconnect&.call
        reject_all_promises(RuntimeError.new(message))
      end

      def resolve_promise(action_id, raw_data)
        promise = @promises_mutex.synchronize do
          @buffers.delete(action_id)
          @promises.delete(action_id)
        end
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
