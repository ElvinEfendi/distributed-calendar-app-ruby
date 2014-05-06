require 'digest/sha1'
require 'securerandom'
require 'csv'

class Appointment
  DATA_FILE = "appointments.csv"
  attr_accessor :id, :uuid, :header, :start_at, :duration_in_minutes, :comment

  def initialize(header=nil, start_at=nil, duration_in_minutes=nil, comment=nil)
    @header = header
    @start_at = start_at
    @duration_in_minutes = duration_in_minutes
    @comment = comment
  end

  # synchronizes this node with given remote node
  # this is one directional synchronization because
  # during offline mode we do not allow user to modify 
  # the database, and when the node is online 
  # it always propogates modifications
  def self.synchronize!(remote_node)
    delta = remote_node.call("appointment.get_delta", Appointment.all_id_checksum_pairs)

    delta["destroy"].each do |remote_appointment|
      Appointment.destroy(remote_appointment["uuid"])
    end

    delta["update"].each do |remote_appointment|
      local_appointment                     = Appointment.find(remote_appointment["uuid"])
      local_appointment.header              = remote_appointment["header"]
      local_appointment.start_at            = remote_appointment["start_at"]
      local_appointment.duration_in_minutes = remote_appointment["duration_in_minutes"]
      local_appointment.comment             = remote_appointment["comment"]
      local_appointment.save
    end

    delta["create"].each do |remote_appointment|
      local_appointment                     = Appointment.new
      local_appointment.uuid                = remote_appointment["uuid"]
      local_appointment.header              = remote_appointment["header"]
      local_appointment.start_at            = remote_appointment["start_at"]
      local_appointment.duration_in_minutes = remote_appointment["duration_in_minutes"]
      local_appointment.comment             = remote_appointment["comment"]
      local_appointment.save
    end
  rescue Exception => e
    puts e.message
    puts e.backtrace.join("\n")
    exit
  end

  def self.all_id_checksum_pairs
    res = {}
    all.each do |appointment|
      res[appointment.uuid.to_s] = appointment.get_checksum
    end
    res
  end

  def self.get_delta(id_checksum_pairs)
    delta = {:destroy => [], :update => [], :create => []}
    local_id_checksum_pairs = Appointment.all_id_checksum_pairs

    (id_checksum_pairs.keys - local_id_checksum_pairs.keys).each do |uuid|
      appointment = Appointment.new
      appointment.uuid = uuid
      delta[:destroy] << appointment.xml_rpc_compatible
    end
    
    (local_id_checksum_pairs.keys - id_checksum_pairs.keys).each do |appointment_to_create|
      delta[:create] << Appointment.find(appointment_to_create).xml_rpc_compatible
    end

    (local_id_checksum_pairs.keys & id_checksum_pairs.keys).each do |appointment_to_update|
      if local_id_checksum_pairs[appointment_to_update] != id_checksum_pairs["appointment_to_update"]
        delta[:update] << Appointment.find(appointment_to_update).xml_rpc_compatible
      end
    end

    delta
  end

  # returns the checksum of the fields of the appointment
  def get_checksum
    Digest::SHA1.hexdigest("#{header}#{start_at}#{duration_in_minutes}#{comment}")
  end

  def xml_rpc_compatible
    {
      :uuid => uuid, 
      :header => (header || ""), 
      :start_at => (start_at || ""), 
      :duration_in_minutes => (duration_in_minutes || ""), 
      :comment => (comment || "")
    }
  end

  def self.new_from_array(row)
    ret = Appointment.new(row[2], row[3], row[4], row[5])
    ret.id = row[0]
    ret.uuid = row[1]
    ret
  end

  def self.find_by_id(id)
    appointment = nil
    CSV.foreach(DATA_FILE) do |row|
      if row[0] == id
        appointment = Appointment.new_from_array(row)
      end
    end
    appointment
  end
  def self.find(uuid)
    appointment = nil
    CSV.foreach(DATA_FILE) do |row|
      if row[1] == uuid
        appointment = Appointment.new_from_array(row)
      end
    end
    appointment
  end

  def save
    appointments = Appointment.all.select{|appointment| appointment.uuid != uuid}
    self.id ||= Appointment.next_id
    self.uuid ||= SecureRandom.uuid
    appointments << self

    writer = CSV.open(DATA_FILE, 'w')
      appointments.each do |appointment| 
        writer << appointment.to_array
      end
    writer.close
    true
  end

  def destroy
    all = Appointment.all.select{|appointment| appointment.uuid != uuid}
    writer = CSV.open(DATA_FILE, 'w')
    all.each do |appointment|
      writer << appointment.to_array
    end
    writer.close
    true
  end

  def self.destroy(uuid)
    all = Appointment.all.select{|appointment| appointment.uuid != uuid}
    writer = CSV.open(DATA_FILE, 'w')
    all.each do |appointment|
      writer << appointment.to_array
    end
    writer.close
    true
  end

  def self.all
    appointments = []
    CSV.foreach(DATA_FILE) do |row|
      appointments << Appointment.new_from_array(row)
    end
    appointments
  end

  def self.count
    CSV.read(DATA_FILE).length
  end

  # return fields as array 
  # as CSV row order
  def to_array
    [id, uuid, header, start_at, duration_in_minutes, comment]
  end

  # return next unique id in db
  def self.next_id
    (all.collect{|appointment| appointment.id.to_i}.max || 0) + 1
  end
end
