require 'rails_helper'

RSpec.describe ImagePolicy, type: :policy do
  subject { ImagePolicy.new(user, image) }

  let(:image) { create(:image) }

  context "for a user with no role" do
    let(:user) { create(:user) }

    it { should_not be_permitted_to(:add) }
    it { should_not be_permitted_to(:import) }
    it { should_not be_permitted_to(:check_validity_for_instagram_ads) }
    it { should_not be_permitted_to(:edit_codes) }
  end

  context "for an administrator" do
    let(:user) { create(:administrator) }

    it { should be_permitted_to(:add) }
    it { should be_permitted_to(:import) }
    it { should be_permitted_to(:check_validity_for_instagram_ads) }
    it { should be_permitted_to(:edit_codes) }
  end
end
