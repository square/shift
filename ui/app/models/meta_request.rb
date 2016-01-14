class MetaRequest < ActiveRecord::Base
  has_many :migrations
  paginates_per 20

  validates_presence_of :ddl_statement
  validates_presence_of :pr_url
  validates_format_of :final_insert, :with => /\A(?i)(INSERT\s+INTO\s+)[^;]+\Z/i, :allow_blank => true
end
