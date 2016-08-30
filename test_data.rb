require 'dotenv'
Dotenv.load('.neuron.env')
require_relative './lib/cloud_powers/synapse/queue'
require_relative './lib/cloud_powers/synapse/pipe'
require_relative './lib/cloud_powers/helper'
require_relative './lib/cloud_powers/auth'
require_relative './lib/cloud_powers/aws_resources'
require_relative './lib/cloud_powers/self_awareness'

require 'byebug'
require 'json'


class TestData
  include Smash::CloudPowers::Auth
  include Smash::CloudPowers::AwsResources
  include Smash::CloudPowers::Helper
  include Smash::CloudPowers::SelfAwareness
  include Smash::CloudPowers::Synapse


  def add(number, board = ENV['BACKLOG_QUEUE_ADDRESS'])
    number.times do |n|
      message = {
        instanceId:       'testing',
        type:             'status_update',
        content:          'testingInfo',
        extraInfo:        { message: 'testing message' }.to_json
      }.to_json

      sqs.send_message(
        queue_url: board,
        message_body: message
      )
      puts n
    end
  end

  def delete(board_name)
    poller(board_name).poll do |msg|
      puts "deleting #{msg}"
      poller(board_name).delete_message(msg)
    end
  end

  def creds
  @creds ||= Aws::Credentials.new(
    ENV['AWS_ACCESS_KEY_ID'],
    ENV['AWS_SECRET_ACCESS_KEY'])
  end

  def terminate_instances
    instance_ids = ec2.describe_instances(
      filters: [
        {
          name: 'key-name',
          values: ['crawlBot']
        }
      ]).reservations.map(&:instances).map { |i| i.map(&:instance_id) }.flatten
    byebug
    # ec2.terminate_instances(instance_ids: instance_ids)
  end

  def creds
    @creds ||= Aws::Credentials.new(
      ENV['AWS_ACCESS_KEY_ID'],
      ENV['AWS_SECRET_ACCESS_KEY']
    )
  end
end


TestData.new.add(10)
# TestData.new.delete('wip')
# TestData.new.terminate_instances
