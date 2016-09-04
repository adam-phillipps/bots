require_relative 'job'

module Smash
  class DefaultTask < Job

    attr_reader :identity, :instance_url, :params
    def initialize(id, msg)
      @params = JSON.parse(msg.body)
      instance_url # sets the url <- hostname in instance metadata
      # sets the 'idetity' <- comes from backlog message and is only for demo
      # TODO: identity should be removed after the demo and abstracted into its
      # own 'Task' class, instead of living in the "example"-ish Task
      identity
      @start_time = Time.now.to_i
      super(id, msg)
    end

    def finished_task
      # TODO: move identity to a demo specific class ASAP
      sitrep_message(identity: identity, extraInfo: { task: @params })
    end

    def identity
      # TODO: move this method to a demo specific class ASAP
      @identity ||= @params['identity'].to_s || 'not-aquired'
    end

    def instance_url
      # TODO: ??? move this method to a demo specific class ASAP???
      @instance_url ||= 'https://test-url.com'
      # @url ||= HTTParty.get('http://169.254.169.254/latest/meta-data/hostname').parsed_response
    end

    def run
      byebug
      # TODO: remove identity after demo
      message = sitrep_message(
        extraInfo: @params,
        identity: identity,
        url: instance_url
      )
      logger.info message
      pipe_to(:status_stream) { message }
      # job specific run instructions

      # TODO: move this method to a demo specific class ASAP
      # testing begins
      @mock_updates_thread =
        send_frequent_status_updates(
          interval: 5,
          content: sitrep_message(extraInfo: { 'task-run-time' => task_run_time })
        )
      sleep rand(30..60)
      Thread.kill(@mock_updates_thread)
      # testing over

      logger.info(sitrep_message(finished_task))
      pipe_to(:status_stream) { finished_task }
    end

    def valid?
      # job specific validity check
      # TODO: move this to a demo specific class ASAP and replace with the
      # line below it for a default example
      @valid ||= !@params['identity'].nil?
      # @valid ||= @params.kind_of? Hash
    end
  end
end
