require_relative './config'

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
      puts "There is a problem between starting and finishing the crawler:\n#{e}"
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

  def next_board
    @board = @board == backlog_address ? wip_address : finished_address
  end

  def previous_board
    @board = @board == finished_address ? wip_address : backlog_address
  end

  def receipt_handle
    @receipt_handle = @message.receipt_handle
  end

  def notification_worker
    @notification_worker ||= SqsQueueNotificationWorker.new(region, sqs_queue_url)
  end

  def completion_handler
    lambda do |notification|
      if (notification['jobId'] == job_id && ['COMPLETED', 'ERROR'].include?(notification['state']))
        notification_worker.stop
      end
    end
  end

  def start_notification_worker
    notification_worker.add_handler(completion_handler)
    notification_worker.start
  end
end
