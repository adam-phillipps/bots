require_relative './lib/cloud_powers/synapse/pipe'
require_relative './lib/cloud_powers/synapse/queue'

module Smash
  class Job
    include Smash::CloudPowers::Synapse::Pipe
    include Smash::CloudPowers::Synapse::Queue
    attr_reader :instance_id, :message

    def initialize(id, msg)
      @instance_id = id
      @message = msg
      @board = build_board(:backlog)
    end

    def update_status
      begin
        message = "Progressed through states...\n\t#{@board.name} -> #{@board.next_board}"
        logger.info message

        delete_queue_message(@board.name)
        @board = build_board(@board.next_board)

        send_message(@board.name, body)
        pipe_to(:status_stream) { sitrep_message(message) }
      rescue Exception => e
        error_message = format_error_message(e)
        logger.error "Problem updating status:\n#{error_message}"
        errors.push_error!(:workflow, error_message)
      end
    end

    def sitrep_message(message)
        situation = @board.name == 'finished' ? 'finished' : 'in-progress'
        report = message
        sitrep_alterations = { type: 'SitRep', content: situation, extraInfo: report }
        update_message_body(sitrep_alterations)
    end
  end
end
