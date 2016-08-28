require 'dotenv'
Dotenv.load('.neuron.env')
require_relative './lib/cloud_powers/aws_resources'
require_relative './lib/cloud_powers/auth'
require_relative './lib/cloud_powers/delegator'
require_relative './lib/cloud_powers/self_awareness'
require_relative './lib/cloud_powers/smash_error'
require_relative './lib/cloud_powers/synapse/pipe'
require_relative './lib/cloud_powers/synapse/queue'

module Smash
  class Neuron
    include CloudPowers::Auth
    include CloudPowers::AwsResources
    include CloudPowers::Helper
    include CloudPowers::SelfAwareness
    include CloudPowers::Synapse

    attr_accessor :instance_id, :job_status, :workflow_status

    def initialize
      # begin
        byebug
        Smash::CloudPowers::SmashError
        get_awareness!
        # @status_thread = Thread.new { send_frequent_status_updates(15) }
        think
    #   rescue Exception => e
    #     error_message = format_error_message(e)
    #     logger.fatal "Rescued in initialize method:\n\t#{error_message}"
    #     die!
    #   end
    end

    def current_ratio
      backlog = get_count(backlog_address)
      wip = get_count(bot_counter_address)

      ((death_threashold * backlog) - wip).ceil
    end

    def death_ratio_acheived?
      !!(current_ratio >= death_threashold)
    end

    def death_threashold
      @death_threashold ||= (1.0 / env('ratio_denominator').to_f)
    end

    def think
      catch :die do
        byebug
        until should_stop?
          poll(:backlog) do |msg, stats|
            begin
              job = Delegator.build_job(@instance_id, msg)
              catch :failed_job do
                catch :workflow_completed do
                  job.valid? ? process_job(job) : process_invalid_job(job)
                end
              end
            rescue JSON::ParserError => e
              error_message = format_error_message(e)
              logger.error error_message
              errors.push_error!(:workflow, error_message)
              pipe_to(:status_stream) { error_message }
            end
          end
        end
      end
      die!
    end

    def process_invalid_job(job)
      logger.info("invalid job:\n#{format_finished_body(job.message_body)}")
      sqs.delete_message(
        queue_url: backlog_address,
        receipt_handle: job.receipt_handle
      )
    end

    def process_job(job)
      logger.info("Job found:\n#{job.message_body}")
      job.update_status
      job.run
      job.update_status(job.finished_job)
    end

    def should_stop?
      !!(time_is_up? ? death_ratio_acheived? : false)
    end

    def time_is_up?
      (run_time % 60) < 5
    end

    def death_ratio_acheived?
      !!(current_ratio >= death_threashold)
    end

    def current_ratio
      backlog = get_count(:backlog_queue_address)
      wip = get_count(:count_queue_address)

      ((death_threashold * backlog) - wip).ceil
    end
  end
end

Smash::Neuron.new
