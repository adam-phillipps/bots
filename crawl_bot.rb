require 'dotenv'
Dotenv.load(".crawl_bot.env")
require 'json'
require_relative 'config'
require_relative 'job'

class CrawlBot
  include Config

  def initialize
    @count = 0
    begin
      @run_time = rand(14400) + 7200 # random seconds from 2 to 6 hours
      @start_time = Time.now.to_i
      poll
    rescue Exception => e
      log "Rescued in initialize method #{e.message}"
      die!
    end
  end

  def poll
    until should_stop? do
      sleep rand(polling_sleep_time)
      poller('backlog').poll(
        idle_timeout: 60,
        wait_time_seconds: nil,
        max_number_of_messages: 1,
        visibility_timeout: 10
      ) do |msg, stats|
        begin
          job = Job.new(msg, backlog_address)
          job.valid? ? process_job(job) : process_invalid_job(job)
        rescue JSON::ParserError => e
          log "Trouble with #{msg.body}:\n#{e}"
        end
        log "Polling....\n"
      end
    end
    die!
  end

  def process_job(job)
    log "Job found:\n#{job.message_body}"
    job.update_status

    job.run
    job.update_status(job.finished_job)

    random_wait_time = rand(10) + 10
    log "Finished job: #{job.run_params}\n \
      with:\n#{format_finished_body(job.finished_job)}\n \
        Sleeping for #{random_wait_time} seconds..."
    sleep(random_wait_time) # take this out when the logic moves to the java
  end

  def process_invalid_job(job)
    log "invalid job:\n#{format_finished_body(job.message_body)}"
    sqs.delete_message(
      queue_url: backlog_address,
      receipt_handle: job.receipt_handle
    )
  end

  def self_id
    @id ||= HTTParty.get('http://169.254.169.254/latest/meta-data/instance-id')
  end

  def boot_time
    @instance_boot_time ||=
      bot_ec2.describe_instances(instance_ids:[self_id]).
        reservations[0].instances[0].launch_time.to_i
  end

  def die!
    poller('counter').poll(max_number_of_messages: 1) do |msg|
      poller('counter').delete_message(msg)
      throw :stop_polling
    end
    send_logs_to_s3
    ec2.terminate_instances(ids: [self_id])
  end

  def should_stop?
    2 <= (@count += 1)
    # !!(time_is_up? ? death_ratio_acheived? : false)
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

  def s3
    @s3 ||= Aws::S3::Client.new(
      region: region,
      credentials: creds
    )
  end

  def creds
    @creds ||= Aws::Credentials.new(
      ENV['AWS_ACCESS_KEY_ID'],
      ENV['AWS_SECRET_ACCESS_KEY'])
  end
end

CrawlBot.new
