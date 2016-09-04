require 'dotenv'
Dotenv.load('.neuron.env')
require_relative 'default_task'
require_relative './lib/cloud_powers/aws_resources'
require_relative './lib/cloud_powers/auth'
require_relative './lib/cloud_powers/delegator'
require_relative './lib/cloud_powers/helper'
require_relative './lib/cloud_powers/self_awareness'
require_relative './lib/cloud_powers/smash_error'
require_relative './lib/cloud_powers/synapse/pipe'
require_relative './lib/cloud_powers/synapse/queue'

module Smash

  class Neuron
    include Smash::CloudPowers::Auth
    include Smash::CloudPowers::AwsResources
    include Smash::CloudPowers::Helper
    include Smash::CloudPowers::SelfAwareness
    include Smash::CloudPowers::Synapse
    include Smash::Delegator

    attr_accessor :instance_id, :job_status, :workflow_status

    def initialize
      # begin
        # Smash::CloudPowers::SmashError.build(:ruby, :workflow, :task)
        get_awareness!
        # @status_thread = Thread.new { send_frequent_status_updates(interval: 5) }
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
        until should_stop?
          poll(:backlog) do |msg, stats|
            begin
              catch :failed_job do
                byebug
                job = build_job(@instance_id, msg)
                catch :workflow_completed do
                  byebug
                  job.valid? ? process_job(job) : process_invalid_job(job)
                end
                byebug
                message =
                  update_message_body(
                    type: 'SitRep',
                    content: 'workflow-completed',
                    extraInfo: { message: "Completed: #{job.params}  Moving along..." }
                  )
                logger.info message
                pipe_to(:status_stream) { message }
              end
              byebug
            rescue JSON::ParserError => e
              error_message = format_error_message(e)
              logger.error error_message
              # errors.push_error!(:workflow, error_message)
              pipe_to(:status_stream) { error_message }
            end
          end
        end
      end
      # die!
    end

    def process_invalid_job(job)
      logger.info("invalid job:\n#{format_finished_body(job.message.body)}")
      sqs.delete_message(
        queue_url: backlog_address,
        receipt_handle: job.receipt_handle
      )
      # TODO: make sure this is sending a message to needs_attention too
    end

    def process_job(job)
      logger.info("Job found: #{job.message_body}")
      pipe_to(:status_stream) do
        sitrep_message(
          content:      'workflow-started',
          extraInfo:    job.params
        )
      end

      job.update_status
      job.run
      job.update_status(job.finished_job)
    end

    def should_stop?
      puts 'here'
      puts time_is_up?
      !!(time_is_up? ? death_ratio_acheived? : false)
    end

    def time_is_up?
      # returns true when the hour mark approaches
      an_hours_time = 60 * 60
      five_minutes_time = 60 * 5

      return false if run_time < five_minutes_time
      run_time % an_hours_time < five_minutes_time
    end

    def current_ratio
      backlog = get_count(:backlog_queue_address)
      wip = get_count(:count_queue_address)

      ((death_threashold * backlog) - wip).ceil
    end
  end
end

Smash::Neuron.new
