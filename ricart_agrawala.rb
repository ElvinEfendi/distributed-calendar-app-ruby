class RicartAgrawala
  attr_accessor :requests_confirmation_count, :local_requests, :pending_requests
  def initialize(calendar_network)
    @calendar_network = calendar_network

    # the count indicating how many times
    # a particular local request is confirmed by remote nodes
    # one request is supposed to be confirme only once
    @requests_confirmation_count = Hash.new(0)

    # these are requests initiated by
    # local client(s)
    @local_requests = []

    # these are requests to be confirmed
    # so they are from remote nodes
    @pending_requests = []

    @lampart_clock = 0
  end

  def sync_lampart_clock_with remote_lampart_clock
    @lampart_clock = [@lampart_clock, remote_lampart_clock].max
  end

  def earliest_similar_local_request_for pending_request
    puts "Finding earliest_similar_local_request_for #{pending_request}"
    @local_requests.select{|local_request| local_request.is_similar_to?(pending_request)}.sort.first
  end

  def increment_and_get_lampart_clock
    @lampart_clock += 1
    @lampart_clock
  end

  # NOTE confirmation count might be bigger in case
  # a node confirms and then quit
  def is_locked_for? local_request
    @requests_confirmation_count[local_request] >= @calendar_network.remote_nodes.size
  end

  # this method periodically call process_pending_requests method
  # to answer the requests
  def self.run(config)
    while true
      begin
        sleep 1
        xml_rpc_client(config["local_host"], config["path"], 
	  	       config["local_port"], config["credentials"]).call("calendar_network.process_pending_requests")
      rescue XMLRPC::FaultException => e
        if config["debug"]
          puts e.inspect
          puts e.backtrace.join("\n")
        end
        break
      rescue Exception => e
        if config["debug"]
          puts e.inspect
          puts e.backtrace.join("\n")
        end
        break
      end
    end
  end

end
