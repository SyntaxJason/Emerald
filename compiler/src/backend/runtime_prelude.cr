module Emerald
  module RuntimePrelude
    extend self

    def emit(io : IO)
      io << <<-PRELUDE
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
