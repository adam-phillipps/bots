require_relative 'config'

class Job
  include Config
  attr_reader :message, :board

  def initialize(msg, board)
    @message = msg
    @params = JSON.parse(msg.body)
    @board = board
  end

  def finished_job
    begin
      @finished_job ||= File.read('data.json')
    rescue Errno::ENOENT => e
      log "There was a problem finding the finished file" +
        "which usually means there was a problem between starting and finishing the crawler:\n#{e}"
    end
  end

  def run_params
    @run_params ||= {
      product_id: @params['productId'],
      title: @params['title']
    }
  end

  def run
    log "job running...\n#{run_params}"
    system(
      "java -jar google-scraper.jar #{run_params[:product_id]} \"#{run_params[:title]}\""
    )
    log "finished job!\n#{run_params}"
  end

  def update_status(finished_message = nil)
    begin
      from = @board
      to = next_board
      sqs.delete_message(
        queue_url: from,
        receipt_handle: receipt_handle
      )

      message = finished_message.nil? ? message_body : finished_message
      sqs.send_message(
        queue_url: to,
        message_body: message
      )

      poller(next_board_name).poll(max_number_of_messages: 1, skip_delete: true) do |msg|
        @message = msg
        @board = to
        throw :stop_polling
      end
      log "progressing through status...\ncurrent_board is #{@board}"
    rescue Exception => e
      log "Problem updating status:\n#{e}"
    end
  end

  def next_board_name
    case @board
    when backlog_address
      'wip'
    when wip_address
      'finished'
    when bot_counter_address
      'counter'
    else
      ''
    end
  end

  def valid?
    !!(
        begin
          @params.has_key?('productId') &&
            @params.has_key?('title')
        rescue Exception => e
          log "invalid job!:\n#{self}\n\n#{e}"
          false
        end
      )
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
