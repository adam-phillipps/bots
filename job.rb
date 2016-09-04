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
        content:    'job-finished',
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
    logger.info("job running...#{run_params}")
    send_status_to_stream(
      self_id, update_message_body(
        url:          url,
        type:         'SitRep',
        content:      'job-started',
        extraInfo:    run_params
      )
    )
    @job_running_thread = Thread.new do
      send_frequent_status_updates(interval: 10, type: 'SitRep')
    end

    system_comand =
      "java -jar -DmodelIndex=\"#{identity}\" " +
      '-DuseLocalFiles=false roas-simulator-1.0.jar'

    error, result, status = Open3.capture3(system_comand)
    Thread.kill(@job_running_thread) unless @job_running_thread.nil?

    logger.info("finished job! #{finished_job}")
    send_status_to_stream(
      self_id, update_message_body(
        url:          url,
        type:         'SitRep',
        content:      'job-finished',
        extraInfo:    run_params.merge({ error: error, result: result, status: status })
      )
    )
  end

  def update_status(finished_message = nil)
    begin

      from = @board
      to = next_board

      sqs.delete_message(queue_url: from, receipt_handle: receipt_handle)

      status = to == finished_address ? 'job-finished' : 'job-starting'
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
