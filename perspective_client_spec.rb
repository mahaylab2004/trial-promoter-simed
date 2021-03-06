require 'rails_helper'
require 'yaml'

RSpec.describe PerspectiveClient do
  before do
    @experiment = build(:experiment)
    secrets = YAML.load_file("#{Rails.root}/spec/secrets/secrets.yml")
    @experiment.set_api_key(:google_perspective, secrets['google_perspective_api_key'])
    @text = "This message is stupid."
  end

  describe "(development only tests)", :development_only_tests => true do 
    it 'returns the score from the Google Perspective API' do
      VCR.use_cassette 'perspective_client/calculate_toxicity_score' do
        @toxicity_score = PerspectiveClient.calculate_toxicity_score(@experiment, @text) 
      end
      expect(@toxicity_score).to eq("0.92")
    end

    it 'returns the score from the Google Perspective API when comment has double quotes within the string' do
      VCR.use_cassette 'perspective_client/calculate_toxicity_score_for_double_quotes' do
        @toxicity_score = PerspectiveClient.calculate_toxicity_score(@experiment, "Wow actually touching on the seriousness of the actual addiction!! Not just \"shaming\" yay!") 
      end
      expect(@toxicity_score).to eq("0.31")
    end

    it 'returns the score from the Google Perspective API when comment has double quotes within the string' do
      VCR.use_cassette 'perspective_client/calculate_toxicity_score_for_double_quotes' do
        @toxicity_score = PerspectiveClient.calculate_toxicity_score(@experiment, "Wow actually touching on the seriousness of the actual addiction!! Not just \"shaming\" yay!") 
      end
      expect(@toxicity_score).to eq("0.31")
    end
  end
end 
   
