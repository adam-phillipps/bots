require 'dotenv'
Dotenv.load(".crawl_bot.env")
require_relative 'config'
require_relative 'job'
require 'json'

class CrawlBot
  include Config

  def initialize
    @run_time = rand(14400) + 7200 # random seconds from 2 to 6 hours
    @start_time = Time.now.to_i
    die!
    poll
  end

  def poll
    until should_stop? do
      puts 'Polling....'
      sleep rand(polling_sleep_time)
      backlog_poller.poll(
        wait_time_seconds: nil,
        max_number_of_messages: 1,
        visibility_timeout: 10 # keep message invisible long enough to process to wip
      ) do |msg, stats|
        begin
          body = JSON.parse(msg.body)
          if valid_job?(body)
            puts "\n\nPossible job found:\n#{body}"

            job = Job.new(msg, backlog_address)
            update_status(job)
            add_self_to_working_bots_count
            job.run

            send_job_to_finished_queue(job.finished_job)

            random_wait_time = rand(10) + 10
            puts "Finished job: #{job.run_params}\nwith:\n#{job.finished_job}\n \
              Sleeping for #{random_wait_time} seconds..."
            sleep(random_wait_time) # take this out when the logic moves to the java
          else
            puts "body: #{msg.body}"
            sqs.delete_message(
              queue_url: backlog_address,
              receipt_handle: msg.receipt_handle
            )
          end
        rescue JSON::ParserError => e
          puts "Trouble with #{msg.body}:\n#{e}"
        end
        puts 'Polling....'
      end
    end
    die!
  end

  def self_id
    @id ||= HTTParty.get('http://169.254.169.254/latest/meta-data/instance-id')
  end

  def boot_time
    @instance_boot_time ||=
      bot_ec2.describe_instances(instance_ids:[self_id]).
        reservations[0].instances[0].launch_time.to_i
  end

  def send_job_to_finished_queue(message)
    sqs.send_message(
      queue_url: finished_address,
      message_body: message
    )
  end

  def add_self_to_working_bots_count
    @counter = sqs.send_message(
      queue_url: bot_counter_address,
      message_body: { id: self_id, time: Time.now }.to_json
    )
  end

  def die!
    counter_poller.poll(max_number_of_messages: 1) do |msg|
      counter_poller.delete_message(msg)
      throw :stop_polling
    end
    ec2.terminate_instances(ids: [self_id])
  end

  def valid_job?(body)
    !!(body.has_key?('productId') &&
        body.has_key?('title'))
  end

  def should_stop?
    !!(time_is_up? ? death_ratio_acheived? : false)
  end

  def time_is_up?
    !!((@start_time + @run_time) < Time.now.to_i)
  end

  def death_ratio_acheived?
    !!(current_ratio >= death_threashold)
  end

  def current_ratio
    backlog = get_count(backlog_address)
    wip = get_count(wip_address)

    (((1.0 / jobs_ratio_denominator) * backlog) - wip).ceil
  end

  def death_threashold
    @death_threashold ||= 1.0 / ENV['RATIO_DENOMINATOR'].to_f
  end

  def polling_sleep_time
    @polling_sleep_time ||= ENV['POLLING_SLEEP_TIME'].to_i # 5
  end

  def backlog_poller
    @backlog_poller ||= Aws::SQS::QueuePoller.new(backlog_address)
  end

  def s3
    @s3 ||= Aws::S3::Client.new(
      region: region,
      credentials: creds
    )
  end

  def update_status(job)
    sqs.delete_message(
      queue_url: job.previous_board,
      receipt_handle: job.receipt_handle
    )

    sqs.send_message(
      queue_url: job.next_board,
      message_body: job.message.body
    )
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

  def creds
    @creds ||= Aws::Credentials.new(
      ENV['AWS_ACCESS_KEY_ID'],
      ENV['AWS_SECRET_ACCESS_KEY'])
  end
end

CrawlBot.new
