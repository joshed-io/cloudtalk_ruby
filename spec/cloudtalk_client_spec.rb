require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe CloudtalkClient do
  before do
    @cloudtalk = CloudtalkClient.new
    @config = File.read(File.expand_path(File.dirname(__FILE__) + '/../cloudtalk.yml')).symbolize_keys![:cloudtalk]
  end

  describe "#login" do
    it "should allow a login as the configured group admin" do
      session_token = @cloudtalk.su_login
      session_token.should =~ /UA[\w|-]{36}/
    end

    it "should set the user ticket as the session token" do
      @cloudtalk.session_token.should be_nil
      session_token = @cloudtalk.su_login
      @cloudtalk.session_token.should == session_token
    end
  end

  describe "#su_login" do
    before do
      @given_user = create_user_helper(@cloudtalk)
      @cloudtalk_user = @given_user[:cloudtalk_user]
    end

    xit "should return a ticket was for the pseudo'd user (not the root user) when using userID as the key" do
      @cloudtalk.su_login(:userID => @cloudtalk_user[:userID])
      @cloudtalk.last_response[:displayName].should == @cloudtalk_user[:displayName]
      @cloudtalk.session_token.should_not be_nil
      @cloudtalk.user_profile[:userName].should == @cloudtalk_user[:userName]
    end

    it "should allow login with the login, not just the userID, and return a ticker for the psuedo'd user" do
      @cloudtalk.su_login(:login => @given_user[:username])
      @cloudtalk.last_response[:displayName].should == @cloudtalk_user[:displayName]
      @cloudtalk.session_token.should_not be_nil
      @cloudtalk.user_profile[:userName].should == @cloudtalk_user[:userName]
    end
  end

  describe "#create_partner_user" do
    it "should allow creation with valid attributes" do
      cloudtalk_user = @cloudtalk.partner_create_user(
              username = "josh_#{m = millis}",
              password     = rand(36**8).to_s(8),
              email = "ctalk_id_josh+#{m}@dz.oib.com",
              display_name = "Josh Dz #{m}",
              "http://www.gravatar.com/avatar/aee8ace6215b362ce4524bfdfc4a718c.png")
      cloudtalk_user[:userID].should =~ /US[\w|-]{36}/
      cloudtalk_user[:validateID].should =~ /UV[\w|-]{36}/
      cloudtalk_user[:userTicket].should =~ /UA[\w|-]{36}/
      cloudtalk_user[:userName].should == "#{@config[:username_prefix]}.#{username}"
      cloudtalk_user[:displayName].should == display_name
      @cloudtalk.session_token.should_not be_nil
    end
  end

  describe "#update_user_profile" do
    before do
      @cloudtalk_user = create_user_helper(@cloudtalk, false)[:cloudtalk_user]
    end

    it "should accept an update" do
      @cloudtalk.update_user_profile(:displayName => display_name = "Terry")
      sleep 5
      @cloudtalk.user_profile[:displayName].should == display_name
    end
  end

  describe "#set_relation" do
    before do
      @cloudtalk_user = create_user_helper(@cloudtalk, false)[:cloudtalk_user]
    end

    it "should set the relation between two users appropriately" do
      @cloudtalk.set_relation(@cloudtalk_user[:userID])
      @cloudtalk.get_relations.should_not == []
    end
  end

  describe "#get_relations" do
    before do
      @cloudtalk_user = create_user_helper(@cloudtalk, false)[:cloudtalk_user]
      @cloudtalk.set_relation(@cloudtalk_user[:userID])
    end

    it "should get the relations with the user" do
      @cloudtalk.get_relations.first[:userID].should == @cloudtalk_user[:userID]
    end
  end

  describe "#update_user_image" do
    before do
      @cloudtalk_user = create_user_helper(@cloudtalk, false)[:cloudtalk_user]
    end

    it "should successfully perform an update of binary data" do
      @cloudtalk.update_user_image("logo.png", File.expand_path(File.dirname(__FILE__) + '/ibone.jpeg'))
    end
  end

  describe "accessing required service without a user ticket" do
    xit "should fail with a bad request"
  end

  describe "#user_profile" do
    before do
      @cloudtalk_user = create_user_helper(@cloudtalk, false)[:cloudtalk_user]
    end

    it "should return the user profile for the token haver" do
      user_profile_results = @cloudtalk.user_profile
      user_profile_results[:userName].should == @cloudtalk_user[:userName]
    end
  end

  describe "#requires_array" do
    it "should return true if it requires an array" do
      @cloudtalk.send(:requires_array?, :set_relation).should be_true
    end

    it "should return false if it does not require an array" do
      @cloudtalk.send(:requires_array?, :get_relations).should be_false
    end
  end

  describe "#get_my_inbox" do
    before do
      @cloudtalk_user = (@given_user = create_user_helper(@cloudtalk))[:cloudtalk_user]
      @cloudtalk.su_login({:login => @given_user[:username]})
    end

    it "should get the inbox for the ticketed user when there are no conversations" do
      my_inbox = @cloudtalk.get_my_inbox
      my_inbox[:conversations].should_not be_nil
      my_inbox[:nextStartingDate].should_not be_nil
      my_inbox[:conversationTotal].should_not be_nil
    end

    context "has conversations" do
      before do
        @cloudtalk_receiver = create_user_helper(@cloudtalk)[:cloudtalk_user]
        @cloudtalk.su_login({:login => @given_user[:username]})
        @message = @cloudtalk.create_message(
                :messageText => "Hello, world!",
                :participants => [
                        {:participantID   => @cloudtalk_user[:userID],
                         :participantName => @cloudtalk_user[:userName]},
                        {:participantID   => @cloudtalk_receiver[:userID],
                         :participantName => @cloudtalk_receiver[:userName]}
                ]
        )
      end

      it "should get the inbox for the ticketed user when there are conversations" do
        sleep 5
        my_inbox = @cloudtalk.get_my_inbox
        my_inbox[:conversations].count.should == 1
        my_inbox[:conversations].first[:conversationID].should == @message[:conversationID]
      end
    end
  end

  describe "#get_messages" do
    before do
      @cloudtalk_user = (@given_user = create_user_helper(@cloudtalk))[:cloudtalk_user]
      @cloudtalk_receiver = create_user_helper(@cloudtalk)[:cloudtalk_user]
      @cloudtalk.su_login({:login => @given_user[:username]})
      @message = @cloudtalk.create_message(
              :messageText => "Hello, world!",
              :participants => [{:participantID   => @cloudtalk_user[:userID]},
                                {:participantID   => @cloudtalk_receiver[:userID]}]
      )
    end

    it "should get the messages when given a conversation ID" do
      sleep 10
      messages = @cloudtalk.get_messages(:conversationID => @message[:conversationID])
      messages.size.should == 1
      messages.first[:messageID].should == @message[:messageID]
    end
  end

  describe "#create_message" do
    it "should work given valid attributes without a conversation id" do
      message = create_message_helper(@cloudtalk)
      message[:messageID].should =~ /PRM[\w|-]{36}/
      message[:conversationID].should =~ /PRC[\w|-]{36}/
      message[:messageCategory].should_not be_nil
      message[:messageURL].should =~ /http/
    end

    context "with a conversation id" do
      before do
        @first_message = create_message_helper(@cloudtalk)
        @conversation_id = @first_message[:conversationID]
      end

      it "should work given valid attributes with a conversation id" do
        sleep 20
        @new_message = @cloudtalk.create_message(
                :messageText => "Hello, world!",
                :conversationID => @conversation_id
        )
        @new_message[:conversationID].should == @first_message[:conversationID]
      end
    end
  end

  describe "#hide_private_conversation" do
    before do
      @cloudtalk_user = (@given_user = create_user_helper(@cloudtalk))[:cloudtalk_user]
      @cloudtalk.su_login({:login => @given_user[:username]})
      @message = @cloudtalk.create_message(
              :messageText => "Hide me!",
              :participants => [{:participantID   => @cloudtalk_user[:userID]}])
    end

    it "should hide a conversation" do
      mock(@cloudtalk.hide_private_conversation(@message[:conversationID]))
    end
  end

  def millis
    Time.now.to_f.to_s.gsub(/\./, "")
  end

  def create_user_helper(cloudtalk, clear_session=true)
    cloudtalk_user = cloudtalk.partner_create_user(
            username     = "josh_#{m = millis}",
            password     = rand(36**8).to_s(8),
            email        = "ctalk_id_josh+#{m}@dz.oib.com",
            display_name = "Josh Dz #{m}",
            "http://www.gravatar.com/avatar/aee8ace6215b362ce4524bfdfc4a718c.png")
    cloudtalk.clear_user if clear_session
    {:username => username, :email => email,
     :display_name => display_name, :password => password,
     :cloudtalk_user => cloudtalk_user}
  end

  def create_message_helper(cloudtalk)
    @cloudtalk_receiver = create_user_helper(cloudtalk)
    @cloudtalk_sender = create_user_helper(cloudtalk, false)
    cloudtalk.create_message(
            :messageText => "Hello, world!",
            :participants => [
                    {:participantID   => @cloudtalk_sender[:cloudtalk_user][:userID]},
                    {:participantID   => @cloudtalk_receiver[:cloudtalk_user][:userID]}
            ]
    )
  end
end
