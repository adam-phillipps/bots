require 'dotenv'
Dotenv.load('.bot_maker.env')
require_relative 'config'
require 'byebug'
require 'json'


class TestData
  include Config

  def add(number)
    number.times do |n|
      puts n
      sqs.send_message(
        queue_url: backlog_address,
        message_body: {
          "productId":2645,
          "title":"Z by Malouf Z Wedge Pillow with Cover"
        }.to_json
      )
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


TestData.new.add(50)
# TestData.new.delete('backlog')
# TestData.new.terminate_instances
