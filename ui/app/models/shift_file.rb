class ShiftFile < ActiveRecord::Base
  belongs_to :migration
  before_save :compress_contents
  after_initialize :decompress_contents

  FILE_TYPES = {
    :log            => 0,
    :state          => 1,
    :appendable     => [0],
    :writable       => [1],
  }.with_indifferent_access

  def self.file_types
    FILE_TYPES
  end

  private

  def compress_contents
    unless self.contents == nil
      self.contents = ActiveSupport::Gzip.compress(contents)
    end
  end

  def decompress_contents
    unless self.contents == nil
      self.contents = ActiveSupport::Gzip.decompress(self.contents)
    end
  end
end