require_relative 'job'

module Smash
  class DefaultTask < Job
    def initialize(id, msg)
      @start_time = Time.now.to_i
      super(id, msg)
      @params = JSON.parse(msg.body)
    end

    def run
      logger.info(sitrep_message(message_body))
      pipe_to(:status_stream) { sitrep_message(message_body) }
      # job specific run instructions

      # testing begins
      @mock_updates_thread =
        send_frequent_status_updates(
          interval: 10,
          content: sitrep_message(task_run_time)
        )
      sleep rand(60)
      Thread.kill(@mock_updates_thread)
      # testing over

      logger.info(sitrep_message(finished_job))
      pipe_to(:status_stream) { sitrep_message(finished_job) }
    end


    def valid?
      # job specific validity check
      @valid ||= @params.kind_of? Hash
    end
  end
end
