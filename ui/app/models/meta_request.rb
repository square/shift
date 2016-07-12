class MetaRequest < ActiveRecord::Base
  has_many :migrations
  paginates_per 20
  before_save :encodeCustomOptions
  after_initialize :decodeCustomOptions
  attr_accessor :max_threads_running, :max_replication_lag, :config_path, :recursion_method

  validates_presence_of :ddl_statement
  validates_presence_of :pr_url
  validates_format_of :final_insert, :with => /\A(?i)(INSERT\s+INTO\s+)[^;]+\Z/i, :allow_blank => true

  private

  def encodeCustomOptions
    self.custom_options = ActiveSupport::JSON.encode(max_threads_running: self.max_threads_running,
                                                     max_replication_lag: self.max_replication_lag,
                                                     config_path: self.config_path,
                                                     recursion_method: self.recursion_method)
  end

  def decodeCustomOptions
    if !self.has_attribute?(:custom_options)
      # prevents MissingAttributeError when doing selects
      return
    end

    if self.custom_options != nil
      decodedOptions = ActiveSupport::JSON.decode(self.custom_options)
      self.max_threads_running = decodedOptions["max_threads_running"]
      self.max_replication_lag = decodedOptions["max_replication_lag"]
      self.config_path = decodedOptions["config_path"]
      self.recursion_method = decodedOptions["recursion_method"]
    end
  end
end
