require 'dotenv'
Dotenv.load
require 'aws-sdk'
Aws.use_bundled_cert!
require 'httparty'
require 'logger'
require 'byebug'

module Config
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

  def setup_logger
    logger_client ||= Logger.new(
      File.open(File.expand_path('../crawlBot.log', __FILE__), 'a+'))
    logger_client.level = Logger::INFO
    logger_client
  end

  def logger(msg)
    logger.info("\n#{Time.now}: #{msg}\n")
  end
end
