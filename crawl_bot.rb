require_relative './config'
# require_relative './job'

class Worker
  include Config

  def initialize
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
          if JSON.parse(msg.body).has_key?('Records')
            puts "\n\nPossible job found:\n\n#{JSON.parse(msg.body)}"
            byebug
            catch :no_such_job_in_backlog do
              job = 'testing'
              run_job(job)
              puts "finished job:"
            end
          else
            sqs.delete_message({
              queue_url: backlog_address,
              receipt_handle: msg.receipt_handle
            })
          end
        rescue JSON::ParserError => e
          puts "Trouble with #{msg.body}:\n____#{e}\n"
        end
        puts 'Polling....'
      end
    end
    ec2.terminate_instancers(ids: [self_id])
  end

  def should_stop?
    # if you're the last one, (in active state) don't kill yourself
    if hour_mark_approaches?
      death_ratio_acheived? ? true : false
    else
      false
    end
  end

  def hour_mark_approaches?
    ((Time.now.to_i - boot_time) % 3600) > 3300
  end

  def death_ratio_acheived?
    death_ratio >= death_threashold
  end

  def death_ratio #
    counts = [backlog_address, wip_address].map do |board|
      sqs.get_queue_attributes(
        queue_url: board,
        attribute_names: ['ApproximateNumberOfMessages']
      ).attributes['ApproximateNumberOfMessages'].to_f
    end

    backlog = counts.first
    wip = counts.last
    wip = wip <= 0.0 ? 1.0 : wip # guards against irrational values
    backlog / wip
  end

  def run_job(job)
    sleep rand(polling_sleep_time)
  end

  def self_id # hard code a value here for testing
    @id ||= 'fdasasfd' # HTTParty.get('http://169.254.169.254/latest/meta-data/instance-id')
  end

  def boot_time # use `Time.now.to_i` instead of ec2 api call for testing
    @instance_boot_time ||= Time.now.to_i# bot_ec2.describe_instances(
                              # instance_ids:[self_id]).reservations[0].instances[0].launch_time.to_i
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
      credentials: maker_creds
    )
  end

  def creds
    @creds ||= Aws::Credentials.new(
      ENV['BOT_AWS_ACCESS_KEY_ID'],
      ENV['BOT_AWS_SECRET_ACCESS_KEY'])
  end
end

CrawlBot.new