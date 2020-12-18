# frozen_string_literal: true

module Mutant
  module Parallel
    class Worker
      include Adamantium::Flat, Anima.new(
        :handle,
        :index,
        :var_active_jobs,
        :var_final,
        :var_running,
        :var_sink,
        :var_source
      )

      private(*anima.attribute_names)

      public :index

      def self.start(world:, block:, process_name:, **attributes)
        new(handle: Child.start(world, process_name, block), **attributes)
      end

      # Run worker payload
      #
      # @return [self]
      def call
        loop do
          job = next_job or break

          job_start(job)

          result = handle.execute(job.payload)

          job_done(job)

          break if add_result(result)
        end

        finalize

        self
      end

      def term
        handle.term
      end

    private

      def next_job
        var_source.with do |source|
          source.next if source.next?
        end
      end

      def add_result(result)
        var_sink.with do |sink|
          sink.result(result)
          sink.stop?
        end
      end

      def job_start(job)
        var_active_jobs.with do |active_jobs|
          active_jobs << job
        end
      end

      def job_done(job)
        var_active_jobs.with do |active_jobs|
          active_jobs.delete(job)
        end
      end

      def finalize
        var_final.put(nil) if var_running.modify(&:pred).zero?
      end

      class Handle
        include Anima.new(:process, :pid, :connection)

        def execute(payload)
          connection.send(payload).receive
        end

        def term
          process.kill('TERM', pid)
          process.wait(pid)
        end
      end

      class Child
        include Anima.new(:block, :connection)

        def call
          loop do
            connection.send(block.call(connection.receive))
          end
        end

        def self.start(world, process_name, block)
          io      = world.io
          process = world.process

          request  = Pipe.from_io(io)
          response = Pipe.from_io(io)

          pid = process.fork do
            world.thread.current.name = process_name
            world.process.setproctitle(process_name)

            Child.new(
              block:      block,
              connection: Pipe::Connection.from_pipes(reader: request, writer: response)
            ).call
          end

          Handle.new(
            pid:        pid,
            process:    process,
            connection: Pipe::Connection.from_pipes(reader: response, writer: request)
          )
        end
      end
    end # Worker
  end # Parallel
end # Mutant
