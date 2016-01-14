class Comment < ActiveRecord::Base
  belongs_to :migration

  include ActiveModel::Validations
  validates_presence_of :author
  validates_presence_of :comment
  validates_presence_of :migration_id
end
