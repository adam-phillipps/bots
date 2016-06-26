require 'dotenv'
Dotenv.load
require 'aws-sdk'
require 'date'
require 'byebug'
require 'securerandom'
require_relative 'config'

class BotMaker < Config
  begin
    def initialize
      byebug
      poll
    end

     def poll
      loop do
        sleep 5
        # run_program(adjusted_birth_ratio) if birth_ratio_acheived?\
        run_program(2) if birth_ratio_acheived? || true
      end
    end

    def birth_ratio_acheived?
      birth_ratio >= jobs_ratio_denominator
    end

    def birth_ratio
      counts = [backlog_address, wip_address].map do |board|
        sqs.get_queue_attributes(
          queue_url: board,
          attribute_names: ['ApproximateNumberOfMessages']
        ).attributes['ApproximateNumberOfMessages'].to_f
      end

      backlog = counts.first
      wip = counts.last
      wip = wip == 0.0 ? 1.0 : wip # guards against irrational values
      backlog / wip
    end

    def adjusted_birth_ratio
      adjusted_ratio = (birth_ratio / jobs_ratio_denominator).floor
      adjusted_ratio == 0 ? 1 : adjusted_ratio
    end

    def run_program(desired_instance_count)
      maker_ec2.run_instances(
        dry_run: true,
        image_id: bot_image_id,
        min_count: desired_instance_count,
        max_count: desired_instance_count
      )
      poll
    end

    def bot_image_tag_filter(tag_name)
      bot_image.tags.find { |t| t.key.include?(tag_name) }.value.split(',')
    end

    def bot_image
      @bot_image ||= bot_ec2.describe_images(
        filters: [{ name: 'tag:Name', values: ['crawlBotProd'] }]
      ).images.first
    end

    def bot_image_id
      bot_image.image_id
    end
  rescue => e
    puts e
    kill_everything
  end
end

BotMaker.new