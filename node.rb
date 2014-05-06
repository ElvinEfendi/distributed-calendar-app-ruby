class Node
  include Comparable
  attr_reader :address, :port

  def initialize address, port
    @address = address
    @port = port
  end

  def to_s
    "(#{address}, #{port})"
  end

  def ==(other_node)
    address == other_node.address && port == other_node.port
  end

  def <=>(other_node)
    if self.canonical_form < other_node.canonical_form
      -1
    elsif self.canonical_form > other_node.canonical_form
      1
    else
      0
    end
  end

  def eql?(other_node)
    self.==(other_node)
  end

  def hash
    [@address, @port].hash
  end

  protected
  def canonical_form
    "#{address.gsub('.', '')}#{port}".to_i
  end
end
