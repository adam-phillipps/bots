require 'dotenv'
Dotenv.load(".crawl_bot.env")
require_relative 'administrator'
require_relative 'job'

class CrawlBot
  include Administrator

  def initialize
    begin


      @status_thread = Thread.new { send_frequent_status_updates() }
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
            job = Job.new(msg, self_id)
            catch :failed_job do
              catch :workflow_completed do
                job.valid? ? process_job(job) : process_invalid_job(job)
              end
              wait_for_search(job)
            end
          rescue JSON::ParserError => e
            message = format_error_message(e)
            errors[:workflow] << message
            send_status_to_stream(
              self_id, update_message_body(
                type: 'SitRep',
                content: 'job-failed',
                extraInfo: message
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
    logger.info("Finished job: #{job.run_params}\n \
      with:\n#{format_finished_body(job.finished_job)}\n \
      Sleeping for #{wait_time} seconds...")

    sleep(wait_time) # take this out when the logic moves to the java
  end

  def process_job(job)
    logger.info("Job found:\n#{job.message_body}")
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
    (run_time % 60) > 5
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
    @polling_sleep_time ||= ENV['POLLING_SLEEP_TIME'].to_i # 5
  end

  def s3
    @s3 ||= Aws::S3::Client.new(
      region: region,
      credentials: creds
    )
  end

  def for_each_id_send_message_to(board, ids, message)
    ids.each do |id|

      sqs.send_message(
        queue_url: board,
        message_body: { "#{id}": "#{message}" }.to_json
      )
      # TODO:
      # resend unsuccessful messages
    end
    true
  end

  def creds
    @creds ||= Aws::Credentials.new(
      ENV['AWS_ACCESS_KEY_ID'],
      ENV['AWS_SECRET_ACCESS_KEY'])
  end
end

CrawlBot.new
