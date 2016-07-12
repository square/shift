class AddCustomOptionsToMetaRequests < ActiveRecord::Migration
  def change
    add_column :meta_requests, :custom_options, :blob
  end
end
