require 'lint_helper'

RSpec.describe "Gemfile" do
  subject { File.read(File.expand_path("../../../Gemfile", __FILE__)) }

  context "funny gemfile URLs that break deploys on CentOS 6.2" do
    %w(git://).each do |url_prefix|
      it "does not contain any #{url_prefix} gem URLs" do
        expect(subject).not_to match(url_prefix)
      end
    end
  end
end
