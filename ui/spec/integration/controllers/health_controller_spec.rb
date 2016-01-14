require 'integration_helper'

RSpec.describe HealthController, type: :controller do
  describe '#status' do
    subject do
      get(:status)
      response
    end

    it 'responds with json status' do
      body = subject.body
      json = JSON.parse(body)
      expect(json['status']).to eq('ok')
    end

    context 'the database is having issues' do
      before do
        allow(ActiveRecord::Base.connection)
          .to receive(:select_all).and_raise(StandardError)
      end

      it 'responds with 500' do
        body = subject.body
        json = JSON.parse(body)
        expect(json['status']).to eq('critical')
        expect(json['message']).to eq('StandardError')
        expect(response).to be_error
      end
    end

    context 'the disabled file exists' do
      let(:disable_file_path) { described_class::DISABLE_FILE_PATH }

      before do
        FileUtils.mkdir_p(File.dirname(disable_file_path))
        FileUtils.touch(disable_file_path)
      end

      after { FileUtils.rm(disable_file_path) }

      it 'responds with 500' do
        body = subject.body
        json = JSON.parse(body)
        expect(json['status']).to eq('critical')
        expect(json['message']).to eq('Server is Disabled')
        expect(response).to be_error
      end
    end
  end
end
