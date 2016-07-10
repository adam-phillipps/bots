require_relative 'config'

class Job
  include Config
  attr_reader :message, :board

  def initialize(msg, board)
    puts 'job running'
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
    system(
      "java -jar google-scraper.jar #{run_params[:product_id]} \"#{run_params[:title]}\""
    )
  end

  def update_status(from = @board, to = next_board)
    begin
      sqs.delete_message(
        queue_url: from,
        receipt_handle: receipt_handle
      )

      sqs.send_message(
        queue_url: to,
        message_body: message_body
      )

      poller(next_board_name).poll(max_number_of_messages: 1, skip_delete: true) do |msg|
        @message = msg
        @board = to
        throw :stop_polling
      end
      log "progressing through status...\n"
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
    when finished_address
      ''
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
