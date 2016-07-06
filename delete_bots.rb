require 'dotenv'
Dotenv.load('.bot_maker.env')
require_relative 'config'
require 'byebug'

class DeleteBots
  include Config

  def initialize
    byebug
    instance_ids = ec2.describe_instances(
      filters: [
        {
          name: 'tag:Name',
          values: ['crawlBot']
        }
      ]
    ).map { |instance| instance.instance_id.to_s }

    ec2.terminate_instances(instance_ids: instance_ids)
  end

  def creds
    @creds ||= Aws::Credentials.new(
      ENV['AWS_ACCESS_KEY_ID'],
      ENV['AWS_SECRET_ACCESS_KEY']
    )
  end
end

DeleteBots.new
