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

    attr_reader :instance_id, :message, :message_body, :board

    def initialize(id, msg)
      @instance_id = id
      @message = msg
      @message_body = msg.body
      @board = build_board(:backlog)
    end

    def update_status
      begin
        message = "Next state...#{@board.name} -> #{@board.next_board}"
        logger.info message
        # TODO: fugure out how to make this more better.  this way creates another
        # contract you have to follow for the Task class (which could be ok)
        update = custom_sitrep(message)

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

    def sitrep_message(opts = {})
      # TODO: find better implementation of merging nested hashes
      # this should be fixed with ::Helper#update_message_body
        situation =
          @board.name == 'finished' ? 'workflow-completed' : 'workflow-in-progress'

        extra_info = {}
        if opts.kind_of?(Hash) && opts[:extraInfo]
          custom_info = opts.delete(:extraInfo)
          extra_info = { 'task-run-time' => task_run_time }.merge(custom_info)
        else
          opts = {}
        end

        sitrep_alterations = {
          type: 'SitRep',
          content: situation,
          extraInfo: extra_info
        }.merge(opts)
        update_message_body(sitrep_alterations)
    end

    def task_run_time
      # @start_time is in the Task class
      Time.now.to_i - @start_time
    end
  end
end
