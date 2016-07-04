require 'dotenv'
Dotenv.load(".bot_maker.env")
require 'aws-sdk'
require 'date'
require 'byebug'
require 'securerandom'
require_relative 'config'

class BotMaker
  include Config
  begin
    def initialize
      poll
    end

     def poll
      loop do
        run_program(adjusted_spawning_ratio)
        sleep 5
      end
    end

    def adjusted_spawning_ratio
      backlog = get_count(backlog_address)
      wip = get_count(bot_counter_address)
      byebug
      (((1.0 / jobs_ratio_denominator) * backlog) - wip).ceil
    end

    def run_program(desired_instance_count)
      puts "count at #{Time.now}: #{desired_instance_count}"
      if desired_instance_count > 0
        chunks = (desired_instance_count.to_f / 100.00).floor
        leftover = (desired_instance_count % 100.00).floor

        chunks.times do |n|
          ec2.run_instances(instance_config(100))
        end
        ec2.run_instances(leftover)
      end
    end

    def bot_image_tag_filter(tag_name)
      bot_image.tags.find { |t| t.key.include?(tag_name) }.value.split(',')
    end

    def bot_image
      @bot_image ||= ec2.describe_images(
        filters: [{ name: 'tag:Name', values: [ENV[AMI_NAME]] }]
      ).images.first
    end

    def bot_image_id
      @bot_image_id ||= bot_image.image_id
    end

    def instance_config(desired_instance_count)
      {
        image_id:                 bot_image_id,
        instance_type:            instance_type,
        min_count:                desired_instance_count,
        max_count:                desired_instance_count,
        key_name:                 'crawlBot',
        # security_groups:          ['crawlBot'],
        # security_group_ids:       ['sg-6950d20f'],
        placement:                { availability_zone: availability_zone },
        disable_api_termination:  'false',
        instance_initiated_shutdown_behavior: 'terminate'
      }
    end

    def creds
      @creds ||= Aws::Credentials.new(
        ENV['AWS_ACCESS_KEY_ID'],
        ENV['AWS_SECRET_ACCESS_KEY'])
    end

    def availability_zone
      @availability_zone ||= ENV['AVAILABILITY_ZONE']
    end

    def jobs_ratio_denominator
      @jobs_denom ||= ENV['RATIO_DENOMINATOR'].to_i
    end

    def instance_type
      @instance_type ||= ENV['INSTANCE_TYPE']
    end
  rescue => e
    puts e
    kill_everything
  end
end

BotMaker.new
