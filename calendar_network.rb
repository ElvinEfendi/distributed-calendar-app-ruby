require "yaml"
require './constants'
require "webrick"
require "xmlrpc/server"
require './calendar_network_handler'
require './appointment_handler'
require './xml_rpc_client'
require './appointments_controller'
require './node'
require './ricart_agrawala'
require './token_server'

# here we encapsulate 
# network operations such as 
# joining to network, quitting, 
# synchronization wrapper and change propogation
class CalendarNetwork 
  attr_reader :config, :local_node, :ricart_agrawala
  attr_accessor :remote_nodes, :need_token, :has_token

  # using xml rpc call join method in online_host 
  # and send ip address of this node
  def initialize(config, remote_host, remote_port)
    @config = config
    @remote_nodes = []
    @local_node = Node.new(@config["local_host"], @config["local_port"])
    @need_token = false
    @has_token = false
    @ricart_agrawala = RicartAgrawala.new(self)
    join_network(remote_host, remote_port)
    start_server
  end

  # returns next remote node in
  # logical ring(i.e: 0, 1, 2, 3, 0, 1, 2, 3, ...)
  def get_next_remote_node
    all_nodes = remote_nodes.dup
    all_nodes |= [@local_node]
    all_nodes = all_nodes.sort
    local_node_index = all_nodes.index(@local_node)
    all_nodes[(local_node_index + 1) % all_nodes.size]
  end

  # true means this node in the network only with itself
  def offline_mode
    @config["offline_mode"]
  end
  def offline_mode=(value)
    @config["offline_mode"] = value
    save_config
  end

  def server_is_running
    @config["server_is_running"]
  end
  def server_is_running=(value)
    @config["server_is_running"] = value
    save_config
  end

  def quit!
    puts "Quitting calendar network..."

    begin
      unless offline_mode
        # inform other online remote nodes if exists
	puts "Informing other online nodes:"
        remote_nodes.each do |remote_node|
          remote_server = xml_rpc_client(remote_node.address, @config["path"], remote_node.port)
          if remote_server.call("calendar_network.bye_guys", @config["local_host"], @config["local_port"])
	    puts "(#{remote_node.address}, #{remote_node.port}) was successfully informed."
	  end
        end
      end
    rescue Exception => e
      puts e.message
      puts e.backtrace.join("\n")
    end
    # reset dynamic fields of config
    @config.delete("server_is_running")
    @config.delete("offline_mode")
    save_config

    # shutdown the server and terminate the program
    @httpserver and @httpserver.shutdown
  end

  private
  def save_config
    File.open "config.yml", "w" do |f|
      f.puts @config.to_yaml
    end
  end

  def start_server
    puts "Starting the server..."
    self.server_is_running = true
    # start XML RPC server to listen for requests
    xml_rpc_server = XMLRPC::WEBrickServlet.new
    xml_rpc_server.add_handler("calendar_network", CalendarNetworkHandler.new(self))
    xml_rpc_server.add_handler("appointment",      AppointmentHandler.new)
    xml_rpc_server.set_default_handler do |name, *args|
      raise XMLRPC::FaultException.new(-99, "Method #{name} missing" +
				       " or wrong number of parameters!")
    end

    if credentials = @config["credentials"]
      # setup http basic authneticator
      http_config = { :Realm => 'Calendar Network Authenticator' }
      htpasswd = WEBrick::HTTPAuth::Htpasswd.new 'http_pass'
      htpasswd.set_passwd config[:Realm], credentials[0], credentials[1]
      htpasswd.flush
      http_config[:UserDB] = htpasswd
      basic_auth = WEBrick::HTTPAuth::BasicAuth.new http_config
      authenticator = lambda {|req, res| basic_auth.authenticate(req, res)}
      
      @httpserver = WEBrick::HTTPServer.new(:Port => @config["local_port"], :BindAddress => @config["local_host"], :RequestCallback => authenticator)
    else
      @httpserver = WEBrick::HTTPServer.new(:Port => @config["local_port"], :BindAddress => @config["local_host"])
    end
    @httpserver.mount(@config["path"], xml_rpc_server)
    # catch the termination of program and do necessary tasks
    signals = %w[INT TERM HUP] & Signal.list.keys
    signals.each { |signal| trap(signal) { self.quit! } }

    # start the server
    unless config["debug"]
      STDIN.reopen "/dev/null"
      STDOUT.reopen "./logs", "a" 
      STDERR.reopen "./logs", "a" 
    end
    @httpserver.start
  rescue Exception => e
    self.server_is_running = false
    puts "Error happened while starting the server."
    if config["debug"]
      puts e.message
      puts e.backtrace.join("\n")
    end
  end

  def join_network(remote_host, remote_port)
    puts "Joining to the network..."
    unless remote_host && remote_host.length > 0 && 
           remote_port && remote_port.length > 0
      self.offline_mode = true
      self.has_token = true
      return
    end

    # join this node to the network using given online remote node
    remote_server = xml_rpc_client(remote_host, @config["path"], remote_port)
    if (result = remote_server.call("calendar_network.join", @config["local_host"], @config["local_port"]))
      @remote_nodes = result.map{|h, p| Node.new(h, p.to_i)}
      # also add initial remote node to the list
      # because it is excluded in the list it has
      @remote_nodes << Node.new(remote_host, remote_port.to_i)

      # synchronize this machine with given remote machine
      Appointment.synchronize!(remote_server)
    end
    self.offline_mode = false
  rescue Exception => e
    self.offline_mode = true
    puts "Error happened while joining to the network. The application is running in offline mode."
    if config["debug"]
      puts e.message
      puts e.backtrace.join("\n")
    end
  end
end

# load configuration
config = YAML.load_file('config.yml')

pid = Process.fork do
  # run the server
  CalendarNetwork.new(config, ARGV[0], ARGV[1])
end

sleep 1

Process.fork do
  if config["me_algorithm"] == TOKEN_RING
    TokenServer.run(config)
  elsif config["me_algorithm"] == RICART_AGRAWALA
    RicartAgrawala.run(config)
  end
end

# run client
AppointmentsController.new
