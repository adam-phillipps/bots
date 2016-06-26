require 'dotenv'
Dotenv.load
require 'aws-sdk'
Aws.use_bundled_cert!
require 'httparty'
require 'byebug'
require 'logger'
require 'zip/zip'

class Config
  class BrokenJobException < Exception; end

  def wip_poller
    @w_poller ||= Aws::SQS::QueuePoller.new(wip_address)
  end

  def backlog_poller
    @b_poller ||= Aws::SQS::QueuePoller.new(backlog_address)
  end

  def sqs
    @sqs_client ||= Aws::SQS::Client.new(credentials: creds)
  end

  def backlog_address
    @b_address ||= ENV['BACKLOG_ADDRESS']
  end

  def wip_address
    @w_address ||= ENV['WIP_ADDRESS']
  end

  def finished_address
    @f_address ||= ENV['FINISHED_ADDRESS']
  end

  def needs_attention_address
    @n_address ||= ENV['NEEDS_ATTENTION_ADDRESS']
  end

  def s3
    @s3 ||= Aws::S3::Client.new(
      region: region,
      credentials: creds
    )
  end

   def maker_ec2
    @ec2 ||= Aws::EC2::Client.new(
      region: region,
      credentials: creds)
  end

  def bot_ec2
    @bot_ec2 ||= Aws::EC2::Client.new(
      region: region,
      credentials: bot_creds)
  end

  def creds
    @c ||= Aws::Credentials.new(
      ENV['AWS_ACCESS_KEY_ID'],
      ENV['AWS_SECRET_ACCESS_KEY'])
  end

  def bots_creds
    @b_c ||= Aws::Credentials.new(
      ENV['BOT_MAKER_AWS_ACCESS_KEY_ID'],
      ENV['AWS_SECRET_ACCESS_KEY'])
  end

  def sqs_queue_url
    @sqs_url ||= @ENV['SQS_QUEUE_URL']
  end

  def region
    @region ||= ENV['AWS_REGION']
  end

  def availability_zones
    @az ||= bot_ec2.describe_availability_zones.
                    availability_zones.map(&:zone_name)
  end

  def bot_creds
    @bot_creds ||= Aws::Credentials.new(
      ENV['BOT_MAKER_AWS_ACCESS_KEY_ID'],
      ENV['BOT_MAKER_AWS_SECRET_ACCESS_KEY'])
  end

  def sqs
    @sqs ||= Aws::SQS::Client.new(credentials: bot_creds)
  end

  def jobs_ratio_denominator
    @jobs_denom ||= ENV['JOBS_RATIO_DENOMINATOR'].to_i
  end

  def setup_logger
    @logger_client ||= Logger.new(
      File.open(File.expand_path('../crawlBot.log', __FILE__), 'a+'))
    @logger_client.level = Logger::INFO
    @logger_client
  end

  def logger
  #   logger.info("\njob started: #{stats.last_message_received_at}\n#{JSON.parse(msg.body)}\n#{msg}\n\n")
  #  @logger_client ||= setup_logger
  end
end