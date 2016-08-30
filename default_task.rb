require_relative 'job'

module Smash
  class DefaultTask < Job
    def initialize(id, msg)
      byebug
      super(id, msg)
      @params = JSON.parse(msg.body)
    end

    def run
      # job specific run instructions
      logger.info("job running...\n#{run_params}")
      sleep(10)
      logger.info("finished job!\n#{finished_job}")
    end


    def valid?
      # job specific validity check
      @valid ||= @params.kind_of? Hash
    end
  end
end
