Description
------
shift-runner is a Go service that runs schema migrations on databases by invoking pt-online-schema-change (pt-osc). It continually polls the api exposed by the shift rails app for new jobs (migrations) to run.

#### Important Concepts
A migration changes states as it moves through its lifecycle. Whenever a migration needs to be processed by shift-runner, it gets a field called `staged` set to `true`. The shift api only ever exposes migrations that are staged. The first thing that the runner does when it consumes a job is "unstage" it (set staged to false) so that no other runner will pick it up. Then, based on the status of the migration (and a few other things), it performs a certain action.

These are the different migration states that shift-runner processes. The descriptions are what the runner does after it picks up each job type
* **preparing**: connect to the migration's cluster and collect some basic table stats. Also perform a dry run of pt-osc to make sure the ddl statement is valid. If there are no errors, move the migration into the "awaiting approval" state
* **running migration**: using the ddl statement in the migration, run pt-osc for real against the migration's cluster. Use a flag in pt-osc to tell it to exit after all the rows have been copied, but before the tables have been renamed. Post frequent status updates (copy % completed) back to the shift api while pt-osc is running. After pt-osc completes, if there are no errors, move the migration into the "awaiting rename" state
* **renaming migration**: rename the temporary table created by pt-osc with the original table. Instead of dropping the original table, rename it into a **pending drops** database (a pending drops database is essentially a trash can db. tables here should be dropped a few days or a week after a migration finishes, after it is certain they aren't needed anymore). Perform the final insert of the migration. If there are no errors, move the migration into the "completed" state

\* _Note_: the above states apply to ALTER TABLE ddl statements. CREATE/DROP TABLE ddl statements are similar, except they don't invoke pt-osc and they go straight from the "running migration" state into the "completed" state

This is a sample payload that the shift api will expose (just one migration here)
```json
[{
  "id":43,
  "database":"appname_staging",
  "table":"employees",
  "ddl_statement":"alter table employees add column salary int(11)",
  "final_insert":"",
  "staged":true,
  "status":0,
  "host":"localhost",
  "port":3306,
  "runtype":1,
  "run_host":null,
  "mode":0,
  "action":2,
  "custom_options": "{\"max_threads_running\": \"200\", \"max_replication_lag\":\"1\"}"
}]
```

Installation
------
#### Quick Start
```
# get it and install dependencies
go get -v github.com/square/shift/...

cd $GOPATH/src/github.com/square/shift/runner
# Edit config/* as necessary

# start the runner
go run main.go -logtostderr
```

#### Configuration
Here are the configuration files that you will probably want to update (although the defaults should be sensible)
* `config/my_${environment}.cnf`: the defaults file that will be passed to pt-osc. You must supply a set of credentials in here that pt-osc can use to connect to every cluster you have and alter tables
* `config/${environment}-config.yaml`: there is one config for each environment (development, staging, and production)
  * `mysql_user`, `mysql_password`, `mysql_cert`, `mysql_key`, `mysql_rootCA`: a set of database credentials that has read-write access to every cluster you have. This user will get stats from information_schema, create/drop/rename tables, and perform final inserts. You may want to just make this the same credentials as pt-osc uses
  * `mysql_defaults_file`: the path to a mysql cnf file that is described above
  * `rest_api`: the url of the shift api (will be http://${shift_url}/api/v1/
  * `rest_cert`: if applicable, the cert needed to connect to the shift api
  * `rest_key`: if applicable, the key needed to connect to the shift api
  * `log_dir`: the directory where the pt-osc state and output for all migrations will be stored
  * `pt_osc_path`: the path to the patched version of pt-osc
  * `enable_trash`: if true, the runner will duplicate the original table into `pending_drops_db` with a timestamp prefix name after non-shortrun alter/drop table.
  * `pending_drops_db`: the name of the pending drops (trash can) db. If this isn't specified, old tables won't be renamed out of their original database
  * `log_sync_interval`: interval in seconds for uploading pt-osc log files to the ui
  * `state_sync_interval`: same as above, but for pt-osc state files
  * `stop_file_path`: path to a file, which if it exists, will send the runner into a stopped state where it will no longer process migrations.
  * `host_override`: if you specify a host here, it will override the host for all migrations exposed by the shift api. This is useful for a staging environment when you want to make sure you don't accidentally run migrations on live dbs
  * `port_override`: same as above, but for a port
  * `database_override`: same as above, but for a database

#### Deployment
`go build`, deploy the resulting binary to your staging/production machines, and run it.

To get the runner to run in production or staging mode, set the following ENV variable. Doing so will cause the runner to read from the corresponding configs in `shift/runner/config/`
```
export ENVIRONMENT="production"
# OR
export ENVIRONMENT="staging"
```

Development
------
Run the tests
```
cd pkg
go test ./...
```

Package dependencies are managed by [godep](https://github.com/tools/godep)

## License

Copyright (c) 2016 Square Inc. Distributed under the Apache 2.0 License.
See LICENSE file for further details.
