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
        sleep 5 # slow the polling
      end
    end

    def adjusted_spawning_ratio
      backlog = get_count(backlog_address)
      wip = get_count(bot_counter_address)

      (((1.0 / jobs_ratio_denominator) * backlog) - wip).ceil
    end

    def run_program(desired_instance_count)
      puts "start #{desired_instance_count} instances at #{Time.now}"
      divider = 100.00
      if desired_instance_count > 0
        chunks = (desired_instance_count.to_f / divider).floor
        leftover = (desired_instance_count % divider).floor
        begin
          chunks.times do |n|
            puts "start 100 of #{desired_instance_count} instances at #{Time.now}"
            ec2.run_instances(instance_config(divider))
          end
          puts "start #{leftover} of #{desired_instance_count} instances at #{Time.now}"
          ec2.run_instances(instance_config(leftover))
        rescue Aws::EC2::Errors::DryRunOperation => e
          puts e
        end
      end
    end

    def bot_image_tag_filter(tag_name)
      bot_image.tags.find { |t| t.key.include?(tag_name) }.value.split(',')
    end

    def bot_image
      @bot_image ||= ec2.describe_images(
        filters: [{ name: 'tag:aminame', values: [ENV['AMI_NAME']] }]
      ).images.first
    end

    def bot_image_id
      @bot_image_id ||= bot_image.image_id
    end

    def instance_config(desired_instance_count)
      count = desired_instance_count.to_i
      {
        image_id:                 bot_image_id,
        instance_type:            instance_type,
        min_count:                count,
        max_count:                count,
        key_name:                 'crawlBot',
        security_groups:          ['webCrawler'],
        security_group_ids:       ['sg-940edcf2'],
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

    def instance_type
      @instance_type ||= ENV['INSTANCE_TYPE']
    end
  rescue => e
    puts e
    kill_everything
  end
end

BotMaker.new
