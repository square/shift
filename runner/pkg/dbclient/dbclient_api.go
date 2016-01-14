package dbclient

type MysqlDB interface {
	// makes query to database
	// returns result as a mapping of strings to string arrays
	// where key is column name and value is the items stored in column
	// in same order as rows
	QueryReturnColumnDict(query string, args ...interface{}) (map[string][]string, error)

	// makes query to database
	// returns result as a mapping of strings to string arrays
	// where key is the value stored in the first column of a row
	// and is mapped to the remaining values in the row
	// in the order as they appeared in the row
	QueryMapFirstColumnToRow(query string, args ...interface{}) (map[string][]string, error)

	// makes a query to the database
	// should be used for inserts and updates. only returns whether
	// or not there was an error
	QueryInsertUpdate(query string, args ...interface{}) error

	// validates whether or not an insert will succeed in a trxn. rolls the
	// trxn back at the end
	ValidateInsertStatement(query string, args ...interface{}) error

	// Log Prints in to the logger
	Log(in interface{})

	// Closes the connection with the database
	Close()
}
