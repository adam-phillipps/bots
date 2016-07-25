require 'open3'
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
      puts "There was a problem finding the finished file" +
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
    puts "job running...\n#{run_params}"

    error, results, status =
      Open3.capture3(
        "java -jar #{scraper} \
          #{run_params[:product_id]} \
          '#{run_params[:title]}' >&2"
    )

    unless status.success?
      puts error
      throw :failed_job
    end
    puts results

    until Dir.glob('*data.json').first
      puts "waiting for job to finish. status: #{status}..."
      sleep 10
      puts "finished job!\n#{run_params}"
    end
  end

  def update_status(finished_message = nil)
    begin
      puts "progressing through status...\n" +
        "\tcurrent_board is #{@board}"

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

      unless finished_message.nil?
        puts format_finished_body(message)
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

      puts "updated..\n\tcurrent board is #{@board}..."
    rescue Exception => e
      puts "Problem updating status:\n#{e}"
      throw e
    end
  end

  def next_board_name
    @board == backlog_address ? 'wip' : 'finished'
  end

  def valid?
    !!(
        begin
          @params.has_key?('productId') &&
            @params.has_key?('title')
        rescue Exception => e
          puts "invalid job!:\n#{self}\n\n#{e}"
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
