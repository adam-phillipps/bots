require 'open3'
require_relative 'administrator'

class Job
  include Administrator
  attr_reader :board, :identity, :instance_id, :message, :params

  def initialize(msg, instance_id, identity)
    send_status_to_stream(
      self_id, update_message_body(
        url:          url,
        type:         'SitRep',
        content:      'job-started'
      )
    )
    @identity = identity
    @instance_id = instance_id

    @message = msg
    @board = backlog_address
    @params = JSON.parse(msg.body)
  end

  def finished_job
    begin
      update_message_body(
        url:          url,
        type:       'SitRep',
        content:    'job_finished',
        extraInfo:  @params
      )
    rescue Exception => e
      logger.error format_error_message(e)
    end
  end

  def run_params # refactor this.  it's just key.to_sym
    @run_params ||= @params
  end

  def run
    @started_job_time = Time.now.to_i
      message =
        lambda do
          run_time = Time.now.to_i - @started_job_time
          update_message_body(
            url:          url,
            type:         'SitRep',
            content:      'job_running',
            extraInfo:    { job: run_params, run_time: run_time }
          )
        end
    logger.info "Task starting... #{message.call}"

    @task_thread = Thread.new do
      while true
        logger.info "Task running... #{message.call}"
        send_status_to_stream(self_id, message.call)
        sleep 3
      end
    end

    system_command =
      "java -jar -DmodelIndex=#{identity} " +
      '-DuseLocalFiles=false roas-simulator-1.0.jar'
    error, results, status = Open3.capture3(system_command)
    total_run_time = Time.now.to_i - @started_job_time

    Thread.kill(@task_thread) unless @task_thread.nil?

    logger.info("finished job! #{finished_job}")
    send_status_to_stream(
      self_id, update_message_body(
        url:          url,
        type:         'SitRep',
        content:      'job_finished',
        extraInfo:    {
          job: run_params,
          run_time: total_run_time,
          results: results,
          errors: error,
          status: status
        }
      )
    )
  end

  def update_status(finished_message = nil)
    begin

      from = @board
      to = next_board

      sqs.delete_message(queue_url: from, receipt_handle: receipt_handle)

      status = to == finished_address ? 'job_finished' : 'job_starting'
      message = to == finished_address ? finished_job : message_body

      send_status_to_stream(
        self_id, update_message_body(
          url:          url,
          type:         'SitRep',
          content:      status,
          extraInfo:    message
        )
      )

      sqs.send_message(queue_url: to, message_body: message)
      unless finished_message.nil?
        throw :workflow_completed
      end

      poller(next_board_name).poll(
        idle_timeout: 60,
        skip_delete: true,
        max_number_of_messages: 1
      ) do |msg|
        @message = msg
        @board = to
        throw :stop_polling
      end

    rescue Exception => e
      error_message = "workflow error:\n#{e.message}\n" + e.backtrace.join('\n')
      errors[:workflow] << error_message
      logger.error("Problem updating status:\n#{error_message}")
      throw :die if errors[:workflow].count > 3
    end
  end

  def next_board_name(b = nil)
    (b || @board) == backlog_address ? 'wip' : 'finished'
  end

  def valid?
    @valid ||= @params.kind_of? Hash
  end

  def message_body
    @message.body
  end

  def next_board
    @board == backlog_address ? wip_address : finished_address
  end

  def previous_board
    @board == finished_address ? wip_address : backlog_address
  end

  def receipt_handle
    @message.receipt_handle
  end

  def notification_worker
    @notification_worker ||= SqsQueueNotificationWorker.new(region, sqs_queue_url)
  end

  def creds
    @creds ||= Aws::Credentials.new(
      ENV['AWS_ACCESS_KEY_ID'],
      ENV['AWS_SECRET_ACCESS_KEY'])
  end
end
