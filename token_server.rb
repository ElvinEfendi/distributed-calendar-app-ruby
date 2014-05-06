require './xml_rpc_client'

class TokenServer
  # this method periodically calls pass_token method to circulate the token
  def self.run(config)
    re_try = 0
    while true
      begin
        sleep 2
        xml_rpc_client(config["local_host"], config["path"], 
	  	       config["local_port"], config["credentials"]).call("calendar_network.pass_token")
      rescue XMLRPC::FaultException => e
        re_try += 1
        if config["debug"]
          puts e.inspect
          puts e.backtrace.join("\n")
        end
        re_try > 3 and break
      rescue Exception => e
        re_try += 1
        if config["debug"]
          puts e.inspect
          puts e.backtrace.join("\n")
        end
        re_try > 3 and break
      end
    end
  end
end
