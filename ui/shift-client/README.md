Description
------
shift-client is a command-line interface for shift. It interacts with the shift API and can be used to do all of the same actions that can be done from the ui

Installation
------
Run the shift-client executable directly
```
cd shift/ui/shift-client
bundle install
./bin/shift-client --help
```
Or install it directly
```
$ gem install shift-client
$ shift-client --help
```

Usage
------
Running with --help shows you all of the available commands and global options
```
$ shift-client --help
  NAME:

    shift-client

  DESCRIPTION:

    Interact with the shift API from the command-line

  COMMANDS:

    approve migration   Approve a migration
    cancel migration    Cancel a migration
    create migration    Create a migration
    delete migration    Delete a migration
    dequeue migration   Dequeue a migration
    enqueue migration   Enqueue a migration
    get migration       Get a migration
    help                Display global or [command] help documentation
    pause migration     Pause a migration
    rename migration    Rename a migration
    resume migration    Resume a migration
    start migration     Start a migration
    unapprove migration Unapprove a migratio

  GLOBAL OPTIONS:

    --url URL
        The API URL for shift (default: http://localhost:3000)

    --ssl-cert SSL CERT
        An SSL cert for authenticating against the shift api

    --ssl-key SSL KEY
        An SSL key for authenticating against the shift api

    --ssl-ca SSL CA
        An SSL CA cert for authenticating against the shift api

    -h, --help
        Display help documentation

    -v, --version
        Display version information

    -t, --trace
        Display backtrace when an error occurs
```

Running with --help on a specific command shows you the specific options for that command
```
$ shift-client approve migration --help

  NAME:

    approve migration

  SYNOPSIS:

    shift-client approve migration [options]

  DESCRIPTION:

    Approve a migration

  OPTIONS:

    --id ID
        The id of the migration

    --lock-version LOCK VERSION
        The most recent lock version of the migration

    --runtype RUNTYPE
        The type of run to approve (options are: short, long, nocheckalter)

    --approver APPROVER
        The username of the approver

```

## Global Options
Without specifying any global options, shift-cli will try to talk to the shift API at localhost:3000 without SSL. If that's where the shift ui is running, you don't need to pass any global options. If it's running at a different URL, or requires valid SSL certs to access it, you can supply any of the following: `--url`, `--ssl-cert`, `--ssl-key`, and `--ssl-ca`

## Responses
The standard response for most successful commands is a JSON object that looks like the following
```
$ shift-client get migration --id 25
{
  "migration": {
    "id": 25,
    "created_at": "2016-06-07T01:20:10.000Z",
    "updated_at": "2016-06-07T01:21:19.000Z",
    "completed_at": null,
    "requestor": "developer",
    "cluster_name": "default-cluster-001",
    "database": "shift_development",
    "ddl_statement": "alter table migrations add column mfinch int",
    "final_insert": "",
    "pr_url": "github.com/pr",
    "table_rows_start": 25,
    "table_rows_end": null,
    "table_size_start": 16384,
    "table_size_end": null,
    "index_size_start": 16384,
    "index_size_end": null,
    "approved_by": "mfinch",
    "approved_at": "2016-07-02T00:40:29.000Z",
    "work_directory": null,
    "started_at": "2016-07-02T01:08:34.000Z",
    "copy_percentage": null,
    "staged": true,
    "status": 3,
    "error_message": null,
    "run_host": null,
    "lock_version": 7,
    "editable": false,
    "runtype": 1,
    "meta_request_id": null,
    "initial_runtype": 1,
    "auto_run": true,
    "custom_options": "{\"max_threads_running\":200,\"max_replication_lag\":1,\"config_path\":\"\",\"recursion_method\":\"\"}"
  },
  "available_actions": [
    "pause",
    "cancel"
  ]
}
```
As you can see, it contains a dump of the migration, as well as the actions that are available to run on it.

The only other type of response you will get from a successful command is an empty JSON object when you delete a migration
```
$ shift-client delete migration --id 24 --lock-version 7
{
}
```

Commands that run into errors will return JSON objects that look like the following
```
$ shift-client start migration --id 25 --lock-version 8
{
  "status": 400,
  "errors": [
    "Invalid action.",
    "Incorrect lock_version supplied."
  ]
}
```

## Option descriptions
* `--id`: the id of the migration you want to act on. Can get this from the response of a successful `shift-client create migration` command
* `--lock-version`: the most recent lock-version of a migration. This is used so that we know a migration's status hasn't changed without you knowing. Can get this from the response of any successful command
* `--runtype`: the type of run to approve a migration with (options are: short, long, nocheckalter). When you run `shift-client get migration` on a migration that is in the "awaiting_approval" step, the available actions in the JSON response will look something like `["approve_short", "approve_long"]`. That means that when you run `shift-client approve migration`, you must supply either `--runtype short` or `--runtype long`. A short run is one that runs an alter directly on a table. A long run is one that uses pt-osc. A nocheckalter run is one that uses pt-osc with the --nocheck-alter flag.
* `--auto-run`: this option can be passed to `shift-client start migration` and `shift-client resume migration`. When it is used, the migration will automatically rename tables after it is done copying all of its rows (instead of waiting for human interaction). `shift-client enqueue migration` automatically sets this to true
* All of the other options should be pretty self explanatory

Development
------
Run the tests
```
bundle exec rake spec
```

## License

Copyright (c) 2016 Square Inc. Distributed under the Apache 2.0 License.
See LICENSE file for further details.
