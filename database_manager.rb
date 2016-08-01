require "mysql"

class DatabaseManager
	def getProducts
		begin
		    con = Mysql.new 'bidengine.cmvi8uet7bcw.us-west-2.rds.amazonaws.com', 'smash', 'SmashAdmin1', 'product_intelligence'

		    rs = con.query("SELECT * FROM crawler_product_result")
		    
		    rs.each do |row|
		        puts row.join("\s")
		    end
		        
		rescue Mysql::Error => e
		    puts e.errno
		    puts e.error
		    
		ensure
		    con.close if con
		end
	end

end

DatabaseManager.new().getProducts()