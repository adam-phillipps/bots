require_relative 'config'
require 'dotenv'
Dotenv.load(".bot_maker.env")


class TestData
  include Config

  def initialize
    356.times do |n|
      sqs.send_message(queue_url: backlog_address, message_body: Time.now.to_i.to_s)
    end
  end

  def creds
  @creds ||= Aws::Credentials.new(
    ENV['AWS_ACCESS_KEY_ID'],
    ENV['AWS_SECRET_ACCESS_KEY'])
  end
end

TestData.new