require "rails_helper"

RSpec.describe GetAnalyticsFromClickMeterJob, type: :job do
  include ActiveJob::TestHelper

  before do
    ActiveJob::Base.queue_adapter = :test
    allow(ClickMeterClient).to receive(:get_clicks)
    allow(BufferClient).to receive(:get_update)
    allow(Throttler).to receive(:throttle)
    experiment = create(:experiment)
    @messages = create_list(:message, 6, message_generating: experiment)
    (0..5).each do |index|
      @messages[index].publish_status = :published_to_buffer
    end
    @messages.each{ |msg| msg.save }
  end

  it 'queues the job' do
    expect { GetAnalyticsFromClickMeterJob.perform_later(@experiment) }.to change(ActiveJob::Base.queue_adapter.enqueued_jobs, :size).by(1)
  end

  it 'queues the job in the default queue' do
    expect(GetAnalyticsFromClickMeterJob.new.queue_name).to eq('default')
  end

  it 'executes perform only on messages that have a buffer_update' do
    (0..5).each do |index|
      expect(ClickMeterClient).to receive(:get_clicks).with(@experiment, @messages[index].click_meter_tracking_link)
    end

    expect(ClickMeterClient).not_to receive(:get_clicks).with(@experiment, @messages[5].click_meter_tracking_link)

    perform_enqueued_jobs { GetAnalyticsFromClickMeterJob.perform_later(@experiment) }
  end

  it 'throttles the requests to 10 per second per the clickmeter api documentation' do
    (0..4).each do |index|
      expect(Throttler).to receive(:throttle).with(10)
    end

    perform_enqueued_jobs { GetAnalyticsFromClickMeterJob.perform_later(@experiment) }
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end
end
