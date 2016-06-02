require 'integration_helper'

RSpec.describe AdminController, type: :controller do

  before (:each) do
    allow(Time).to receive(:now).and_return(Time.new(2015, 6, 1, 2, 2, 2))
    allow(Date).to receive(:today).and_return(Date.new(2015, 6, 1))
    login(admin: true)
  end

  it "returns 401 if user not admin" do
    login(admin: false)
    get :index
    expect(response).to have_http_status(401)
  end

  describe "GET #index" do
    it "returns a 200 status code" do
      get :index
      expect(response).to be_success
      expect(response).to have_http_status(200)
    end

    it "renders the :index view" do
      get :index
      expect(response).to render_template(:index)
    end
  end

  describe "GET #refresh_filed_chart" do
    it "returns a 200 status code" do
      get :refresh_filed_chart
      expect(response).to have_http_status(200)
    end

    context "data grouped by days" do #TODO: check formatted dates?
      before (:each) do
        FactoryGirl.create(:completed_migration,
          created_at: 3.days.ago,
          approved_at: 20.hours.ago,
          completed_at: 1.days.ago)
        FactoryGirl.create(:pending_migration,
          created_at: 6.days.ago)
      end

      it "returns the correct number of categories" do
        get :refresh_filed_chart, weeks: 1
        expect(json["categories"].length).to eq(7)
      end

      it "returns correct migrations_filed" do
        get :refresh_filed_chart, weeks: 1
        expect(json["migrations_filed"]).to eq([1,0,0,1,0,0,0])
      end

      it "returns correct migrations_completed" do
        get :refresh_filed_chart, weeks: 1
        expect(json["migrations_completed"]).to eq([0,0,0,0,0,1,0])
      end
    end

    context "data grouped by weeks" do
      before (:each) do
        FactoryGirl.create(:completed_migration,
          created_at: 4.weeks.ago.beginning_of_week(:sunday),
          approved_at: 3.weeks.ago.beginning_of_week(:sunday) + 2.days,
          completed_at: Time.now)
        FactoryGirl.create(:pending_migration,
          created_at: Time.now.beginning_of_week(:sunday) - 4.weeks)
      end

      it "returns the correct number of categories" do
        get :refresh_filed_chart, weeks: 12
        expect(json["categories"].length).to eq(12)
      end

      it "returns correct migrations_filed" do
        get :refresh_filed_chart, weeks: 12
        expect(json["migrations_filed"]).to eq([0,0,0,0,0,0,0,2,0,0,0,0])
      end

      it "returns correct migrations_completed" do
        get :refresh_filed_chart, weeks: 12
        expect(json["migrations_completed"]).to eq([0,0,0,0,0,0,0,0,0,0,0,1])
      end
    end

    context "all time data grouped by months" do
      before (:each) do
        FactoryGirl.create(:completed_migration,
          created_at: 8.months.ago,
          approved_at: 6.months.ago,
          completed_at: 3.months.ago)
        FactoryGirl.create(:pending_migration,
          created_at: Time.now)
      end

      it "returns the correct number of categories" do
        get :refresh_filed_chart, weeks: 0
        expect(json["categories"].length).to eq(9)
      end

      it "returns the correct migrations_filed" do
        get :refresh_filed_chart, weeks: 0
        expect(json["migrations_filed"]).to eq([1,0,0,0,0,0,0,0,1])
      end

      it "returns the correct migrations_completed" do
        get :refresh_filed_chart, weeks: 0
        expect(json["migrations_completed"]).to eq([0,0,0,0,0,1,0,0,0])
      end
    end
  end

  describe "GET #refresh_approval_time_chart" do
    it "returns a 200 status code" do
      get :refresh_approval_time_chart
      expect(response).to have_http_status(200)
    end

    context "data grouped by days" do
      before (:each) do
        FactoryGirl.create(:completed_migration,
          created_at: 1.days.ago.beginning_of_day,
          approved_at: 1.days.ago.beginning_of_day + 3.hours,
          completed_at: Time.now)
        FactoryGirl.create(:start_migration,
          created_at: 1.days.ago.beginning_of_day + 1.hours,
          approved_at: Time.now.beginning_of_day)
        FactoryGirl.create(:start_migration,
          created_at: 1.days.ago.beginning_of_day + 5.hours,
          approved_at: 1.days.ago.beginning_of_day + 5.hours + 20.minutes)
      end

      it "returns the correct number of categories" do
        get :refresh_approval_time_chart, weeks: 1
        expect(json["categories"].length).to eq(7)
      end

      it "returns the correct average_approval_times" do
        get :refresh_approval_time_chart, weeks: 1
        expect(json["average_approval_times"]).to eq([nil,nil,nil,nil,nil,8.8,nil])
      end
    end

    context "data grouped by weeks" do
      before (:each) do
        FactoryGirl.create(:completed_migration,
          created_at: 9.weeks.ago.beginning_of_week(:sunday) + 2.days,
          approved_at: 9.weeks.ago.beginning_of_week(:sunday) + 2.days + 2.hours,
          completed_at: Time.now)
        FactoryGirl.create(:start_migration,
          created_at: 8.weeks.ago.beginning_of_week(:sunday) + 5.days,
          approved_at: 8.weeks.ago.beginning_of_week(:sunday) + 6.days + 3.hours)
      end

      it "returns the correct number of categories" do
        get :refresh_approval_time_chart, weeks: 12
        expect(json["categories"].length).to eq(12)
      end

      it "returns the correct average_approval_times" do
        get :refresh_approval_time_chart, weeks: 12
        expect(json["average_approval_times"]).to eq([nil,nil,2,27,nil,nil,nil,nil,nil,nil,nil,nil])
      end
    end

    context "all time data grouped by months" do
      before (:each) do
        FactoryGirl.create(:completed_migration,
          created_at: 3.months.ago.beginning_of_month,
          approved_at: 3.months.ago.beginning_of_month + 7.days,
          completed_at: Time.now)
        FactoryGirl.create(:start_migration,
          created_at: 5.months.ago.beginning_of_month,
          approved_at: 5.months.ago.beginning_of_month + 1000.hours)
      end

      it "returns the correct number of categories" do
        get :refresh_approval_time_chart, weeks: 0
        expect(json["categories"].length).to eq(6)
      end

      it "returns the correct average_approval_times" do
        get :refresh_approval_time_chart, weeks: 0
        expect(json["average_approval_times"]).to eq([1000,nil,7*24,nil,nil,nil])
      end
    end
  end

  describe "GET #refresh_cluster_metrics" do
    before (:each) do
      @cluster = FactoryGirl.create(:cluster)
        FactoryGirl.create(:completed_migration,
          cluster_name: @cluster.name,
          database: :testdb1,
          started_at: 1.days.ago.beginning_of_day,
          completed_at: 1.days.ago.beginning_of_day + 3.hours,
          ddl_statement: "ALTER TABLE test1 MODIFY test_id bigint DEFAULT NULL")
        FactoryGirl.create(:completed_migration,
          cluster_name: @cluster.name,
          database: :testdb1,
          started_at: 1.days.ago.beginning_of_day + 1.hours,
          completed_at: Time.now.beginning_of_day,
          ddl_statement: "ALTER TABLE test2 MODIFY test_id bigint DEFAULT NULL")
        FactoryGirl.create(:completed_migration,
          cluster_name: @cluster.name,
          database: :testdb1,
          started_at: 1.days.ago.beginning_of_day + 2.hours,
          completed_at: Time.now.beginning_of_day,
          ddl_statement: "ALTER TABLE test2 MODIFY test_id bigint DEFAULT NULL")
        FactoryGirl.create(:completed_migration,
          cluster_name: @cluster.name,
          database: :testdb2,
          started_at: 1.days.ago.beginning_of_day + 5.hours,
          completed_at: 1.days.ago.beginning_of_day + 5.hours + 15.minutes,
          ddl_statement: "ALTER TABLE test3 MODIFY blah bigint DEFAULT NULL")
    end

    it "returns the correct data" do
      get :refresh_cluster_metrics, cluster: @cluster.name
      expect(json["testdb1"]["test1"]).to eq({
        "times_altered" => 1,
        "average_alter_time" => 3.0 * 3600,
        "max_alter_time" => 3.0 * 3600,
        "min_alter_time" => 3.0 * 3600})
      expect(json["testdb1"]["test2"]).to eq({
        "times_altered" => 2,
        "average_alter_time" => 22.5 * 3600,
        "max_alter_time" => 23.0 * 3600,
        "min_alter_time" => 22.0 * 3600})
      expect(json["testdb2"]["test3"]).to eq({
        "times_altered" => 1,
        "average_alter_time" => 0.25 * 3600,
        "max_alter_time" => 0.25 * 3600,
        "min_alter_time" => 0.25 * 3600})
    end
  end
end