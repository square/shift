require 'integration_helper'

RSpec.describe ShiftFileController, type: :controller do
  describe "GET #show"
    before (:each) do
      login
      @shift_file = FactoryGirl.create(:shift_file, migration_id: 123,
        file_type: 1, contents: "test content")
    end
    it "returns 200 status code when file is found" do
      get :show, migration_id: 123, file_type: 1
      expect(response).to have_http_status(200)
    end

    it "returns 404 status code when file is not found" do
      get :show, migration_id: 12345, file_type: 1
      expect(response).to have_http_status(404)
    end

    it "returns file contents" do
      get :show, migration_id: 123, file_type: 1
      expect(response.body).to eq("test content")
    end
end