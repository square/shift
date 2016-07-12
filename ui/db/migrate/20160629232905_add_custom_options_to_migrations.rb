class AddCustomOptionsToMigrations < ActiveRecord::Migration
  def change
    add_column :migrations, :custom_options, :blob
  end
end
