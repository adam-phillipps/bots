require_relative './lib/cloud_powers/aws_resources'
require_relative './lib/cloud_powers/synapse/pipe'
require_relative './lib/cloud_powers/synapse/queue'
require_relative './lib/cloud_powers/helper'

module Smash
  class Job
    include Smash::CloudPowers::Auth
    include Smash::CloudPowers::AwsResources
    include Smash::CloudPowers::Helper
    include Smash::CloudPowers::Synapse::Pipe
    include Smash::CloudPowers::Synapse::Queue

    attr_reader :instance_id, :message

    def initialize(id, msg)
      @instance_id = id
      @message = msg
      @board = build_board(:backlog)
      @message_body = msg.body
    end

    def update_status
      begin
        message = "Progressed through states...\n\t#{@board.name} -> #{@board.next_board}"
        logger.info message
        update = sitrep_message(message)

        delete_queue_message(@board.name)
        @board = build_board(@board.next_board)

        send_message(@board, update)
        pipe_to(:status_stream) { update }
      rescue Exception => e
        error_message = format_error_message(e)
        logger.error "Problem updating status:\n#{error_message}"
        # errors.push_error!(:workflow, error_message)
      end
    end

    def sitrep_message(message)
        situation = @board.name == 'finished' ? 'workflow-completed' : 'workflow-in-progress'
        report = message
        sitrep_alterations = { type: 'SitRep', content: situation, extraInfo: report }
        update_message_body(sitrep_alterations)
    end

    def task_run_time
      # @start_time is in the Task class
      Time.now.to_i - @start_time
    end
  end
end
