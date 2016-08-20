require 'aws-sdk'
Aws.use_bundled_cert!
require 'httparty'
require 'syslog/logger'
require 'logger'
require 'json'
require 'byebug'

module Administrator
  def self_id
    # 'test-id' # comment the below line for development mode
    @id ||= HTTParty.get('http://169.254.169.254/latest/meta-data/instance-id')
  end

  def poller(board)
    begin
      eval("#{board}_poller")
    rescue NameError => e
      unless board == ''
        logger.error("There isn't a '#{board}' poller available...\n#{e}")
      end
    end
  end

  def backlog_poller
    @backlog_poller ||= Aws::SQS::QueuePoller.new(backlog_address)
  end

  def wip_poller
    @wip_poller ||= Aws::SQS::QueuePoller.new(wip_address)
  end

  def finished_poller
    @finished_poller ||= Aws::SQS::QueuePoller.new(finished_address)
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

  def errors
    $errors ||= { ruby: [], workflow: [] }
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

  def status_address
    @status_address ||= ENV['STATUS_ADDRESS']
  end

  def region
    @region ||= ENV['AWS_REGION']
  end

  def scraper
    Dir["#{File.expand_path(File.dirname(__FILE__))}/**/*.jar"].first
  end

  def jobs_ratio_denominator
    @jobs_ratio_denominator ||= ENV['RATIO_DENOMINATOR'].to_i
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

  def logger
    @logger ||= create_logger
  end

  def create_logger
    logger = Logger.new(STDOUT)
    logger.datetime_format = '%Y-%m-%d %H:%M:%S'
    logger
  end

  def format_finished_body(body)
    body.split(' ')[0..25].join(' ') + '...'
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

  def die!
    notification_of_death

    poller('counter').poll(max_number_of_messages: 1) do |msg|
      poller('counter').delete_message(msg)
      throw :stop_polling
    end

    poller('wip').poll(max_number_of_messages: 1) do |msg|
      poller('wip').delete_message(msg)
      throw :stop_polling
    end

    send_logs_to_s3
    ec2.terminate_instances(ids: [self_id])
  end

  def notification_of_death
    blame = errors.sort_by(&:reverse).last.first
    sqs.send_message(
        queue_url: status_address,
        message_body: { "#{self_id}": 'dying' }.to_json
    )
    sqs.send_message(
      queue_url: needs_attention_address,
      message_body: { "#{self_id}": "shut itself down because #{blame}" }
    )
    logger.info("The cause for the shutdown is #{blame}")
  end

  def update_status_checks(ids, status)
    for_each_id_send_message_to(
      status_address,
      ids,
      status
    )
  end

  def add_each_to_status_check(ids)
    for_each_id_send_message_to(
      status_address,
      ids,
      'starting'
    )
  end

  def add_to_working_bots_count(ids)
    for_each_id_send_message_to(
      bot_counter_address,
      ids,
      Time.now
    )
  end

  def for_each_id_send_message_to(board, ids, message)
    ids.each do |id|
      sqs.send_message(
        queue_url: board,
        message_body: { "#{id}": "#{message}" }.to_json
      )
    end
  end

  def boot_time
    # Time.now.to_i # comment the code below for development mode
    @instance_boot_time ||=
      ec2.describe_instances(instance_ids:[self_id]).
        reservations[0].instances[0].launch_time.to_i
  end

  def send_frequent_status_updates
    while true
      # status = 'Testing' # comment the lines below for development mode
      status = ec2.describe_instances(instance_ids: [self_id]).
        reservations[0].instances[0].state.name.capitalize

      logger.info "Send update to status board" +
        { self_id => status }.to_json

      update_status_checks([self_id], status)
      sleep 5
    end
  end
end
