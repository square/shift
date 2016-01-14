class Cluster < ActiveRecord::Base
  has_many :migrations, primary_key: "name", foreign_key: "cluster_name"
  has_many :owners, primary_key: "name", foreign_key: "cluster_name"
end
