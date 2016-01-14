require 'integration_helper'

RSpec.describe ErrorsController, type: :controller do
  before(:each) do
    login
  end

  describe 'GET #error404' do
    it 'renders a custom page' do
      get :error404
      expect(response).to render_template(:error404)
      expect(response.status).to eq(404)
    end
  end
end
