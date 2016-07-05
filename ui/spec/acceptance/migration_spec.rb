require 'acceptance_helper'
require 'shared_setup'

def get_options(element, with_optgroup)
  find("##{element} #{with_optgroup ? 'optgroup' : ''} option", match: :first)
  page.all("##{element} #{with_optgroup ? 'optgroup' : ''} option")
end

def select_random_option(element, with_optgroup: true)
  # wait until js edits DOM completely, try this repetitively
  # as it is not guaranteed that one time is enough
  50.times do
    break if get_options(element, with_optgroup).length > 1
  end

  options = get_options(element, with_optgroup)
  with_optgroup ? options.sample.text : options.drop(1).sample.text
end

def create_multiple_requests(count)
  (1..count).each do |i|
    click_link "Create Request"
    option = select_random_option('form_new_migration_request_cluster_name')
    select option, from: 'cluster'

    option = select_random_option('form_new_migration_request_database', with_optgroup: false)
    select option, from: 'database'

    fill_in 'DDL statement', with: 'create table t like c'
    fill_in 'pr url', with: 'github.com/pr'

    click_button "Submit Migration"
  end
end

feature 'creating a new migration' do
  include_context "shared setup"
  before(:each) do
    login
    @cluster = FactoryGirl.create(:cluster, :admin_review_required => false)
    FactoryGirl.create(:owner, cluster_name: @cluster.name, username: "user1")
  end

  scenario 'happy path', js: true do
    visit '/'
    expect(page).to have_content("Pending Migrations")

    create_multiple_requests(6)

    expect(page).to have_content("Migration Flow")
    expect(page).to have_content('developer') # Test credentials username

    click_link "All Requests"
    expect(page).to have_content("Pending Migrations")
    expect(page).to have_content("create table t like c")

    click_link "See all"
    expect(page).to have_content("Pending Migrations")

    click_link "< Back to All Migrations"
    expect(current_path).to eq("/")
  end
end
