# this class is for handling remote requests
# the public method in this
# class will be available for remote nodes
require './constants'
require './node'
require './ricart_agrawala_request'
class CalendarNetworkHandler
  def initialize(calendar_network)
    @calendar_network = calendar_network
  end

  # receives okay from a node for given action
  def confirm_request action, appointment_id, timestamp
    local_request = RicartAgrawalaRequest.new(@calendar_network.local_node, 
					      action, appointment_id, 
					      timestamp)
    puts "Request " + local_request.to_s + " is confirmed by a remote node"
    @calendar_network.ricart_agrawala.requests_confirmation_count[local_request] += 1
    true
  end

  # this method will periodically
  # be called by ricart_agrawala processing server locally
  def process_pending_requests
    puts "Processing pending requests..."
    pending_requests = @calendar_network.ricart_agrawala.pending_requests.dup
    pending_requests.each do |pending_request|
      puts "Processing pending request: " + pending_request.to_s
      # get earliest local request that has same action on same appointment with
      # with pending request
      earliest_similar_local_request = @calendar_network.ricart_agrawala.earliest_similar_local_request_for(pending_request)
      puts "Earliest similar local request is: #{earliest_similar_local_request.inspect}"
      if earliest_similar_local_request == nil ||
	      pending_request < earliest_similar_local_request
	# if no local request exists or pending request initiated before local request
	# confirm pending request
        remote_server = xml_rpc_client(pending_request.node.address, @calendar_network.config["path"], 
				       pending_request.node.port)
	remote_server.call("calendar_network.confirm_request", pending_request.action, 
			   pending_request.appointment_id, pending_request.timestamp)
	# remove pending request from the list
	puts "Removing the pending_request from the list..."
	@calendar_network.ricart_agrawala.pending_requests.delete(pending_request)
      end
    end
    true
  end

  # when a node wants to do something
  # it ask other remote node's confirmation by calling this method
  def need_permission_for address, port, action, appointment_id, timestamp
    ricart_agrawala_request = RicartAgrawalaRequest.new(Node.new(address, port), 
							action, appointment_id, timestamp)
    puts "Received permission request: " + ricart_agrawala_request.to_s
    # add for processing
    @calendar_network.ricart_agrawala.pending_requests << ricart_agrawala_request

    # syncronize lampart clock value
    @calendar_network.ricart_agrawala.sync_lampart_clock_with(timestamp)
    true
  end

  # called by local client only
  def unlock_db_for action, appointment_id, timestamp
    if @calendar_network.config["me_algorithm"] == TOKEN_RING
      @calendar_network.need_token = false
      # the rest will be done by token server
    elsif @calendar_network.config["me_algorithm"] == RICART_AGRAWALA
      local_request = RicartAgrawalaRequest.new(@calendar_network.local_node, 
						action, appointment_id, 
						timestamp)
      puts "Removing #{local_request} from requests_confirmation_count"
      @calendar_network.ricart_agrawala.requests_confirmation_count.delete local_request
      puts "Removing #{local_request} from local_requests"
      @calendar_network.ricart_agrawala.local_requests.delete local_request
    end	    
    true
  end

  # called by local client only
  def lock_status_for action, appointment_id, timestamp
    if @calendar_network.config["me_algorithm"] == TOKEN_RING
      @calendar_network.has_token
    elsif @calendar_network.config["me_algorithm"] == RICART_AGRAWALA
      local_request = RicartAgrawalaRequest.new(@calendar_network.local_node, 
						action, appointment_id, 
						timestamp)
      @calendar_network.ricart_agrawala.is_locked_for?(local_request)
    else
      puts "Unknown mutual exculusion algorithm!"
      false
    end
  end

  # called by local client only
  def lock_db_for action, appointment_id
    # because of this method is called before each action
    # we also increase current lampart clock
    timestamp = @calendar_network.ricart_agrawala.increment_and_get_lampart_clock
    puts "Locking db for action: #{action} and appointment_id: #{appointment_id}. Timestamp: #{timestamp}"
    if @calendar_network.config["me_algorithm"] == TOKEN_RING
      @calendar_network.need_token = true
      # the rest will be done by token server
    elsif @calendar_network.config["me_algorithm"] == RICART_AGRAWALA
      # inform all other online remote nodes, that
      # this node needs their permission for given action
      @calendar_network.remote_nodes.each do |remote_node|
        remote_server = xml_rpc_client(remote_node.address, @calendar_network.config["path"], remote_node.port)
	remote_server.call("calendar_network.need_permission_for", @calendar_network.local_node.address, 
			   @calendar_network.local_node.port, action, appointment_id, timestamp)
      end
      # set local action request
      @calendar_network.ricart_agrawala.local_requests << RicartAgrawalaRequest.new(@calendar_network.local_node, 
							 			    action, appointment_id, timestamp)
    end
    timestamp
  end

  def take_token
    puts "receiving token"
    @calendar_network.has_token = true
    true
  end

  # called by local client
  def pass_token
    next_remote_node = @calendar_network.get_next_remote_node
    puts "Passing token to #{next_remote_node}"
    if !@calendar_network.has_token || next_remote_node == @calendar_network.local_node || @calendar_network.need_token
      return true
    end
    puts "Passing token to: " + next_remote_node.to_s
    remote_server = xml_rpc_client(next_remote_node.address, @calendar_network.config["path"], next_remote_node.port)
    remote_server.call("calendar_network.take_token")

    @calendar_network.has_token = false
    true
  end

  # called by local client
  def propogate_change(action, params)
    return unless @calendar_network.remote_nodes
    @calendar_network.remote_nodes.each do |remote_node|
      print "Excuting the change(s) in (#{remote_node.address}, #{remote_node.port})... "
      remote_server = xml_rpc_client(remote_node.address, @calendar_network.config["path"], remote_node.port)
      if remote_server.call("appointment.#{action}", params)
        puts " done!"
      else
        puts " could not be done!"
      end
    end
    true
  end
 
  # this method quit the node itself from
  # the network
  def quit_self
    @calendar_network.quit!
  end

  def bye_guys(remote_host, remote_port)
    @calendar_network.remote_nodes.delete(Node.new(remote_host, remote_port))
    if @calendar_network.remote_nodes.size == 0
      @calendar_network.offline_mode = true
    end
    true
  end

  # this method will be called with 
  # xml rpc from another nodes to join
  # the network. It will also join this new host(requester)
  # to other online hosts.
  # return list of other online remote (host, port) pairs if !only_join and no error
  # if error return false
  # else return true
  def join(host, port, only_join=false)
    puts "Join request is received from (#{host}, #{port})"
    tmp_remote_nodes = @calendar_network.remote_nodes.dup
    
    # add given node to the list
    @calendar_network.remote_nodes |= [Node.new(host, port)]

    # change the calendar_network to online mode if it is not
    @calendar_network.offline_mode = false

    if only_join
      # this means requester does not need list of (host, port)
      # it just asks remote node to add given (host, port) pair to their list
      puts "Joining is done. " + @calendar_network.remote_nodes.inspect
      return true
    else
      puts "Informing other remote nodes..."
      # inform other online nodes
      tmp_remote_nodes.each do |remote_node|
	puts "Informing #{remote_node.to_s}"
        remote_server = xml_rpc_client(remote_node.address, @calendar_network.config["path"], remote_node.port)
        remote_server.call("calendar_network.join", host, port, true)
      end

      puts "Joining is done. " + @calendar_network.remote_nodes.inspect
      return tmp_remote_nodes.collect{|node| [node.address, node.port]}
    end
  rescue Exception => e
    puts e.message
    return false
  end

end
