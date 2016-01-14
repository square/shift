require 'integration_helper'
require 'shared_setup'

RSpec.describe CommentsController, type: :controller do
  include_context "shared setup"

  let(:profile) { {"developer" => {:photo => "pic.img"}} }
  let(:profile_client) { instance_double(Profile) }

  before(:each) do
    login
    allow(Profile).to receive(:new).and_return(profile_client)
    allow(profile_client).to receive(:primary_photo).and_return("pic.img")
  end

  def valid_comment_payload(extra = {})
    {
      :author       => 'mfinch',
      :comment      => 'this is a comment',
      :migration_id => '1',
    }.merge(extra).with_indifferent_access
  end

  describe 'POST #create' do
    context 'with valid attributes' do
      before :each do
        # migration is used in the comment mailer
        @migration = FactoryGirl.create(:pending_migration)
      end

      it 'creates a new comment' do
        expect{
          post :create, valid_comment_payload({migration_id: @migration.id})
        }.to change(Comment, :count).by(1)
      end

      it 'returns nothing' do
        post :create, valid_comment_payload({migration_id: @migration.id})
        expect(response).to have_http_status(200)
      end
    end

    context 'with invalid attributes' do
      it 'does not save a new comment' do
        expect{
          post :create, valid_comment_payload(author: nil)
        }.to_not change(Comment, :count)
        expect(response).to have_http_status(400)
      end
    end
  end
end
