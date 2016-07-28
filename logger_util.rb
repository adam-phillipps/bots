class LoggerUtil
	@@logger = Logger.new(STDOUT)
	def self.info(message)
		@@logger.level = Logger::INFO
		@@logger.datetime_format = '%Y-%m-%d %H:%M:%S'
		@@logger.info(message)
	end
	def self.error(message)
		@@logger.level = Logger::ERROR
		@@logger.datetime_format = '%Y-%m-%d %H:%M:%S'
		@@logger.error(message)
	end
end