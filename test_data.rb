require_relative 'config'
require 'dotenv'
Dotenv.load(".bot_maker.env")
require 'json'


class TestData
  include Config

  def initialize
    356.times do |n|
      sqs.send_message(queue_url: backlog_address, message_body: {"productId":2645,"title":"Z by Malouf Z Wedge Pillow with Cover"}.to_json)
    end
  end

  def creds
  @creds ||= Aws::Credentials.new(
    ENV['AWS_ACCESS_KEY_ID'],
    ENV['AWS_SECRET_ACCESS_KEY'])
  end
end

TestData.new
