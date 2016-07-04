require_relative './config'

class Job
  include Config
  attr_reader :msg, :board

  def initialize(msg, board)
    @params = JSON.parse(msg.body)
    @board = board
  end

  def body
    JSON.parse(plain_text_body)
  end

  def finished_job
    unless @finished_job
      begin
        file = File.read('data.json')
        # @finished_job ||= JSON.parse(file).map { |result| result.to_json }
        @finished_job ||= file
      rescue Exception => e
        puts "there was something wrong with the file or it doesn't exist"
      end
    end
    @finished_job
  end

  def run_params
    @run_params ||= {
      product_id: @params['productId'],
      title: @params['title']
    }
  end

  def run
    system("java -jar google-scraper.jar #{run_params[:productId]} \"#{run_params[:title]}\"")
  end

  def next_board
    board == backlog_address ? wip_address : finished_address
  end

  def previous_board
    board == finished_address ? wip_address : backlog_address
  end

  def plain_text_body
    msg.body
  end


  def receipt_handle
    @receipt_handle = msg.receipt_handle
  end

  def update_status(to = next_board)
    sqs.send_message(
      queue_url: to,
      message_body: plain_text_body
    )

    @board = next_board if to == next_board
    delete_from_message_origination_board
  end

  def delete_from_message_origination_board
    if @board == wip_address || @board == backlog_address
      sqs.delete_message(
        queue_url: backlog_address,
        receipt_handle: receipt_handle
      )
    elsif @board == finished_address
      delete_from_wip_queue
    end
  end

  def delete_from_wip_queue
    puts 'deleting from wip queue'
    wip_poller.poll(max_number_of_messages: 1) do |msg|
      wip_poller.delete_message(msg)
      throw :stop_polling
    end
  end

  def delete_from_backlog_queue
    puts 'deleting from backlog queue'
    sqs.delete_message(
      queue_url: backlog_address,
      receipt_handle: receipt_handle
    )
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
