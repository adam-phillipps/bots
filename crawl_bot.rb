require 'dotenv'
# Dotenv.load("/home/ubuntu/crawler/.crawl_bot.env")
Dotenv.load(".crawl_bot.env")
require_relative 'administrator'
require_relative 'job'

class CrawlBot
  include Administrator

  attr_accessor :identity, :instance_id

  def initialize
    begin
      @status_thread = Thread.new { send_frequent_status_updates }
      poll
    rescue Exception => e
      logger.error("Rescued in initialize method:\n" +
        "#{[e.message, e.backtrace.join("\n")].join("\n")}")
      die!
    end
  end

  def poll
    catch :die do
      until should_stop? do
        sleep rand(polling_sleep_time)
        poller('backlog').poll(
          idle_timeout: 60,
          wait_time_seconds: nil,
          max_number_of_messages: 1,
          visibility_timeout: 10
        ) do |msg, stats|
          begin
            @identity = JSON.parse(msg.body)['identity']
            job = Job.new(msg, self_id, @identity)
            catch :failed_job do
              catch :workflow_completed do
                job.valid? ? process_job(job) : process_invalid_job(job)
              end
              send_status_to_stream(
                self_id, update_message_body(
                  content: 'workflow-completed',
                  extraInfo: job.run_params
                )
              )
            end
          rescue JSON::ParserError => e
            message = [@params.join("\n"), format_error_message(e)].join("\n")
            errors[:workflow] << message
            send_status_to_stream(
              self_id, update_message_body(
                url:          url,
                content:      'workflow-failed',
                extraInfo:    { error: message, job: job.run_params }
              )
            )
            throw :die if errors[:workflow].count > 5
            logger.error("Failed job:\n#{message}")
          end
          logger.info("Polling....\n")
        end
      end
    end
    die!
  end

  def wait_for_search(job)
    wait_time = 10
    # logger.info("Finished job: #{job.run_params}\n \
      # with:\n#{format_finished_body(job.finished_job)}\n \
      # Sleeping for #{wait_time} seconds...")

    sleep(wait_time) # take this out when the logic moves to the java
  end

  def process_job(job)
    logger.info("Job found: #{job.message_body}")
    send_status_to_stream(
      self_id, update_message_body(
        url:          url,
        type:         'SitRep',
        content:      'workflow-started',
        extraInfo:    job.params
      )
    )
    job.update_status
    job.run
    job.update_status(job.finished_job)
  end

  def process_invalid_job(job)
    logger.info("invalid job:\n#{format_finished_body(job.message_body)}")
    sqs.delete_message(
      queue_url: backlog_address,
      receipt_handle: job.receipt_handle
    )
  end

  def should_stop?
    !!(time_is_up? ? death_ratio_acheived? : false)
  end

  def time_is_up?
    # returns true when the hour mark approaches
    an_hours_time = 60 * 60
    five_minutes_time = 60 * 5

    return false if run_time < five_minutes_time
    run_time % an_hours_time < five_minutes_time
  end

  def run_time
    Time.now.to_i - boot_time
  end

  def death_ratio_acheived?
    !!(current_ratio >= death_threashold)
  end

  def current_ratio
    backlog = get_count(backlog_address)
    wip = get_count(bot_counter_address)

    ((death_threashold * backlog) - wip).ceil
  end

  def death_threashold
    @death_threashold ||= (1.0 / jobs_ratio_denominator.to_f)
  end

  def polling_sleep_time
    @polling_sleep_time ||= 10 # ENV['POLLING_SLEEP_TIME'].to_i # 5
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
