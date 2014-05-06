require 'yaml'
require './appointment'
require './xml_rpc_client'

class AppointmentsController
  def initialize
    @local_host = config["local_host"]
    @path = config["path"]
    @local_port = config["local_port"]
    @local_server = lambda { xml_rpc_client(@local_host, @path, @local_port) }
    
    puts "\nAvailable commands"
    offline_commands = %w(list read exit close_client help)
    online_commands = %w(create update destroy)
    print "Basic commands: #{offline_commands.join(', ')}. "
    puts "Only online mode commands: #{online_commands.join(', ')}"

    # wait for the user command to execute
    while true
      print "Enter the command you'd like to be executed: "
      command = $stdin.gets.chop

      offline_mode = (!config["server_is_running"] or config["offline_mode"])
      if offline_mode && !offline_commands.include?(command)
        puts "Entered command \"#{command}\" is not allowed. Please, ask only among (#{offline_commands.join(', ')})."
        puts ""
        next
      elsif !offline_mode && !(online_commands + offline_commands).include?(command)
        puts "Entered command \"#{command}\" is not allowed. Please, ask only among (#{(online_commands + offline_commands).join(', ')})."
        puts ""
        next
      end

      (command == "exit" && !config["server_is_running"]) and  break

      # run the asked command
      self.send(command)
      puts ""
    end
  end
  
  def help
    puts "list         - list all available appointments"
    puts "read         - view specific appointment"
    puts "exit         - in offline mode just close client, in online mode also shut the server down"
    puts "close_client - close the client without touching to running server"
    puts "create       - create new appointment"
    puts "update       - update specific appointment"
    puts "destroy      - destroy specific appointment"
  end

  def close_client
    puts "The server will still be online in the network." if config["server_is_running"]
    Kernel.exit
  end

  # inform local server that you want to exit
  def exit
    puts "The server is shutding down...(You can still use client)" if config["server_is_running"]
    @local_server.call.call("calendar_network.quit_self")
  end
  
  def create
    consistently "create", -1 do
      puts "Please, fill following fields to create a new appointment:"

      appointment = Appointment.new
	  
      fill_fields_of(appointment)

      if appointment.save
        puts "New appointment was successfully created."
        pretty_print_titles
        pretty_print(appointment)

        # propogate this changes to all other online nodes
        propogate_change(:create, appointment.xml_rpc_compatible)
      else
        puts "Error happened while saving the appointment."
      end
    end
  end
  
  def update
    puts "Please, fill following fields to update an appointment(leave blank to keep unchanged):"

    print "    Identifier of the appointment: "
    id = $stdin.gets.chop.strip
    appointment = Appointment.find_by_id(id)
    if appointment != nil
      consistently "update", appointment.uuid do
        # load appointment again 
        # because it might get updated by other node
        # while waiting for grant
        appointment = Appointment.find_by_id(id)
        if appointment != nil
          pretty_print_titles
          pretty_print(appointment)

          fill_fields_of(appointment)

          if appointment.save
            puts "The appointment was successfully updated."
            pretty_print_titles
            pretty_print(appointment)

            # propogate this changes to all other online nodes
            propogate_change(:update, appointment.xml_rpc_compatible)
          else
            puts "Error happened while saving the appointment."
          end
        else
          puts "Appointment with id = #{id} could not be found."
        end
      end
    else
      puts "Appointment with id = #{id} could not be found."
    end
  end

  def destroy
    print "Please, enter the identifier of appointment you want to destroy: "
    id = $stdin.gets.chop.strip
    appointment = Appointment.find_by_id(id)
    if appointment != nil
      consistently "destroy", appointment.uuid do
        # load appointment again 
        # because it might get updated by other node
        # while waiting for grant
        appointment = Appointment.find_by_id(id)
        if appointment != nil
          if appointment.destroy
            puts "The appointment was successfully destroyed."
      
            # propogate this changes to all other online nodes
            propogate_change(:destroy, appointment.xml_rpc_compatible)
          else
            puts "Error happened while destroying the appointment."
          end
        else
          puts "Appointment with id = #{id} could not be found."
        end
      end
    else
      puts "Appointment with id = #{id} could not be found."
    end
  end

  def list
    appointments = Appointment.all
    if appointments.empty?
      puts "No appointment found."
    else
      pretty_print_titles  
      appointments.each do |appointment|
        pretty_print(appointment)
      end
    end
  end

  def read
    if Appointment.count == 0
      puts "Currently there are no appointments."
      return
    end

    print "Please, enter the identifier of appointment you want to view in detail: "
    id = $stdin.gets.chop.strip
    appointment = Appointment.find_by_id(id)

    puts "    Header:   #{appointment.header}"
    puts "    Start at: #{appointment.start_at}"
    puts "    Duration: #{appointment.duration_in_minutes} minutes"
    puts "    Comment:  #{appointment.comment}"
  rescue Exception => e
    puts e.message
  end

  private
  def consistently action, appointment_id
    appointment_id = appointment_id.to_s
    # inform local network handler 
    # that we need token i.e try to lock db
    timestamp = @local_server.call.call("calendar_network.lock_db_for", action, appointment_id)
    locked = false
    time = Time.now
    timeout = 30 # seconds
    while !locked && Time.now - timeout < time
      sleep 1
      locked = @local_server.call.call("calendar_network.lock_status_for", action, appointment_id, timestamp)
    end

    if !locked
      puts "The resource is used by another process. Please try later."
      # revert back lock_db_for request
      @local_server.call.call("calendar_network.unlock_db_for", action, appointment_id, timestamp)
      return
    end

    # db locked now, run action
    puts "==> db is locked. doing modifications..."
    yield
    puts "==> unlocking db..."
    # unlock db i.e release token
    @local_server.call.call("calendar_network.unlock_db_for", action, appointment_id, timestamp)
  end

  # in each call to this method we reload
  # config, because there might be changes by server
  def config
    YAML.load_file('config.yml')
  end

  # run the action in all other online nodes
  # in new thread. this is another direction of
  # synchronization
  def propogate_change(action, params)
    @local_server.call.call("calendar_network.propogate_change", action, params)
  end

  def pretty_print_titles
    printf("%-5s %-30s %-25s %-18s %s\n", "ID", "Header", "Start at", "Duration", "Comment")
  end

  def pretty_print(appointment)
    comment = appointment.comment
    if comment.respond_to?("[]")
      comment = appointment.comment[0, 20]
    end

    printf("%-5s %-30s %-25s %-18s %s\n", 
	   appointment.id, 
	   appointment.header, 
	   appointment.start_at, 
	   "#{appointment.duration_in_minutes}", 
	   comment)
  end

  # asks user to enter value for given
  # appointment's fields
  def fill_fields_of(appointment)
    {header: "Header", start_at: "Start at", 
	    duration_in_minutes: "Duration", comment: "Comment"}.each do |field, title|
      print "    #{title}: "
      if (value=$stdin.gets.chop.strip) && value.length > 0
        appointment.send("#{field}=", value)
      end
    end
  end
end

if __FILE__==$0
  AppointmentsController.new
end
