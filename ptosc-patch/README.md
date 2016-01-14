Description
------
Apply this patch to pt-online-schema-change on the system where shift-runner lives. This patch adds the following new flags
* `--save-state`: continuously save the state of the online schema change to a file as it runs. This file can then be used to continue a schema change that has been stopped for some reason
* `--load-state`: load the state of an incomplete online schema change from a file, and continue the schema change from where it previously stopped
* `--exit-at`: if defined, arg must specify one of the following points to exit at
  * create (after creating and altering the new table)
  * triggers (after creating the triggers)
  * copy (after copying the data to the new table)
  * rename (after renaming the tables)

The save/load state flags essentially allow you to resume OSCs that either failed or were manually stopped. If, for example, the db an osc is running against exceeded the max # threads running threshold, pt-osc will stop. Normally you would have to start the osc over again, but if you were running with the save-state flag then you could resume without losing progress by running with the load-state flag.

## License

Copyright (c) 2016 Square Inc. Distributed under the Apache 2.0 License.
See LICENSE file for further details.
