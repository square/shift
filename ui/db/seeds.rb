# seed the statuses table
Statuses.create(status: 0, description: 'preparing migration', label: 'warning')
Statuses.create(status: 1, description: 'awaiting approval', action: 'approve', label: 'info')
Statuses.create(status: 2, description: 'awaiting start', action: 'start', label: 'info')
Statuses.create(status: 3, description: 'running migration', action: 'pause', label: 'warning')
Statuses.create(status: 4, description: 'awaiting rename', action: 'rename', label: 'info')
Statuses.create(status: 5, description: 'rename in progress', label: 'warning')
Statuses.create(status: 6, description: 'awaiting drop old', action: 'drop old', label: 'info')
Statuses.create(status: 7, description: 'drop old in progress', label: 'warning')
Statuses.create(status: 8, description: 'completed', label: 'success')
Statuses.create(status: 9, description: 'canceled', label: 'danger')
Statuses.create(status: 10, description: 'failed', label: 'danger')
Statuses.create(status: 11, description: 'pausing', label: 'warning')
Statuses.create(status: 12, description: 'paused', action: 'resume', label: 'info')
Statuses.create(status: 13, description: 'error', action: 'retry', label: 'danger')
Statuses.create(status: 14, description: 'enqueued', action: 'dequeue', label: 'purple')

# create a fake cluster for development
if Rails.env == "development"
  Cluster.create(name: "default-cluster-001", app: "local-app", rw_host: "localhost",
                 port: 3306, admin_review_required: false, is_staging: true)
end
