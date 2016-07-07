Description
------
The shift-ui is a rails app (just called "shift") that makes it easy to file, track, and run online database migrations. From the ui you can create requests to alter the schema of your tables (ex: add a column). After passing sanity checks, requests must be approved by an admin and then they can be run. Migrations update the ui with their status while they run so they can be tracked in real time, and you can always pause/resume/cancel/retry them with the click of a button.

Besides providing a ui, shift also exposes migrations via a json api. The shift-runner queries the api to pick up jobs (migrations) and run them.

#### Important Concepts
* **migration**: a migration is a request to alter the schema of a table. When a user files a migration, they must submit a cluster name, a database name, a valid ddl statement, a link to a corresponding pull request, and (optionally) a final insert
* **final insert**: an optional insert statement that can be run at the end of a migration (ex: "insert into schema_migrations...")
* **cluster**: a cluster describes a dataset. Each cluster has, among other things, a name, a host and port where the dataset can be reached, an application that it belongs to, and a list of owners. Migrations are run against clusters, not against databases directly. By default we only allow one migration to be running on a cluster at a time
* **cluster owner**: users who are considered to be owners of a cluster. You must be a cluster owner (or an admin) to run migrations for that cluster
* **meta request**: a collection of migrations that share a common ddl statement and final insert. Useful for sharded datasets. Meta requests are nice because they are quick to file, and they can be run in bulk. All migrations in a meta request must be for clusters that belong to the same app
* **migration flow**: the sequence of states in a migrations lifecycle. The flow for a request can always be seen at the bottom of the page when viewing the migration. Here's the what the flow looks like for an "alter table" migration
<br><br>
<img src="/ui/screenshots/flow.png">
<br><br>
When a migration is in an orange state it means that it is exposed by the shift api and the shift-runner will pick it up for processing. When a migration is in a blue state it means that a human user needs to perform an action.

Installation
------
#### Quick Start
```
# clone the repo and install gems
git clone https://github.com/square/shift.git
cd shift/ui
gem install bundler
bundle install

# Edit config/database.yml as necessary

# create the database and seed it with some data
bundle exec rake db:setup

# start the rails server
bundle exec rails server

# navigate to 127.0.0.1:3000 in your browser
```

#### Configuration
Here are the configuration files/variables that you will probably want to update (although the defaults should be sensible)
* `config/database.yml`: this is where you setup the connection to the database that this rails app will use (see [this guide](http://edgeguides.rubyonrails.org/configuring.html#configuring-a-database) for more info)
* `config/environments/*`: there is one config for each environment (test, development, staging, and production)
    * `config.x.mysql_helper.db_config`: here you must supply a set of database credentials that has read-only access to all of your clusters. When migrations are filed, shift connects to the cluster they are filed against to verify that the ddl is valid
    * `config.x.mysql_helper.db_blacklist`: this is global a list of databases that schema changes can not be run on. i.e., you won't be able to file any migrations against these databases on any cluster
    * `config.x.mailer.default_from`: a default address to receive email notifications from
    * `config.x.mailer.default_to`: a default local name to send email notifications to
    * `config.x.mailer.default_to_domain`: a default domain to send email notifications to
    * `config.x.ptosc.log_dir`: the path on the filesystem where the shift-runner logs to. If shift and shift-runner run on the same host and shift has read access to the runner's logs, they can be served up in the ui. This is just a nice-to-have
* `ENV['SECRET_KEY_BASE']`: your rails secret token

#### Adding Clusters and Owners
Clusters and owners are both stored in the shift database. After you have run `db:setup`, connect to the db and inspect the `clusters` and `owners` tables. For purposes of example, a cluster that points to localhost gets seeded during db:setup. When you insert a cluster, this will cause it to show up in the UI as an option when you go to file a new migration. When a migration runs on the cluster, it will connect to the `rw_host` and `port` specified by you in the table.

As of now, the only way to add new clusters and owners is to connect directly to the shift database and insert records. Ex:
```
mysql shift_development
> insert into clusters (`name`, `app`, `rw_host`, `port`, `admin_review_required`, `is_staging`) values ('cluster-name', 'clusters-app', 'hostname', 'port', true, false);
# this will create a cluster called "cluster-name" that will show up in the production section of the cluster dropdown menu (since "is_staging" is false) when you go to
# create a migration. Migrations filed against this cluster will run on "hostname" on port "port". Admins will be required to approve migrations against this cluster
# (i.e., even if a user is an owner of the cluster, they won't be able to approve migrations on it).

> insert into owners (`cluster_name`, `username`) values ('cluster-name', 'john');
# this will establish "john" as an owner of the cluster "cluster-name". This will
# give john the ability to run/pause/cancel/etc. any migrations filed against "cluster-name".
# It would also give him the ability to approve migrations filed against "cluster-name" if
# "admin_review_required" was set to false on the cluster.
```

At some point in the future there could be a way to do this from the ui.

#### Services
There is a rufus-scheduler job that runs alongside the rails server. The job runs every 15 seconds and tries to start migrations that are queued up to run. You can find it here `config/initializers/migration_scheduler.rb`

#### Dependencies
Setting these up is entirely optional. If you don't do it, shift will still work fine
* `app/services/notifier.rb`: plug into your notification service
* `app/services/profile.rb`: provide profile pictures for users
* IMGKit: create status images from html. Read the [imgkit docs](https://github.com/csquared/IMGKit#imgkit) for more info on setting this up

#### Deploying
You will probably want to use something like [capistrano](https://github.com/capistrano/capistrano) to deploy to your staging and production environments.

Since the rails server is mainly used for development, you should use a real web server (ex: [Phusion Passenger](https://www.phusionpassenger.com/)) when deployig to your production and staging environments. To run in either of these environments, make sure you set the following ENV variables first
```
export RAILS_ENV="production"
# OR
export RAILS_ENV="staging"

export SECRET_KEY_BASE="some_random_30_char_string"
# check out shift/ui/config/secrets.yml for more info about this
```
Note: both the staging and production configs (`shift/ui/config/environments/{staging,production}.rb`) are setup to run as https. If you're not ready to support that, edit the configs and remove the SSL sections.

If you have to run the development web server, you can set the same ENV variables as above, or you can start the server with
```
bundle exec rails server -e production # or staging
```

Authentication and Authorization
------
#### UI
By default, when you start the server, you will be logged in as an admin user with access to everything. To hook up shift with your own authentication system, you will need to override the `current_user` function in `app/controller/application_controller`.

Authorization is all based on whether or not a user is an admin or cluster owner. Check out `app/policies/migration_policy.rb` to see the authorization policies in place.

#### API
There are no ACLs setup for the api by default. This allows you to get up and running quickly, but it is not safe for a production service. You should setup authentication and authorization for the api in `app/controllers/api_controller.rb`.

Development
------
Run the tests
```
bundle exec rake spec
```

CLI
------
There is a CLI available that allows you to do all the actions that are normally done from the UI, from the command line. Check out the [shift-cli README](https://github.com/square/shift/tree/master/ui/shift-client) for more info.

## License

Copyright (c) 2016 Square Inc. Distributed under the Apache 2.0 License.
See LICENSE file for further details.
