require "xmlrpc/client"

def xml_rpc_client(host, path, port, credentials=nil)
  if credentials == nil
    config = YAML.load_file('config.yml')
    credentials = config["credentials"]
  end
  if credentials
    XMLRPC::Client.new(host, path, port, nil, nil, credentials[0], credentials[1])
  else
    XMLRPC::Client.new(host, path, port)
  end
end
