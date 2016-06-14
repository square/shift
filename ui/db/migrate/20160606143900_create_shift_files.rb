class CreateShiftFiles < ActiveRecord::Migration
  def change
    create_table :shift_files do |t|
      t.integer :migration_id
      t.integer :file_type, :limit => 1
      t.datetime :created_at
      t.datetime :updated_at
      t.binary :contents, :limit => 16.megabyte

      t.index [:migration_id, :file_type], unique: true
    end
  end
end
