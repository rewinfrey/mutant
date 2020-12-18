# frozen_string_literal: true

module Mutant
  # Pipe abstraction
  class Pipe
    include Adamantium::Flat, Anima.new(:reader, :writer)

    # Run block with pipe in binmode
    #
    # @return [undefined]
    def self.with(io)
      io.pipe(binmode: true) do |(reader, writer)|
        yield new(reader: reader, writer: writer)
      end
    end

    def self.from_io(io)
      reader, writer = io.pipe(binmode: true)
      new(reader: reader, writer: writer)
    end

    # Writer end of the pipe
    #
    # @return [IO]
    def to_writer
      reader.close
      writer
    end

    # Parent reader end of the pipe
    #
    # @return [IO]
    def to_reader
      writer.close
      reader
    end

    class Encode
      include Concord.new(:io)

      def receive
        Marshal.load(io.receive)
      end

      def send(value)
        io.send(Marshal.dump(value))
      end

      def self.from_io(io)
        self.new(Frame.new(io))
      end
    end

    class Frame
      include Concord.new(:io)

      HEADER_FORMAT = 'N'
      MAX_BYTES     = (2**32).pred
      HEADER_SIZE   = 4

      def receive
        header = io.read(HEADER_SIZE) or fail 'Unexpected EOF'
        io.read(Mutant::Util.one(header.unpack(HEADER_FORMAT)))
      end

      def send(body)
        bytesize = body.bytesize

        fail 'message to big' if bytesize > MAX_BYTES

        io.write([bytesize].pack(HEADER_FORMAT))
        io.write(body)
        self
      end
    end

    class Connection
      include Anima.new(:reader, :writer)

      def receive
        reader.receive
      end

      def send(value)
        writer.send(value)
        self
      end

      def self.from_pipes(reader:, writer:)
        new(
          reader: Encode.from_io(reader.to_reader),
          writer: Encode.from_io(writer.to_writer)
        )
      end
    end
  end # Pipe
end # Mutant
