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
* `--log-timings`: log original table_size (data_length + index_length), new table_size, original table_rows, new table_rows, and the number of seconds the copy step took, to STDERR and syslog after the copy is completed.
* `--swap-table-name`: name for the old table after it is swapped
* `--update-tablesize-interval`: how often the size of the original table should be recalculated, in seconds. The size of the table is used to calculate the progress of an osc, so updating this number at regular intervals will make the progress reporting of long-running oscs more accurate. The default value is a reasonable 600, and there probably isn't a need to ever change it.

The save/load state flags essentially allow you to resume OSCs that either failed or were manually stopped. If, for example, the db an osc is running against exceeded the max # threads running threshold, pt-osc will stop. Normally you would have to start the osc over again, but if you were running with the save-state flag then you could resume without losing progress by running with the load-state flag.

### Future Improvements
* When resuming pt-osc with --load-state, the logging doesn't accurately represent what's happening. Specifically, pt-osc will still log that it's doing some of the early steps in the process (ex: creating the shadow table) even if it is actually skipping those steps. This is just a logging problem.
* When resuming pt-osc with --load-state, it would be ideal to load up the nibbling state that was saved with --save-state. As it stands now, when you resume pt-osc, it goes through the whole process of recalculating the rate/size at which it should nibble again. Also, because of this, the copy % that pt-osc emits will reflect the % of work left since being resumed (so it will reset to 0%, but it will progress faster).

## License

Copyright (c) 2016 Square Inc. Distributed under the Apache 2.0 License.
See LICENSE file for further details.
