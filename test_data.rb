require_relative './config'

class TestData
  include Config

  def initialize
    sqs = sqs(creds)
    50.times do |n|
      sqs.send_message(queue_url: backlog_address, message_body: Time.now.to_i.to_s)
    end
  end

  def creds
  @creds ||= Aws::Credentials.new(
    ENV['MAKER_AWS_ACCESS_KEY_ID'],
    ENV['MAKER_AWS_SECRET_ACCESS_KEY'])
  end
end

TestData.new