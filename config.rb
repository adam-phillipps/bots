require 'aws-sdk'
Aws.use_bundled_cert!
require 'httparty'
require 'syslog/logger'
require 'logger'
require 'io/console'
require 'byebug'

module Config
  def poller(board)
    begin
      eval("#{board}_poller")
    rescue NameError => e
      puts "There isn't such a poller available"
    end
  end

  def backlog_poller
    @backlog_poller ||= Aws::SQS::QueuePoller.new(backlog_address)
  end

  def wip_poller
    @wip_poller ||= Aws::SQS::QueuePoller.new(wip_address)
  end

  def counter_poller
    @counter_poller ||= Aws::SQS::QueuePoller.new(bot_counter_address)
  end

  def sqs
    @sqs ||= Aws::SQS::Client.new(credentials: creds)
  end

  def ec2
    @ec2 ||= Aws::EC2::Client.new(
      region: region,
      credentials: creds
    )
  end

  def backlog_address
    @backlog_address ||= ENV['BACKLOG_ADDRESS']
  end

  def wip_address
    @wip_address ||= ENV['WIP_ADDRESS']
  end

  def finished_address
    @finished_address ||= ENV['FINISHED_ADDRESS']
  end

  def bot_counter_address
    @bot_counter_address ||= ENV['BOT_COUNTER_ADDRESS']
  end

  def needs_attention_address
    @needs_attention_address ||= ENV['NEEDS_ATTENTION_ADDRESS']
  end

  def region
    @region ||= ENV['AWS_REGION']
  end


  def jobs_ratio_denominator
    @jobs_ratio_denominator ||= ENV['RATIO_DENOMINATOR'].to_i
  end

  def ec2
    @ec2 ||= Aws::EC2::Client.new(
      region: region,
      credentials: creds)
  end

  def get_count(board)
    sqs.get_queue_attributes(
      queue_url: board,
      attribute_names: ['ApproximateNumberOfMessages']
    ).attributes['ApproximateNumberOfMessages'].to_f
  end

  def filename
    @filename ||= ENV['LOG_FILE']
  end

  def log(message)
    IO.write filename, "#{message} + \n"
  end

  def format_finished_body(body)
    body.split(' ')[0..10].join(' ') + '...'
  end

  def send_logs_to_s3
    File.open(filename) do |file|
      s3.put_object(
        bucket: log_bucket,
        key: self_id,
        body: file
      )
    end
  end

  def log_bucket
    @log_bucket ||= ENV['LOGS_BUCKET']
  end
end
