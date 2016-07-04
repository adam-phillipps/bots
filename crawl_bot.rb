require_relative 'config'
require 'dotenv'
Dotenv.load(".crawl_bot.env")
require 'json'

class CrawlBot
  include Config

  def initialize
    @run_time = rand(14400) + 7200 # random seconds from 2 to 6 hours
    @start_time = Time.now.to_i
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
          if possible_valid_job?(body)
            puts "\n\nPossible job found:\n#{body}"
            catch :no_such_job_in_backlog do
              job = Job.new(msg, backlog_address)
              make_self_known_to_the_world
              job.run
              puts "finished job: #{job.params}"
            end
          else
            puts "body: #{msg.body}"
            sqs.delete_message(
              queue_url: backlog_address,
              receipt_handle: msg.receipt_handle
            )
          end
        rescue JSON::ParserError => e
          puts "Trouble with #{msg.body}:\n____#{e}\n"
        end
        puts 'Polling....'
      end
    end
    die!
  end

  def make_self_known_to_the_world
    @counter ||= sqs.send_message(
      queue_url: bot_counter_address,
      message_body: { id: self_id, time: Time.now }.to_json
    )
  end

  def die!
    sqs.delete_message(
      queue_url: bot_counter_address,
      receipt_handle: @counter.receipt_handle
    )
    ec2.terminate_instances(ids: [self_id])
  end

  def possible_valid_job?(body)
    !!(body.has_key?('crawler_product_result_id') &&
        body.has_key?('title'))
  end

  def should_stop?
    !!(time_is_up? ? death_ratio_acheived? : false)
  end

  def time_is_up?
    !!((@start_time + @run_time) < Time.now.to_i)
  end

  def death_ratio_acheived?
    !!(death_ratio >= death_threashold)
  end

  def death_ratio
    backlog = get_count(backlog_address)
    wip = get_count(wip_address)

    wip = wip <= 0.0 ? 1.0 : wip # guards against irrational values
    backlog / wip
  end

  def self_id # hard code a value here for testing
    @id ||= HTTParty.get('http://169.254.169.254/latest/meta-data/instance-id')
  end

  def boot_time # use `Time.now.to_i` instead of ec2 api call for testing
    @instance_boot_time ||=
      bot_ec2.describe_instances(instance_ids:[self_id]).
        reservations[0].instances[0].launch_time.to_i
  end

  def death_threashold
    @death_threashold ||= ENV['DEATH_RATIO'].to_i # 10
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

  def creds
    @creds ||= Aws::Credentials.new(
      ENV['AWS_ACCESS_KEY_ID'],
      ENV['AWS_SECRET_ACCESS_KEY'])
  end
end

CrawlBot.new
