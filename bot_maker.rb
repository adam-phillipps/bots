require 'dotenv'
Dotenv.load
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
        puts "polling: #{Time.now}..."
        puts "current ratio: #{current_ratio}"
        puts "adjusted: #{adjusted_spawning_ratio}"
        puts "b count: #{get_count(backlog_address)}"
        puts "w count: #{get_count(wip_address)}"
        run_program(adjusted_spawning_ratio)
        sleep 5
      end
    end

    def current_ratio
      backlog = get_count(backlog_address)
      wip = get_count(wip_address)

      wip == 0.0 ? (backlog / 1) : (backlog / wip) # guards against irrational values
    end

    def should_spawn?
      get_count(backlog_address) > 0 && get_count(wip_address) == 0
    end

    def adjusted_spawning_ratio
      (current_ratio / jobs_ratio_denominator).floor
    end

    def run_program(desired_instance_count)
      puts "count: #{desired_instance_count}"
      if desired_instance_count > 0
        ec2.run_instances(instance_config(desired_instance_count))
      end
    end

    def bot_image_tag_filter(tag_name)
      bot_image.tags.find { |t| t.key.include?(tag_name) }.value.split(',')
    end

    def bot_image
      @bot_image ||= ec2.describe_images(
        filters: [{ name: 'tag:Name', values: ['crawlBotProd'] }]
      ).images.first
    end

    def bot_image_id
      @bot_image_id ||= bot_image.image_id
    end

    def instance_config(desired_instance_count)
      {
        dry_run:                  true,
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
        ENV['MAKER_AWS_ACCESS_KEY_ID'],
        ENV['MAKER_AWS_SECRET_ACCESS_KEY'])
    end

    def ec2
      @ec2 ||= Aws::EC2::Client.new(
        region: region,
        credentials: creds)
    end

    def availability_zone
      @availability_zone ||= ENV['AVAILABILITY_ZONE']
    end

    def jobs_ratio_denominator
      @jobs_denom ||= ENV['JOBS_RATIO_DENOMINATOR'].to_i
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