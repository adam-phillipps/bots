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
      File.read('data.json')
    rescue Errno::ENOENT => e
      # throw :scraper_problem
      log "There was a problem finding the finished file" +
        "which usually means there was a problem between starting and finishing the crawler:\n#{e}"
      # die! # discuss
    end
  end

  def run_params # refactor this.  it's just key.to_sym
    @run_params ||= {
      product_id: @params['productId'],
      title: @params['title']
    }
  end

  def run
    log "job running...\n#{run_params}"

    Dir.glob('*.json').each { |file| File.delete(file) }

    system(
      "java -jar #{scraper} #{run_params[:product_id]} \"#{run_params[:title]}\""
    )

    until Dir.glob('data.json').first
      log "waiting for job to finish..."
      sleep 10
    end
    log "finished job!\n#{run_params}"
  end

  def update_status(finished_message = nil)
    begin
      log "progressing through status...\n \
        current_board is #{@board}"

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

      poller(next_board_name).poll(
        idle_timeout: 60,
        skip_delete: true,
        max_number_of_messages: 1
      ) do |msg|
        @message = msg
        @board = to
        throw :stop_polling
      end

      log "updated current_board is #{@board}..."
    rescue Exception => e
      log "Problem updating status:\n#{e}"
      die!
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
