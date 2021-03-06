require 'rails_helper'

RSpec.describe MessageFactory do
  before do
    @experiment = create(:experiment)
    @experiment.use_click_meter = true
    @experiment.click_meter_group_id = 1
    @experiment.click_meter_domain_id = 2
    @suitable_social_media_profiles = create_list(:social_media_profile, 5)
    @suitable_social_media_profiles[0].platform = :facebook
    @suitable_social_media_profiles[0].allowed_mediums = [:ad]
    @suitable_social_media_profiles[1].platform = :facebook
    @suitable_social_media_profiles[1].allowed_mediums = [:organic]
    @suitable_social_media_profiles[2].platform = :twitter
    @suitable_social_media_profiles[2].allowed_mediums = [:ad]
    @suitable_social_media_profiles[3].platform = :twitter
    @suitable_social_media_profiles[3].allowed_mediums = [:organic]
    @suitable_social_media_profiles[4].platform = :instagram
    @suitable_social_media_profiles[4].allowed_mediums = [:ad]
    @suitable_social_media_profiles.each { |social_media_profile| @experiment.social_media_profiles << social_media_profile }
    @experiment.save
    @message_templates = create_list(:message_template, 5, platforms: TrialPromoter::SUPPORTED_NETWORKS, experiment_list: @experiment.to_param)
    # Create 2 images for each message template's image pool
    @message_templates.each do |message_template|
      images = create_list(:image, 2, experiment_list: @experiment.to_param)
      message_template.image_pool = images.map(&:id)
      message_template.save
    end
    # Add the {url} parameter to each message template.
    @message_templates.each do |message_template|
      message_template.content += '{url}'
      message_template.save
    end
    # Add some hashtags to the first 3 message templates
    @message_templates[0..2].each do |message_template|
      random_hashtags = ['#hashtag1,#hashtag2,#hashtag3','#hashtag1,#hashtag4,#hashtag5','#hashtag6,#hashtag7,#hashtag8']
      message_template.hashtags = random_hashtags.sample
      message_template.save
    end
    # Set up social media profile picking
    @social_media_profile_picker = SocialMediaProfilePicker.new
    allow(@social_media_profile_picker).to receive(:pick).with(@suitable_social_media_profiles, Symbol, Symbol).and_return(@suitable_social_media_profiles[1])
    @message_factory = MessageFactory.new(@social_media_profile_picker)
    # Set up Pusher mocks
    @pusher_channel = double()
    allow(Pusher).to receive(:[]).with('progress').and_return(@pusher_channel)
    allow(@pusher_channel).to receive(:trigger)
    # Set up click tracking
    allow(ClickMeterClient).to receive(:create_click_meter_tracking_link).and_call_original
    click_meter_tracking_link = ClickMeterTrackingLink.new
    click_meter_tracking_link.click_meter_id = "100"
    click_meter_tracking_link.click_meter_uri = "/datapoints/100"
    click_meter_tracking_link.tracking_url = 'http://tracking-url.com'
    click_meter_tracking_link.destination_url = 'http://destination-url.com'
    allow(ClickMeterClient).to receive(:get_tracking_link).and_return(click_meter_tracking_link)
    allow(ClickMeterClient).to receive(:delete_tracking_link)
    # Set up action throttling
    allow(@message_factory).to receive(:throttle).and_call_original
  end

  it 'can be initialized with a social media profile picker' do
    @message_factory = MessageFactory.new(@social_media_profile_picker)
    
    expect(@message_factory.social_media_profile_picker).to eq(@social_media_profile_picker)
  end
  
  it 'returns a hash of parameters for message generation' do
    @experiment.facebook_posting_times = "12:30 PM"
    @experiment.save
    message_generation_parameter_set = MessageGenerationParameterSet.new do |m|
      m.social_network_choices = [:facebook]
      m.medium_choices = ['ad']
      m.image_present_choices = :no_messages
      m.number_of_cycles = 1
      m.number_of_messages_per_social_network = 1
    end
    @experiment.message_generation_parameter_set = message_generation_parameter_set

    parameters = @message_factory.get_message_generation_parameters(@experiment)

    expect(parameters[:message_constructor]).not_to be_nil
    expect(parameters[:number_of_cycles]).to eq(@experiment.message_generation_parameter_set.number_of_cycles)
    expect(parameters[:number_of_messages_per_day]).to eq(@experiment.message_generation_parameter_set.number_of_messages_per_social_network)
    expect(parameters[:number_of_days_between_posting]).to eq(@experiment.message_generation_parameter_set.number_of_days_between_posting)
    expect(parameters[:platforms]).to eq(@experiment.message_generation_parameter_set.social_network_choices)
    expect(parameters[:mediums]).to eq(@experiment.message_generation_parameter_set.medium_choices)
    expect(parameters[:message_templates]).to eq(MessageTemplate.belonging_to(@experiment).to_a)
    expect(parameters[:message_templates]).to be_instance_of(Array)
    expect(parameters[:posting_times]).to eq(@experiment.posting_times)
    expect(parameters[:total_count]).to eq(@experiment.message_generation_parameter_set.expected_generated_message_count(parameters[:message_templates].count))
    expect(parameters[:social_media_profiles]).to eq(@experiment.social_media_profiles)
    expect(parameters[:tracking_link_client]).to eq(ClickMeterClient)
  end

  it 'returns a BasicTrackingLinkClient if the experiment does not use Click Meter' do
    @experiment.facebook_posting_times = "12:30 PM"
    @experiment.use_click_meter = false
    @experiment.save
    message_generation_parameter_set = MessageGenerationParameterSet.new do |m|
      m.social_network_choices = [:facebook]
      m.medium_choices = ['ad']
      m.image_present_choices = :no_messages
      m.number_of_cycles = 1
      m.number_of_messages_per_social_network = 1
    end
    @experiment.message_generation_parameter_set = message_generation_parameter_set

    parameters = @message_factory.get_message_generation_parameters(@experiment)

    expect(parameters[:tracking_link_client]).to eq(BasicTrackingLinkClient)
  end

  it 'creates a set of messages given five message templates, 1 social network, 1 medium, images for all messages, 1 cycle, 1 message per network per day (no hashtags)' do
    @experiment.facebook_posting_times = "12:30 PM"
    @experiment.save
    message_generation_parameter_set = MessageGenerationParameterSet.new do |m|
      m.social_network_choices = [:facebook]
      m.medium_choices = ['ad']
      m.image_present_choices = :all_messages
      m.number_of_cycles = 1
      m.number_of_messages_per_social_network = 1
    end
    @experiment.message_generation_parameter_set = message_generation_parameter_set
    expected_generated_message_count = message_generation_parameter_set.expected_generated_message_count(MessageTemplate.count)

    @message_factory.create(@experiment)
    
    messages = Message.all.order('created_at ASC')
    # Have the correct number of messages been generated?
    expect(messages.count).to eq(expected_generated_message_count)
    # Is every message for the right platform?
    expect((messages.select{ |message| message.platform != :facebook }).count).to eq(0)
    # Is every message for the right medium?
    expect((messages.select{ |message| message.medium != :ad }).count).to eq(0)
    # Does every message have a promoted_website_url?
    expect((messages.select{ |message| message.promoted_website_url.nil? }).count).to eq(0)
    # Does every message have a suitable social media profile selected?
    messages.each do |message|
      expect(message.social_media_profile).to eq(@suitable_social_media_profiles[1])
    end
    # Were the pusher events triggered?
    expect(@pusher_channel).to have_received(:trigger).exactly(expected_generated_message_count * 2).times.with('progress', {:value => an_instance_of(Fixnum), :total => expected_generated_message_count, :event => 'Message generated'})
    # Was the message generation throttled (limit of 10 req/sec for Click Meter)
    expect(@message_factory).to have_received(:throttle).with(9).exactly(expected_generated_message_count * 2).times
 
    # Has the scheduled date and time been set correctly?
    publish_date_time = @experiment.message_distribution_start_date
    messages.each do |message|
      expected_scheduled_date_time = ActiveSupport::TimeZone.new("America/Los_Angeles").local(publish_date_time.year, publish_date_time.month, publish_date_time.day, 12, 30, 0)
      expect(message.scheduled_date_time).to eq(expected_scheduled_date_time)
      publish_date_time += 1.day
    end

    # Is the image selected for each message taken from the image pool for the corresponding message template?
    messages.each do |message|
      expect(message.message_template.image_pool.include?(message.image.id)).to be true
    end

    # Is one hashtag selected for each message where the message template has a list of hashtags?
    messages.each do |message|
      if !message.message_template.hashtags.nil? && message.message_template.hashtags.length > 0
        expect(message.message_template.hashtags.any? {|hashtag| message.content.include?(hashtag)}).to be true 
      end
    end
    
    # Was a Click Meter tracking link created for each message?
    expect(ClickMeterClient).to have_received(:create_click_meter_tracking_link).exactly(expected_generated_message_count).times.with(@experiment, an_instance_of(Message), @experiment.click_meter_group_id, @experiment.click_meter_domain_id)
    messages.each do |message|
      expect(message.click_meter_tracking_link).not_to be_nil
      # These next 4 lines are really only useful to ensure that on development machines we are getting back fake ClickMeter links.
      expect(message.click_meter_tracking_link.click_meter_id).to eq(message.id.to_s)
      expect(message.click_meter_tracking_link.click_meter_uri).to eq("/datapoints/#{message.id.to_s}")
      expect(message.click_meter_tracking_link.tracking_url).to eq("http://tracking-url.com")
      expect(message.click_meter_tracking_link.destination_url).to eq("http://destination-url.com")
      # Was the tracking URL (code) used in place of the {url} variable?
      expect(message.content.index(message.click_meter_tracking_link.tracking_url)).not_to be nil
    end
  end

  it 'creates a set of messages given five message templates, 3 social networks, 2 mediums, images for all messages, 3 cycles, 5 messages per network per day (random hashtags)' do
    message_generation_parameter_set = MessageGenerationParameterSet.new do |m|
      m.social_network_choices = [:facebook, :instagram, :twitter]
      m.medium_choices = ['ad', 'organic']
      m.image_present_choices = :all_messages
      m.number_of_cycles = 3
      m.number_of_messages_per_social_network = 5
    end
    # In order to test that the same hashtags are used, set every template to have a set of allowed hashtags
    @message_templates.each do |message_template|
      random_hashtags = ['#hashtag1,#hashtag2,#hashtag3','#hashtag1,#hashtag4,#hashtag5','#hashtag6,#hashtag7,#hashtag8']
      message_template.hashtags = random_hashtags.sample
      message_template.save
    end
    @experiment.message_generation_parameter_set = message_generation_parameter_set
    @experiment.facebook_posting_times = "12:30 AM,08:30 AM,2:30 PM,3:30 PM,12:30 PM"
    @experiment.twitter_posting_times = "12:40 AM,08:40 AM,2:40 PM,3:40 PM,12:40 PM"
    @experiment.instagram_posting_times = "12:50 AM,08:50 AM,2:50 PM,3:50 PM,12:50 PM"
    @experiment.save
    expected_generated_message_count = message_generation_parameter_set.expected_generated_message_count(MessageTemplate.count)
    # Because this test depends on the randomness of shuffle, in order to make sure this test always passes, we are reurning a determinstic set of values for shuffle.
    # shuffle is called 15 times
    permutations = @message_templates.permutation.to_a
    allow_any_instance_of(Array).to receive(:shuffle).and_return(*permutations[0..14])

    @message_factory.create(@experiment)
    
    messages = Message.all.order('created_at ASC')
    # Was the generation of instagram organic messages skipped?
    expect(messages.any? { |message| message.platform == :instagram && message.medium == :organic }).to be false
    # Have the correct number of messages been generated?
    expect(messages.count).to eq(expected_generated_message_count)
    # Was every message template used in every cycle (3)?
    # Basically each message template should have been used 3 * 5 times (number_of_cycles * (platform count * medium count - 1)); -1 accounts for us not generating instagram organic messages
    messages_grouped_by_message_template = messages.group_by { |message| message.message_template.id }
    messages_grouped_by_message_template.each{ |message_template_id, messages_using_message_template| expect(messages_using_message_template.count).to eq(15) }
    # Are the message templates with their platform and medium distributed equally?
    messages_grouped_by_message_template_platform_and_medium = messages.group_by { |message| message.message_template.id.to_s + message.platform.to_s + message.medium.to_s }
    expect_equal_distribution(messages_grouped_by_message_template_platform_and_medium)
    # Are the message templates shuffled each cycle?
    facebook_organic_messages = messages.select { |message| message.platform == :facebook && message.medium == :organic }
    sliced_facebook_organic_messages = facebook_organic_messages.each_slice(5).to_a
    expect(sliced_facebook_organic_messages[0].map(&:message_template).map(&:id)).not_to eq(sliced_facebook_organic_messages[1].map(&:message_template).map(&:id))
    expect(sliced_facebook_organic_messages[0].map(&:message_template).map(&:id)).not_to eq(sliced_facebook_organic_messages[2].map(&:message_template).map(&:id))
    expect(sliced_facebook_organic_messages[1].map(&:message_template).map(&:id)).not_to eq(sliced_facebook_organic_messages[2].map(&:message_template).map(&:id))
    # Was every message scheduled with some date and time?
    messages.each { |message| expect(message.scheduled_date_time).not_to be_nil }
    messages_grouped_by_scheduled_send_date = messages.group_by{ |message| message.scheduled_date_time.to_date }
    # Was the experiment run for 3 days (With 5 message templates and 5 messages sent out every day, each cycle should have taken one day. We have 3 cycles, to the experiment should have taken a total of 3 days to run.)
    expect(messages_grouped_by_scheduled_send_date.keys.length).to eq(3)
    # Are the correct number of messages scheduled to go out on each day? 
    # total = number of social networks * number of mediums * number of messages per day per social network - number of messages per day per social network (to account for no instagram organic messages)
    number_of_messages_scheduled_per_day = 3 * 2 * 5 - 5
    messages_grouped_by_scheduled_send_date.each { |scheduled_send_date, messages_by_send_date| expect(messages_by_send_date.length).to eq(number_of_messages_scheduled_per_day) }
    # Were the messages scheduled at the right times?
    # 12:30 AM,08:30 AM,2:30 PM,3:30 PM,12:30 PM
    organic_facebook_messages_on_first_day = messages_grouped_by_scheduled_send_date[messages_grouped_by_scheduled_send_date.keys[0]].select{ |message| message.platform == :facebook && message.medium == :ad }
    publish_date_time = @experiment.message_distribution_start_date
    expected_scheduled_date_time = ActiveSupport::TimeZone.new("America/Los_Angeles").local(publish_date_time.year, publish_date_time.month, publish_date_time.day, 0, 30, 0)
    expect(organic_facebook_messages_on_first_day[0].scheduled_date_time).to eq(expected_scheduled_date_time)
    expected_scheduled_date_time = ActiveSupport::TimeZone.new("America/Los_Angeles").local(publish_date_time.year, publish_date_time.month, publish_date_time.day, 8, 30, 0)
    expect(organic_facebook_messages_on_first_day[1].scheduled_date_time).to eq(expected_scheduled_date_time)
    expected_scheduled_date_time = ActiveSupport::TimeZone.new("America/Los_Angeles").local(publish_date_time.year, publish_date_time.month, publish_date_time.day, 14, 30, 0)
    expect(organic_facebook_messages_on_first_day[2].scheduled_date_time).to eq(expected_scheduled_date_time)
    expected_scheduled_date_time = ActiveSupport::TimeZone.new("America/Los_Angeles").local(publish_date_time.year, publish_date_time.month, publish_date_time.day, 15, 30, 0)
    expect(organic_facebook_messages_on_first_day[3].scheduled_date_time).to eq(expected_scheduled_date_time)
    expected_scheduled_date_time = ActiveSupport::TimeZone.new("America/Los_Angeles").local(publish_date_time.year, publish_date_time.month, publish_date_time.day, 12, 30, 0)
    expect(organic_facebook_messages_on_first_day[4].scheduled_date_time).to eq(expected_scheduled_date_time)
    # Were the same images used across all platforms and mediums for the very first message_template used?
    messages_created_from_first_message_template_for_first_cycle = messages.select{ |message| message.message_template == @message_templates[0] }[0..4]
    messages_created_from_first_message_template_for_first_cycle[1..4].each do |message|
      expect(messages_created_from_first_message_template_for_first_cycle[0].image).to eq(message.image)
    end
    # Was the same hashtag used across all platforms and mediums for the very first message template used?
    %w(#hashtag1 #hashtag2 #hashtag3 #hashtag4 #hashtag5 #hashtag6 #hashtag7 #hashtag8).each do |hashtag|
      if !messages_created_from_first_message_template_for_first_cycle[0].content.index(hashtag).nil?
        messages_created_from_first_message_template_for_first_cycle[1..4].each do |message|
          expect(messages_created_from_first_message_template_for_first_cycle[0].content.index(hashtag)).to eq(message.content.index(hashtag))
        end
      end
    end
    
    # Does every message have a suitable social media profile selected?
    messages.each do |message|
      expect(message.social_media_profile).to eq(@suitable_social_media_profiles[1])
    end
    # Does every message have a promoted_website_url?
    expect((messages.select{ |message| message.promoted_website_url.nil? }).count).to eq(0)
    # Were the pusher events triggered?
    expect(@pusher_channel).to have_received(:trigger).exactly(expected_generated_message_count * 2).times.with('progress', {:value => an_instance_of(Fixnum), :total => expected_generated_message_count, :event => 'Message generated'})
    # Was the message generation throttled (limit of 10 req/sec for Click Meter)
    expect(@message_factory).to have_received(:throttle).with(9).exactly(expected_generated_message_count * 2).times

    # # Has the scheduled date and time been set correctly?
    # TODO: Not sure how I can test this efficiently.

    # Is the image selected for each message taken from the image pool for the corresponding message template?
    messages.all.each do |message|
      expect(message.message_template.image_pool.include?(message.image.id)).to be true
    end
    
    # Is one hashtag selected for each message where the message template has a list of hashtags?
    messages.each do |message|
      if !message.message_template.hashtags.nil? && message.message_template.hashtags.length > 0
        expect(message.message_template.hashtags.any? {|hashtag| message.content.include?(hashtag)}).to be true 
      end
    end
  end

  it 'recreates the messages each time' do
    @experiment.facebook_posting_times = "12:30 PM"
    @experiment.save
    message_generation_parameter_set = MessageGenerationParameterSet.new do |m|
      m.social_network_choices = [:facebook]
      m.medium_choices = ['ad']
      m.image_present_choices = :no_messages
      m.number_of_cycles = 1
      m.number_of_messages_per_social_network = 1
    end
    @experiment.message_generation_parameter_set = message_generation_parameter_set
    expected_generated_message_count = message_generation_parameter_set.expected_generated_message_count(MessageTemplate.count)

    @message_factory.create(@experiment)
    @message_factory.create(@experiment)
    
    messages = Message.all
    expect(messages.count).to eq(expected_generated_message_count)
  end

  def expect_equal_distribution(grouped_messages)
    keys = grouped_messages.keys
    (0...(keys.count - 1)).each do |index|
      expect(grouped_messages[keys[index]].length == grouped_messages[keys[index + 1]].length)
    end
  end
  
  it 'can throttle an action' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
    allow(Kernel).to receive(:sleep)
    
    @message_factory.throttle(10)
    
    expect(Kernel).to have_received(:sleep).with(0.1)
  end
  
  it 'throttles an action (on development environments)' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
    allow(Kernel).to receive(:sleep)
    
    @message_factory.throttle(10)
    
    expect(Kernel).to have_received(:sleep).with(0.1)
  end

  it 'ignores throttling (on test environments)' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('test'))
    allow(Kernel).to receive(:sleep)
    
    @message_factory.throttle(10)
    
    expect(Kernel).not_to have_received(:sleep).with(0.1)
  end
end
