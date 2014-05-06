class RicartAgrawalaRequest
  include Comparable
  attr_reader :node, :action, :appointment_id, :timestamp
  def initialize(node, action, appointment_id, timestamp)
    @node = node
    @action = action
    @appointment_id = appointment_id
    @timestamp = timestamp.to_i
  end

  def to_s
    "(#{@action}, #{@appointment_id}, #{@node.to_s}, #{@timestamp})"
  end

  def ==(other)
    if other == nil
      false
    else
      @action == other.action && 
	      @appointment_id == other.appointment_id &&
	      @node == other.node &&
	      @timestamp == other.timestamp
    end
  end

  def <=>(other)
    if self.timestamp < other.timestamp
      -1
    elsif self.timestamp > other.timestamp
      1
    elsif self.timestamp == other.timestamp && self.node != nil && self.node < other.node
      -1
    elsif self.timestamp == other.timestamp && self.node != nil && self.node > other.node
      1
    else
      0
    end
  end

  # this returns true if this and other request
  # when running at the same time might result in inconsistency
  # for 'create' action we do not care about appointment_id
  def is_similar_to? other_request
    ud_arr = ["update", "destroy"]
    if @action == "create" && other_request.action == "create"
      true
    elsif ud_arr.include?(@action) || ud_arr.include?(other_request.action)
      @appointment_id == other_request.appointment_id
    else
      raise Exception.new("This method works only for 'create', 'update' and 'destroy' methods.")
    end
  end

  def eql?(other)
    self.==(other)
  end

  def hash
    [@node, @action, @appointment_id, @timestamp].hash
  end

end
