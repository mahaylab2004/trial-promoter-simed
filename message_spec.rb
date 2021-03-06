# == Schema Information
#
# Table name: messages
#
#  id                           :integer          not null, primary key
#  message_template_id          :integer
#  content                      :text
#  tracking_url                 :string(2000)
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  website_id                   :integer
#  message_generating_id        :integer
#  message_generating_type      :string
#  promotable_id                :integer
#  promotable_type              :string
#  medium                       :string
#  image_present                :string
#  image_id                     :integer
#  publish_status               :string
#  scheduled_date_time          :datetime
#  social_network_id            :string
#  social_media_profile_id      :integer
#  platform                     :string
#  promoted_website_url         :string(2000)
#  campaign_id                  :string
#  backdated                    :boolean
#  original_scheduled_date_time :datetime
#  click_rate                   :float
#  website_goal_rate            :float
#  website_goal_count           :integer
#  website_session_count        :integer
#  impressions_by_day           :text
#  note                         :text
#


require 'rails_helper'

describe Message do
  it { is_expected.to belong_to :message_template }
  it { is_expected.to enumerize(:publish_status).in(:pending, :published_to_buffer, :published_to_social_network).with_default(:pending).with_predicates(true) }
  it { is_expected.to have_one :buffer_update }
  it { is_expected.to have_one(:click_meter_tracking_link).dependent(:destroy) }
  it { is_expected.to have_many :metrics }
  it { is_expected.to have_many :comments }
  it { is_expected.to have_many :image_replacements }
  it { is_expected.to have_many :comments }
  it { is_expected.to belong_to(:message_generating) }
  it { is_expected.to enumerize(:platform).in(:twitter, :facebook, :instagram) }
  it { is_expected.to enumerize(:medium).in(:ad, :organic).with_default(:organic) }
  it { is_expected.to enumerize(:image_present).in(:with, :without).with_default(:without) }
  it { is_expected.to belong_to :image }
  it { is_expected.to belong_to :social_media_profile }
  it { is_expected.to validate_presence_of :message_generating }
  it { is_expected.to validate_presence_of :platform }
  it { is_expected.to validate_presence_of :promoted_website_url }
  it { is_expected.to validate_presence_of :content }
  it { is_expected.to serialize(:impressions_by_day).as(Hash) }

  it 'returns the medium as a symbol' do
    message = build(:message)
    message.medium = :ad

    expect(message.medium).to be :ad
  end

  it 'returns the platform as a symbol' do
    message = build(:message, platform: 'twitter')

    expect(message.platform).to be(:twitter)
  end

  describe "#visits" do
    before do
      @messages = create_list(:message, 3)

      Visit.create(id: 67, visit_token: "f07cdbd3-6df5-4aae-bf3b-9e23f2cf15b0", visitor_token: "4ff38d8e-5a4f-4af5-baee-2f068ae5b66d", ip: "128.125.77.139", user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWeb...", referrer: nil, landing_page: "http://promoter-staging.sc-ctsi.org/users/sign_in", user_id: nil, referring_domain: nil, search_keyword: nil, browser: "Chrome", os: "Windows 10", device_type: "Desktop", screen_height: 1200, screen_width: 1920, country: "United States", region: "California", city: "Los Angeles", postal_code: "90089", latitude: "#<BigDecimal:7f162d8729a0,'0.337866E2',18(18)>", longitude: "#<BigDecimal:7f162d8728b0,'-0.1182987E3',18(18)>", utm_source: nil, utm_medium: nil, utm_term: nil, utm_content: @messages[1].to_param, utm_campaign: nil, started_at: "2017-02-15 19:46:14")
    end

    it "correctly ties in visits to each message via the utm_content on the visit" do
      expect(@messages[1].visits.count).to eq(1)
      expect(@messages[1].visits[0].utm_content).to eq(@messages[1].to_param)
    end

    it "returns an empty array if no visits have occurred" do
      expect(@messages[2].visits.count).to eq(0)
    end
  end

  describe "#events" do
    before do
      @messages = create_list(:message, 4)

      Ahoy::Event.create(id: 7, visit_id: 10, user_id: nil, name: "Converted", properties: { "utm_source": "twitter", "utm_campaign": "smoking cessation", "utm_medium": "ad", "utm_term": "cessation123", "utm_content": @messages[2].to_param, "conversionTracked": true, "time": 1487207159071}, time: "2017-02-16 01:05:59")
    end

    it "correctly ties in events to each message via the utm_content on the properties for each event" do
      expect(@messages[2].events.count).to eq(1)
      expect(@messages[2].events[0].properties["utm_content"]).to eq(@messages[2].to_param)
    end

    it "returns an empty array if no events have occurred" do
      expect(@messages[3].events.count).to eq(0)
    end
  end

  xit 'always updates existing metrics from a particular source' do
    # Saving a message and then updating the same metric DOES NOT WORK!
    message = build(:message)

    message.metrics << Metric.new(source: :twitter, data: {"likes": 1})
    message.save
    message.metrics << Metric.new(source: :twitter, data: {"likes": 2})
    message.save

    message.reload
    expect(message.metrics.length).to eq(1)
    expect(message.metrics[0].data[:likes]).to eq(2)
  end

  it "parameterizes id and the experiments's param together" do
    experiment = create(:experiment, name: 'TCORS 2')
    message = create(:message, message_generating: experiment)
    expect(message.to_param).to eq("#{experiment.to_param}-message-#{message.id.to_s}")
  end

  it 'finds a message by the param' do
    create(:message)

    message = Message.find_by_param(Message.first.to_param)

    expect(message).to eq(Message.first)
  end

  describe 'pagination' do
    before do
      create_list(:message, 100)
      @messages = Message.order('created_at ASC')
    end

    it 'has a default of 90 messages per page' do
      page_of_messages = Message.page(1)

      expect(page_of_messages.count).to eq(90)
    end

    it 'returns the first page of messages given a per page value' do
      page_of_messages = Message.order('created_at ASC').page(1).per(5)

      expect(page_of_messages.count).to eq(5)
      expect(page_of_messages[0]).to eq(@messages[0])
    end

    it 'returns the second page of messages given a per page value' do
      page_of_messages = Message.order('created_at ASC').page(2).per(5)

      expect(page_of_messages.count).to eq(5)
      expect(page_of_messages[0]).to eq(@messages[5])
    end

    it 'returns a page of messages given a condition' do
      page_of_messages = Message.where(content: 'Content').order('created_at ASC').page(2).per(5)

      expect(page_of_messages.count).to eq(5)
      expect(page_of_messages[0]).to eq(@messages[5])
    end
  end

  describe '#delayed?' do
    before do
      @message = create(:message)
      @message.scheduled_date_time = "2017-10-10 13:04:00"
      @message.buffer_update = BufferUpdate.new(id: 2, buffer_id: "23423244", service_update_id: "2343225435247", status: "pending", message_id: 1128, created_at: "2017-02-17 19:55:02", updated_at: "2017-02-21 23:19:04", sent_from_date_time: "2017-10-10 13:09:22")
    end

    it 'checks if message sent from Buffer has been delayed' do
      expect(@message.delayed?).to be(true)
    end

    it 'checks if message sent from Buffer was on-time' do
      @message.scheduled_date_time = "2017-10-10 13:09:00"

      expect(@message.delayed?).to be(false)
    end
  end

  describe 'metric helpers' do
    before do
      @message = create(:message)
      visits = create_list(:visit, 3, utm_content: @message.to_param)
      Ahoy::Event.create(visit_id: visits[0].id, name: "Converted")

      @message_with_no_sessions_or_goals = create(:message)
      @message_with_no_sessions_or_goals.metrics << Metric.new(source: :twitter, data: {"clicks" => nil, "impressions" => nil})
      @message_with_no_sessions_or_goals.save
    end

    it 'returns N/A if asked to retrieve a metric for a missing source' do
      expect(@message.metric_facebook_likes).to eq('N/A')
    end

    it 'returns N/A if asked to retrieve a missing metric for an existing source' do
      @message.metrics << Metric.new(source: :facebook, data: {"likes" => 5})
      expect(@message.metric_facebook_shares).to eq('N/A')
    end

    it 'returns the value of the metric if asked to retrieve an existing metric for an existing source' do
      @message.metrics << Metric.new(source: :facebook, data: {"likes" => 5})
      expect(@message.metric_facebook_likes).to eq(5)
    end

    it 'returns N/A when asked to find a percentage given a missing source' do
      @message.metrics << Metric.new(source: :twitter, data: {"shares" => 100})
      expect(@message.percentage_facebook_clicks_impressions).to eq('N/A')
    end

    it 'returns N/A when asked to find a percentage given two metric names, either of which is missing' do
      @message.metrics << Metric.new(source: :facebook, data: {"impressions" => 100})
      expect(@message.percentage_facebook_clicks_impressions).to eq('N/A')

      @message.metrics << Metric.new(source: :facebook, data: {"clicks" => 5})
      expect(@message.percentage_facebook_clicks_impressions).to eq('N/A')
    end

    it 'returns N/A when asked to find a percentage given two metric names, both of which are missing' do
      @message.metrics << Metric.new(source: :facebook, data: {"shares" => 100})
      expect(@message.percentage_facebook_clicks_impressions).to eq('N/A')
    end

    it 'returns N/A when the value of both metrics is 0' do
      @message.metrics << Metric.new(source: :facebook, data: {"clicks" => 0, "impressions" => 0})
      expect(@message.percentage_facebook_clicks_impressions).to eq('N/A')
    end

    it 'returns a percentage given two metric names (first metric / second metric accurate to two decimal places)' do
      @message.metrics << Metric.new(source: :facebook, data: {"clicks" => 5, "impressions" => 100})
      expect(@message.percentage_facebook_clicks_impressions).to eq(5.0)
    end
  end

  describe 'message click rate and website goal rate calculations' do
    before do
      @message = create(:message)
      visits = create_list(:visit, 3, utm_content: @message.to_param)
      Ahoy::Event.create(visit_id: visits[0].id, name: "Converted")

      @message_with_no_sessions_or_goals = create(:message)
    end

    it 'saves a nil value if there are no clicks or sessions' do
      @message.metrics << Metric.new(source: :twitter, data: {"clicks" => nil, "impressions" => nil})
      @message.save

      @message.calculate_click_rate
      @message.reload

      expect(@message.click_rate).to eq(nil)
    end

    it 'saves the number of goals for a given message' do
      @message.calculate_goal_count
      @message.reload

      expect(@message.website_goal_count).to eq(1)
    end

    it 'saves the sessions (Ahoy visits) for a given message' do
      @message.calculate_session_count
      @message.reload

      expect(@message.website_session_count).to eq(3)
    end

    it 'saves a goal rate percentage from Ahoy (goals / visits)' do
      @message.calculate_website_goal_rate
      @message.reload

      expect(@message.website_goal_rate).to eq(33.33)
    end

    it 'saves a nil value in website_goal_rate if there are no sessions and no goals' do
      @message_with_no_sessions_or_goals.calculate_website_goal_rate
      @message_with_no_sessions_or_goals.reload

      expect(@message_with_no_sessions_or_goals.website_goal_rate).to eq(nil)
    end

    it 'saves 0 in website_session_count if there are no sessions' do
      @message_with_no_sessions_or_goals.calculate_session_count
      @message_with_no_sessions_or_goals.reload

      expect(@message_with_no_sessions_or_goals.website_session_count).to eq(0)
    end

    it 'saves 0 in website_goal_count if there are no goals' do
      @message_with_no_sessions_or_goals.calculate_goal_count
      @message_with_no_sessions_or_goals.reload

      expect(@message_with_no_sessions_or_goals.website_goal_count).to eq(0)
    end
  end

  describe 'campaign_id helper methods do' do
    before do
      @messages = create_list(:message, 5)
      @messages[0].platform = 'twitter'
      @messages[1].platform = 'facebook'
      @messages[2].platform = 'facebook'
      @messages[3].platform = 'instagram'
      @messages[4].platform = 'twitter'

      @messages[0].medium = :ad
      @messages[1].medium = :ad
      @messages[2].medium = :organic
      @messages[3].medium = :ad
      @messages[4].medium = :organic

      @messages[0].campaign_id = '123456'
      @messages[1].campaign_id = '123456'
      @messages[2].campaign_id = '123456'
      @messages[3].campaign_id = '123456'
      @messages[4].campaign_id = '123456'
    end

    describe '#show_campaign_id' do
      it "only shows the campaign_id field for Facebook or Instagram Ad accounts" do
        expect(@messages[0].show_campaign_id?).to eq(false)
        expect(@messages[1].show_campaign_id?).to eq(true)
        expect(@messages[2].show_campaign_id?).to eq(false)
        expect(@messages[3].show_campaign_id?).to eq(true)
        expect(@messages[4].show_campaign_id?).to eq(false)
      end

      it 'does not show campaign_id for an organic message' do
        expect(@messages[2].show_campaign_id?).to eq(false)
        expect(@messages[4].show_campaign_id?).to eq(false)
      end
    end

    describe '#edit_campaign_id' do
      before do
        @messages[0].campaign_id = nil
        @messages[1].campaign_id = nil
        @messages[2].campaign_id = nil
        @messages[3].campaign_id = nil
        @messages[4].campaign_id = nil
      end

      it "only allows editing the campaign_id form for Facebook or Instagram Ad accounts" do
        expect(@messages[0].edit_campaign_id?).to eq(false)
        expect(@messages[1].edit_campaign_id?).to eq(true)
        expect(@messages[2].edit_campaign_id?).to eq(false)
        expect(@messages[3].edit_campaign_id?).to eq(true)
        expect(@messages[4].edit_campaign_id?).to eq(false)
      end

      it 'does not allow editing campaign_id field for an organic message' do
        expect(@messages[2].edit_campaign_id?).to eq(false)
        expect(@messages[4].edit_campaign_id?).to eq(false)
      end
    end
  end

  xdescribe 'backdating' do
    before do
      allow(Throttler).to receive(:throttle)
    end

    # Backdating is a process that we included for the TCORS pilot project.
    # Twitter ads starting from 05/31 were scheduled for publishing 5 days in advance.
    # This was done to give Twitter support enough time to approve the tweets in scheduled campaigns.
    it 'backdates a Twitter ad message' do
      message_scheduled_date_time = DateTime.new(2017, 6, 10, 15, 0, 0)
      message = create(:message, :platform => :twitter, :medium => :ad, :scheduled_date_time => message_scheduled_date_time)

      message.backdate(5)

      expect_backdated(message, message_scheduled_date_time)
    end

    it 'only backdates a message once' do
      message_scheduled_date_time = DateTime.new(2017, 6, 10, 15, 0, 0)
      message = create(:message, :platform => :twitter, :medium => :ad, :scheduled_date_time => message_scheduled_date_time)

      message.backdate(5)
      message.backdate(5)

      expect_backdated(message, message_scheduled_date_time)
    end

    it 'only backdates any Twitter ad messages scheduled on or after May 31st' do
      message_scheduled_date_time = DateTime.new(2017, 5, 31, 15, 0, 0)
      message = create(:message, :platform => :twitter, :medium => :ad, :scheduled_date_time => message_scheduled_date_time)

      message.backdate(5)

      expect_backdated(message, message_scheduled_date_time)
    end

    it 'deletes any associated buffer update' do
      message_scheduled_date_time = DateTime.new(2017, 5, 31, 15, 0, 0)
      message = create(:message, :platform => :twitter, :medium => :ad, :scheduled_date_time => message_scheduled_date_time)
      buffer_update = create(:buffer_update)
      allow(buffer_update).to receive(:destroy)
      message.buffer_update = buffer_update
      message.publish_status = :published_to_buffer
      message.save

      message.backdate(5)

      expect_backdated(message, message_scheduled_date_time)
      expect(buffer_update).to have_received(:destroy)
      expect(message.buffer_update).to be nil
      expect(message.publish_status).to eq(:pending)
    end

    it 'does not backdate any Twitter ad messages scheduled before May 31st' do
      message_scheduled_date_time = DateTime.new(2017, 5, 30, 15, 0, 0)
      message = create(:message, :platform => :twitter, :medium => :ad, :scheduled_date_time => message_scheduled_date_time)

      message.backdate(5)

      expect_not_backdated(message, message_scheduled_date_time)
    end

    it 'does not backdate any organic Twitter messages' do
      message_scheduled_date_time = DateTime.new(2017, 6, 10, 15, 0, 0)
      message = create(:message, :platform => :twitter, :medium => :organic, :scheduled_date_time => message_scheduled_date_time)

      message.backdate(5)

      expect_not_backdated(message, message_scheduled_date_time)
    end

    it 'does not backdate any Facebook' do
      message_scheduled_date_time = DateTime.new(2017, 6, 10, 15, 0, 0)
      message = create(:message, :platform => :facebook, :medium => :organic, :scheduled_date_time => message_scheduled_date_time)

      message.backdate(5)

      expect_not_backdated(message, message_scheduled_date_time)
    end

    it 'does not backdate any Instagram messages' do
      message_scheduled_date_time = DateTime.new(2017, 6, 10, 15, 0, 0)
      message = create(:message, :platform => :instagram, :medium => :organic, :scheduled_date_time => message_scheduled_date_time)

      message.backdate(5)

      expect_not_backdated(message, message_scheduled_date_time)
    end
  end
  
  describe 'finding messages by alternative identifier' do
    before do
      @messages = create_list(:message, 6)
      @messages[0].platform = 'twitter'
      @messages[1].platform = 'facebook'
      @messages[2].platform = 'facebook'
      @messages[3].platform = 'instagram'
      @messages[4].platform = 'twitter'
      @messages[5].platform = 'twitter'

      @messages[0].medium = :ad
      @messages[1].medium = :ad
      @messages[2].medium = :organic
      @messages[3].medium = :ad
      @messages[4].medium = :organic
      @messages[5].medium = :organic

      @messages[0].social_network_id = '114749583439036416'
      @messages[1].campaign_id = '12345678'
      @messages[2].social_network_id = '1605839243031680_1867404650208470'
      @messages[3].campaign_id = '23456789'
      @messages[4].social_network_id = '104749583439036410'
      @messages[5].buffer_update = create(:buffer_update, :published_text => 'Some text unique to this message')
      
      @messages.each { |message| message.save }
    end
    
    it 'finds a Twitter (ad or organic) message by its social_network_id' do
      message = Message.find_by_alternative_identifier('114749583439036416')
      
      expect(message).not_to be_nil
      expect(message.social_network_id).to eq('114749583439036416')
    end

    it 'finds a Facebook (organic) message by its social_network_id' do
      message = Message.find_by_alternative_identifier('1605839243031680_1867404650208470')
      
      expect(message).not_to be_nil
      expect(message.social_network_id).to eq('1605839243031680_1867404650208470')
    end
    
    it 'finds a Facebook (ad) message by its campaign_id (even if a social_network_id exists)' do
      message = Message.find_by_alternative_identifier('12345678')
      
      expect(message).not_to be_nil
      expect(message.campaign_id).to eq('12345678')
    end

    it 'finds an Instagram (ad) message by its campaign_id' do
      message = Message.find_by_alternative_identifier('23456789')
      
      expect(message).not_to be_nil
      expect(message.campaign_id).to eq('23456789')
    end
    
    it 'finds a message by the published_text in the associated buffer_update' do
      message = Message.find_by_alternative_identifier('Some text unique to this message')
      
      expect(message).not_to be_nil
      expect(message.buffer_update.published_text).to eq('Some text unique to this message')
    end
  end
  
  it 'returns the scheduled_date_time if a message has not been backdated' do
    message = Message.new(scheduled_date_time: DateTime.new(2017, 6, 1, 0, 0, 0))
    message.backdated = nil
    
    expect(message.scheduled_date_time).to eq(DateTime.new(2017, 6, 1, 0, 0, 0))

    message.backdated = false

    expect(message.scheduled_date_time).to eq(DateTime.new(2017, 6, 1, 0, 0, 0))
  end

  it 'returns the original_scheduled_date_time if a message has been backdated' do
    message = Message.new(scheduled_date_time: DateTime.new(2017, 6, 1, 0, 0, 0), original_scheduled_date_time: DateTime.new(2017, 5, 27, 0, 0, 0))
    message.backdated = true
    
    expect(message.scheduled_date_time).to eq(DateTime.new(2017, 5, 27, 0, 0, 0))
  end
  
  it 'finds a message by the text that was published to the social media platform' do
    messages = create_list(:message, 3)
    messages[0].buffer_update = create(:buffer_update, published_text: "Hydrogen cyanide is found in rat poison. It???s also in #cigarette smoke. http://bit.ly/2t2KVBd")
    messages[1].buffer_update = create(:buffer_update, published_text: "#Smoking can shorten your life by over 12%. If you smoke, you may be cuttin??? your time with the fam short. http://bit.ly/2uvKzrc")
    messages[2].buffer_update = create(:buffer_update, published_text: "#Tobacco use causes ~20% of all US deaths-more than AIDS, alcohol, car accidents, homicides & illegal drugs combined http://bit.ly/2sDLTYh")
    published_post = "Hydrogen cyanide is found in rat poison. It???s also in #cigarette smoke. http://bit.ly/2t2KVBd"

    expect(Message.find_by_published_text(published_post)).to eq(messages[0])
  end
   
  it 'raises an exception if a duplicate message text is found' do
    messages = create_list(:message, 3)
    messages.each{|message| message.buffer_update = create(:buffer_update, published_text: "Hydrogen cyanide is found in rat poison. It???s also in #cigarette smoke. http://bit.ly/2t2KVBd") }
    published_post = "Hydrogen cyanide is found in rat poison. It???s also in #cigarette smoke. http://bit.ly/2t2KVBd"
    
    expect { Message.find_by_published_text(published_post) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
      
  it "returns the tagged experiment" do
    experiment = create(:experiment, name: 'TCORS 2')
    message = build(:message)
    message.experiment_list.add(experiment.to_param)

    expect(message.experiment).to eq(experiment)
  end
  
  private
  def expect_backdated(message, message_scheduled_date_time)
    message.reload
    expect(message.scheduled_date_time).to eq(message_scheduled_date_time - 5.days)
    expect(message.backdated).to be true
    expect(message.original_scheduled_date_time).to eq(message_scheduled_date_time)
    if !message.buffer_update.nil?
      expect(Throttler).to have_received(:throttle).with(1)
    end
  end

  def expect_not_backdated(message, message_scheduled_date_time)
    message.reload
    expect(message.scheduled_date_time).to eq(message_scheduled_date_time)
    expect(message.backdated).to be nil
    expect(message.original_scheduled_date_time).to be nil
  end
end
