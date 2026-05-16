module Emerald
  module RuntimePrelude
    extend self

    def emit(io : IO)
      io << <<-PRELUDE
      require "http/client"
      require "socket"

      abstract class EmeraldBoxBase
      end

      class EmeraldBox(T) < EmeraldBoxBase
        getter value : T
        def initialize(@value : T); end

        def to_s(io : IO)
          io << @value.to_s
        end
      end

      class EmeraldResult
        @ok : Bool
        @payload : EmeraldBoxBase

        protected def initialize(@ok : Bool, @payload : EmeraldBoxBase); end

        def self.ok(v) : EmeraldResult
          EmeraldResult.new(true, EmeraldBox.new(v))
        end

        def self.err(e) : EmeraldResult
          EmeraldResult.new(false, EmeraldBox.new(e))
        end

        def is_ok? : Bool
          @ok
        end

        def is_err? : Bool
          !@ok
        end

        def raw_value : EmeraldBoxBase
          @payload
        end

        def to_s(io : IO)
          if @ok
            io << "Ok(" << @payload.to_s << ")"
          else
            io << "Err(" << @payload.to_s << ")"
          end
        end
      end


      module EmeraldRuntimeSocket
        @@mutex = Mutex.new
        @@next_handle = 1_i64
        @@sockets = {} of Int64 => TCPSocket
        @@listeners = {} of Int64 => TCPServer

        def self.connect(host : String, port : Int64) : Int64
          store_socket(TCPSocket.new(host, port.to_i32))
        end

        def self.listen(host : String, port : Int64) : Int64
          store_listener(TCPServer.new(host, port.to_i32))
        end

        def self.socket_open?(handle : Int64) : Bool
          @@mutex.synchronize { @@sockets.has_key?(handle) }
        end

        def self.listener_open?(handle : Int64) : Bool
          @@mutex.synchronize { @@listeners.has_key?(handle) }
        end

        def self.read_text(handle : Int64) : String
          socket_for(handle).gets_to_end
        end

        def self.read_line(handle : Int64) : String
          socket_for(handle).gets || ""
        end

        def self.write_text(handle : Int64, text : String) : Bool
          socket = socket_for(handle)
          socket << text
          socket.flush
          true
        end

        def self.close_socket(handle : Int64) : Bool
          socket = @@mutex.synchronize { @@sockets.delete(handle) }
          return false unless socket

          socket.close
          true
        rescue ex : Exception
          false
        end

        def self.close_listener(handle : Int64) : Bool
          listener = @@mutex.synchronize { @@listeners.delete(handle) }
          return false unless listener

          listener.close
          true
        rescue ex : Exception
          false
        end

        def self.accept(handle : Int64) : Int64
          store_socket(listener_for(handle).accept)
        end

        private def self.store_socket(socket : TCPSocket) : Int64
          @@mutex.synchronize do
            handle = @@next_handle
            @@next_handle += 1_i64
            @@sockets[handle] = socket
            handle
          end
        end

        private def self.store_listener(listener : TCPServer) : Int64
          @@mutex.synchronize do
            handle = @@next_handle
            @@next_handle += 1_i64
            @@listeners[handle] = listener
            handle
          end
        end

        private def self.socket_for(handle : Int64) : TCPSocket
          @@mutex.synchronize { @@sockets[handle]? } || raise "TCP connection is not open"
        end

        private def self.listener_for(handle : Int64) : TCPServer
          @@mutex.synchronize { @@listeners[handle]? } || raise "TCP listener is not open"
        end
      end

      class EmeraldFiber(T)
        @channel : Channel(T)
        @fiber : Fiber

        def initialize(&block : -> T)
          @channel = Channel(T).new(1)
          ch = @channel
          @fiber = spawn { ch.send(block.call) }
        end

        def self.spawn(&block : -> T) : EmeraldFiber(T) forall T
          EmeraldFiber(T).new(&block)
        end

        def await : T
          @channel.receive
        end
      end

      class EmeraldThread(T)
        @channel : Channel(T)
        @thread : Thread

        def initialize(&block : -> T)
          @channel = Channel(T).new(1)
          ch = @channel
          @thread = Thread.new { ch.send(block.call) }
        end

        def self.spawn(&block : -> T) : EmeraldThread(T) forall T
          EmeraldThread(T).new(&block)
        end

        def await : T
          @channel.receive
        end
      end

      PRELUDE
    end
  end
end
