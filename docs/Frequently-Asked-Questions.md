### Why aren't the row counts in the UI 100% accurate?
The row counts in the UI come from the `rows` column in information_schema.tables. The docs for that column say that "For InnoDB tables, the row count is only a rough estimate used in SQL optimization." (https://dev.mysql.com/doc/refman/5.6/en/tables-table.html)

For example, even if you do not insert or delete any rows during a migration, the pre and post-migration row counts might not match:
![Non-matching row counts](https://user-images.githubusercontent.com/26372199/50506575-a670d100-0a9f-11e9-9d6d-405a3f30dc7a.png)