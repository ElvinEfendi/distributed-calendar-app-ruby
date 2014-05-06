# this class is for handling remote requests
# the public method in this
# class will be available for remote nodes

require './appointment'
class AppointmentHandler
  # accepts appointment fields in array
  def create(xml_rpc_appointment)
    appointment = Appointment.new
    appointment.uuid                = xml_rpc_appointment["uuid"]
    appointment.header              = xml_rpc_appointment["header"]
    appointment.start_at            = xml_rpc_appointment["start_at"]
    appointment.duration_in_minutes = xml_rpc_appointment["duration_in_minutes"]
    appointment.comment             = xml_rpc_appointment["comment"]

    appointment.save
  end

  # accepts appointment fields in array
  def update(xml_rpc_appointment)
    appointment                     = Appointment.find(xml_rpc_appointment["uuid"])
    appointment.header              = xml_rpc_appointment["header"]
    appointment.start_at            = xml_rpc_appointment["start_at"]
    appointment.duration_in_minutes = xml_rpc_appointment["duration_in_minutes"]
    appointment.comment             = xml_rpc_appointment["comment"]

    appointment.save
  end

  # UUID of appointment
  def destroy(xml_rpc_appointment)
    appointment = Appointment.find(xml_rpc_appointment["uuid"])
    appointment.destroy
  end

  # accept array of array i.e: [[uuid, checksum], [uuid, checksum]]
  # return i.e [[create, id, header, start_at, duration_in_minutes, comment], [<same pattern>]]
  def get_delta(id_checksum_pairs)
    Appointment.get_delta(id_checksum_pairs)
  end
end
