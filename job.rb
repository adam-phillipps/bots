require 'open3'
require_relative 'administrator'

class Job
  include Administrator
  attr_reader :board, :instance_id, :message

  def initialize(msg, instance_id)
    send_status_to_stream(self_id,
      {
        type:         'SitRep',
        content:      'job-started'
      }.to_json
    )
    @instance_id = instance_id
    @message = msg
    @board = backlog_address
    @params = JSON.parse(msg.body)
  end

  def finished_job
    begin
      update_message_body(
        type: 'SitRep',
        content: 'job-finished',
        extraInfo: @params
      )
    rescue Exception => e
      logger.error format_error_message(e)
    end
  end

  def run_params # refactor this.  it's just key.to_sym
    @run_params ||= @params
  end

  def run
    logger.info("job running...\n#{run_params}")
    logger.info("waiting for job to finish...")
    sleep(10)
    logger.info("finished job!\n#{finished_job}")
  end

  def update_status(finished_message = nil)
    begin
      logger.info("progressing through status...\n" +
        "\tcurrent_board is #{@board}")

      from = @board
      to = next_board

      sqs.delete_message(queue_url: from, receipt_handle: receipt_handle)

      status = to == finished_address ? 'job-finished' : 'job-running'
      message = to == finished_address ? finished_message : message_body

      send_status_to_stream(
        self_id, update_message_body(
          type: 'SitRep',
          content: status,
          extraInfo: message
        )
      )

      sqs.send_message(queue_url: to, message_body: message)
      unless finished_message.nil?
        logger.info(format_finished_body(message))
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

      logger.info("updated..\n\tcurrent board is #{@board}...")
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
