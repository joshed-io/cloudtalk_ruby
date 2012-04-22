require 'net/http'
require 'cgi'

class CloudtalkClient
  attr_accessor :session_token
  attr_accessor :last_response

  CLOUDTALK_ACTIONS = {
          :login               => {:post => "user/login"},
          :partner_create_user => {:post => "user/create"},
          :update_user_profile => {:post   => "profile/setUserProfile",
                                   :prefix => "base"},
          :update_user_image   => {:post                => "profile/uploadImage",
                                   :prefix              => "base",
                                   :appendTicketAsParam => true},
          :user_profile        => {:post   => "profile/getUserProfile",
                                   :prefix => "base"},
          :get_my_inbox        => {:post   => "conversation/getMyInbox",
                                   :prefix => "base"},
          :get_messages        => {:post   => "conversation/getMessages",
                                   :prefix => "base"},
          :create_message      => {:post   => "message/create",
                                   :prefix => "base"},
          :get_relations       => {:post   => "relation/getRelations",
                                   :prefix => "base"},
          :set_relation        => {:post           => "relation/setRelations",
                                   :prefix         => "base",
                                   :requires_array => true},
          :hide_private_conversation => {:post => "conversation/hidePrivateConversation",
                                         :prefix => "base",
                                         :appendTicketAsParam => true}
  }

  def partner_create_user(username, password, email_address, display_name, profile_image_url)
    created_user = run(:partner_create_user,
                       :userName        => username,
                       :emailAddress    => email_address,
                       :displayName     => display_name,
                       :profileImageURL => profile_image_url,
                       :password        => password,
                       :siteUrl         => "",
                       :birthDay        => "01",
                       :birthMonth      => "01",
                       :birthYear       => "19-0")
    set_user(created_user[:userTicket])
    created_user
  end

  def update_user_profile(data={})
    run(:update_user_profile,
        data)
  end

  def su_login(asUser=nil)
    login(@group_admin_username, @group_admin_password, asUser)
  end

  #login a user by username, using the tenancy's su capability
  #params : username, password
  # username - the fully qualified Cloudtalk username of the user to login
  #return : a boolean indicating the status of the login
  def login(username=nil, password=nil, asUser=nil)
    params = {:userName => username, :password => password}
    if asUser && (as_username = asUser[:login])
      asUser[:login] = as_username
    end
    params.merge!(:asUser => asUser) if asUser
    set_user(run(:login, params)[:userTicket])
  end

  def user_profile(username=nil)
    run(:user_profile,
        {:username => username}.reject { |k, v| !v || v.empty? })
  end

  def get_my_inbox
    run(:get_my_inbox)
  end

  def get_messages(data)
    run(:get_messages, data.merge(
            :messageCount    => 20,
            :searchDirection => "backward",
            :startingDate    => "now"))
  end

  def create_message(data)
    parts = []
    if conversation_id = data[:conversationID]
      parts << {:name => "conversationID", :value => conversation_id}
    else
      parts << {:name => "subject", :value => data[:messageText]}
      parts << {:name => "participants", :value => data[:participants].to_json}
    end

    parts << {:name => "Filename", :value => "file"}
    parts << {:name => "messageType", :value => "text"}
    parts << {:name => "messageText", :value => data[:messageText]}
    parts << {:name => "messagePrivacy", :value => "private"}
    parts << "Content-Disposition: form-data; name=\"image.0.file\"; filename=\"file\"\r\nContent-Type: application/octet-stream\r\n\r\n"
    parts << {:name => "Upload", :value => "Submit Query"}
    multipart_post(:create_message, parts)
  end

  def update_user_image(filename, binary_data)
    parts = []
    parts << {:name => "Filename", :value => filename}
    parts << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\nContent-Type: application/octet-stream\r\n\r\n#{binary_data}"
    parts << {:name => "Upload", :value => "Submit Query"}
    multipart_post(:update_user_image, parts)
  end

  def get_relations
    run(:get_relations,
        :relationshipType => ["friend", "follow"])
  end

  def set_relation(user_id)
    run(:set_relation,
        [:relationshipType   => "follow",
         :relationshipSource => "pana.ma",
         :setType            => "add",
         :userID             => user_id])
  end

  def hide_private_conversation(conversation_id)
    run(:hide_private_conversation,
        :conversationID => conversation_id)
  end

  def user_set?
    !!@session_token
  end

  def clear_user
    @session_token = nil
  end

  private

  def set_user(user_ticket)
    @session_token = user_ticket
  end

  def run(action, data={}, headers={})
    action_info = CloudtalkClient.action_info_for(action)
    prep_data!(data, action)
    path     = get_path(action)
    response = (action_info[:method] == "GET") ? get(path, data, headers) : post(path, data, headers)
    process_response(response)
  end

  def get_path(action)
    action_info = CloudtalkClient.action_info_for(action)
    api_prefix  = (action_info[:prefix] == "base") ? @api_prefix : @partner_api_prefix
    "#{api_prefix}#{action_info[:path]}"
  end

  def prep_data!(data, action)
    requires_array?(action) ? data.first.merge!(:anchors => [@partner_anchor]) : data.merge!(:anchors => [@partner_anchor])
    data.merge!(:userTicket => session[:cloudtalk_token]) if attach_ticket_as_param?(action) 
  end

  def requires_array?(action)
    CLOUDTALK_ACTIONS[action][:requires_array]
  end

  def attach_ticket_as_param?(action)
    CLOUDTALK_ACTIONS[action][:attachTicketAsParam]
  end

  def get(path, data)
    response = nil
    new_http_client.start do |http|
      path = "#{path}#{CloudtalkClient.convert_hash_to_uri(data)}"
      log "Performing GET to #{path}"
      response = http.request(Net::HTTP::Get.new(path))
    end
    response
  end

  def post(path, data, headers={})
    log "Performing POST to #{path}"
    log "Data: #{data.to_json}"

    response = nil
    new_http_client.request_post(path, data.to_json, post_headers.merge(headers)) do |http_response|
      case http_response
        when Net::HTTPSuccess
          response = {:code => 200, :body => http_response.body}
        else
          if http_response.content_type == "application/json"
            raise JSON.parse(http_response.body)['error']
          else
            raise "Unhappy clouds: #{http_response.body}"
          end
      end
    end
    response
  end

  def multipart_post(action, parts)
    raise "Session token required" unless @session_token
    path                   = get_path(action)
    request                = Net::HTTP::Post.new(path, "userTicket" => @session_token)

    boundary               = rand(36**16).to_s(36)
    post_stream            = marshal_post_stream(parts, boundary)
    request.content_length = post_stream.size
    request.content_type   = 'multipart/form-data; boundary=' + boundary
    request.body           = post_stream

    response               = nil
    new_http_client.start { |http|
      http_response = http.request(request)
      case http_response
        when Net::HTTPSuccess, Net::HTTPRedirection
          response = {:code => 200, :body => http_response.body}
        else
          http_response.error!
      end
    }
    process_response(response)
  end

  def marshal_post_stream(parts, boundary)
    post_stream = ""
    parts.each do |part|
      post_stream << "--#{boundary}\r\n"
      if part.is_a?(String)
        post_stream << part
      else
        post_stream << "Content-Disposition: form-data; name=\"#{part[:name]}\""
        post_stream << "\r\n\r\n"
        post_stream << part[:value]
      end
      post_stream << "\r\n"
    end
    post_stream << "--" + boundary + "--\r\n"
    post_stream
  end

  def post_headers
    headers = {"Content-Type" => "application/json"}
    headers.merge!({"userTicket" => @session_token}) if @session_token
    headers.merge!({"cloudtalk-protocol" => "4.0"})
    headers
  end

  def process_response(response)
    raise "Error #{response[:code]} | #{response[:body]}" unless response[:code] == 200
    if response[:body]
      json_body = JSON.parse(response[:body]) rescue {}
      @last_response = symbolize_keys(json_body)
    else
      @last_response = {}
    end
    @last_response
  end

  def CloudtalkClient.convert_hash_to_uri(target_hash)
    url = "?"
    target_hash.each_pair { |key, value|
      url << "&" unless url == "?"
      url << "#{key}=#{CGI.escape(value.to_s)}" if !value.nil?
    }
    url
  end

  def new_http_client
    if @proxy_host
      Net::HTTP::Proxy(@proxy_host, @proxy_port).new(@host, @port)
    else
      Net::HTTP.new(@host, @port)
    end
  end

  def log(s)
    puts s if ENV['debug']
  end

  def self.action_info_for(action)
    mapped_action = CLOUDTALK_ACTIONS[action]
    raise "Valid action not found in action map" unless mapped_action
    {:method => "POST",
     :path   => mapped_action[:post],
     :prefix => mapped_action[:prefix]}
  end

  #if you're already established a cloudtalk session, pass in the token
  def initialize(session_token=nil, config_path=nil)
    @config = File.read(File.expand_path(File.dirname(__FILE__) + '/../cloudtalk.yml')).symbolize_keys![:cloudtalk]
    @api_prefix           = @config[:api_prefix] || "/v2/resources/"
    @partner_api_prefix   = @config[:partner_api_prefix] || "/v2/resources/partners/"
    @partner_anchor       = @config[:anchor]
    @group_admin_username = @config[:group_admin_username]
    @group_admin_password = @config[:group_admin_password]

    @host                 = @config[:host]
    @port                 = @config[:port] || 80
    if proxy_host = @config[:proxy_host]
      @proxy_host = proxy_host
      @proxy_port = @config[:proxy_port]
    end

    @session_token = session_token
  end

  def symbolize_keys(obj)
    case obj
      when Array
        obj.inject([]) { |res, val|
          res << case val
            when Hash, Array
              symbolize_keys(val)
            else
              val
          end
          res
        }
      when Hash
        obj.inject({}) { |res, (key, val)|
          nkey      = case key
            when String
              key.to_sym
            else
              key
          end
          nval      = case val
            when Hash, Array
              symbolize_keys(val)
            else
              val
          end
          res[nkey] = nval
          res
        }
      else
        obj
    end
  end
end