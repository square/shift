class Owner < ActiveRecord::Base
  belongs_to :cluster, foreign_key: "cluster_name", primary_key: "name"
end
