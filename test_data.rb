require_relative 'config'
require 'dotenv'
Dotenv.load(".bot_maker.env")
require 'json'


class TestData
  include Config
  def add
    20000.times do |n|
      puts n
      sqs.send_message(queue_url: backlog_address, message_body: {"productId":2645,"title":"Z by Malouf Z Wedge Pillow with Cover"}.to_json)
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
end

# TestData.new.add
# TestData.new.delete('wip')
