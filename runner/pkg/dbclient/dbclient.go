// Create a mysql client and provide query helpers.
package dbclient

import (
	"crypto/tls"
	"crypto/x509"
	"database/sql"
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"math/rand"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/square/shift/runner/Godeps/_workspace/src/code.google.com/p/goconf/conf"
	"github.com/square/shift/runner/Godeps/_workspace/src/github.com/go-sql-driver/mysql"
	"github.com/square/shift/runner/Godeps/_workspace/src/github.com/golang/glog"
)

type mysqlDB struct {
	Db        *sql.DB
	dsnString string
}

type TlsConfig struct {
	UseTls     bool
	RootCA     string
	ClientCert string
	ClientKey  string
}

const (
	MAX_CONN_RETRIES         = 50
	MAX_QUERY_READ_RETRIES   = 25
	MAX_QUERY_WRITE_RETRIES  = 200
	LOCK_WAIT_TIMEOUT        = 1
	INNODB_LOCK_WAIT_TIMEOUT = 1
	lockWaitTimeoutError     = "Error 1205: Lock wait timeout exceeded; try restarting transaction"
)

// connect to the db and run a query. retry connecting if there is an error
func (database *mysqlDB) queryDb(query string, args ...interface{}) ([]string, [][]string, error) {
	var err error
	for tries := 0; tries <= MAX_CONN_RETRIES; tries++ {
		err = database.Db.Ping()
		if err == nil {
			var cols []string
			var data [][]string
			if args == nil {
				args = make([]interface{}, 0)
			}
			cols, data, err = database.runQuery(query, args...)
			if err == nil {
				return cols, data, nil
			}
		} else {
			database.Db.Close()
			database.Db, err = sql.Open("mysql", database.dsnString)
		}
		// sleep between 0 and 300 milliseconds
		rand.Seed(time.Now().UTC().UnixNano())
		sleepTime := rand.Intn(300)
		time.Sleep(time.Duration(sleepTime) * time.Millisecond)
	}
	return nil, nil, err
}

// makes a query to the database, retrying if the query returns an error.
// returns array of column names and arrays of data stored as string
// string equivalent to []byte. data stored as 2d array with each subarray
// containing a single column's data
func (database *mysqlDB) runQuery(query string, args ...interface{}) ([]string, [][]string, error) {
	var err error
	var rows *sql.Rows
	if args == nil {
		args = make([]interface{}, 0)
	}

	for tries := 0; tries <= MAX_QUERY_READ_RETRIES; tries++ {
		rows, err = database.Db.Query(query, args...)
		if (err == nil) || (err.Error() != lockWaitTimeoutError) {
			if tries > 0 {
				glog.Infof("Lock wait timeout (%ds) exceeded %d times "+
					"(query: %s)", LOCK_WAIT_TIMEOUT, tries, query)
			}
			break
		}
		time.Sleep(1000 * time.Millisecond)
	}
	if err != nil {
		return nil, nil, err
	}

	column_names, err := rows.Columns()
	if err != nil {
		return nil, nil, err
	}

	columns := len(column_names)
	values := make([][]string, columns)
	tmp_values := make([]sql.RawBytes, columns)

	scanArgs := make([]interface{}, len(values))
	for i := range values {
		scanArgs[i] = &tmp_values[i]
	}

	for rows.Next() {
		err = rows.Scan(scanArgs...)
		if err != nil {
			return nil, nil, err
		}
		for i, col := range tmp_values {
			str := string(col)
			values[i] = append(values[i], str)
		}
	}
	err = rows.Err()

	return column_names, values, nil
}

// makes a query to the database, retrying if the query returns an error.
// should be used for inserts and updates. only returns whether or not
// there was an error
func (database *mysqlDB) QueryInsertUpdate(query string, args ...interface{}) error {
	var err error
	if args == nil {
		args = make([]interface{}, 0)
	}

	for tries := 0; tries <= MAX_QUERY_WRITE_RETRIES; tries++ {
		_, err = database.Db.Exec(query, args...)
		if (err == nil) || (err.Error() != lockWaitTimeoutError) {
			if tries > 0 {
				glog.Infof("Lock wait timeout (%ds) exceeded %d times "+
					"(query: %s)", LOCK_WAIT_TIMEOUT, tries, query)
			}
			break
		}
		time.Sleep(1000 * time.Millisecond)
	}

	return err
}

// return values of query in a mapping of column_name -> column
func (database *mysqlDB) QueryReturnColumnDict(query string, args ...interface{}) (map[string][]string, error) {
	var column_names []string
	var values [][]string
	var err error
	if args == nil {
		args = make([]interface{}, 0)
	}
	column_names, values, err = database.queryDb(query, args...)
	result := make(map[string][]string)
	for i, col := range column_names {
		result[col] = values[i]
	}
	return result, err
}

// return values of query in a mapping of first columns entry -> row
func (database *mysqlDB) QueryMapFirstColumnToRow(query string, args ...interface{}) (map[string][]string, error) {
	var values [][]string
	var err error
	if args == nil {
		args = make([]interface{}, 0)
	}
	_, values, err = database.queryDb(query, args...)
	result := make(map[string][]string)
	if len(values) == 0 {
		return nil, nil
	}
	for i, name := range values[0] {
		for j, vals := range values {
			if j != 0 {
				result[string(name)] = append(result[string(name)], vals[i])
			}
		}
	}
	return result, err
}

// start a transaction, run an insert statement, roll it back, and return whether or not
// there was an error
func (database *mysqlDB) ValidateInsertStatement(query string, args ...interface{}) (err error) {
	trxn, err := database.Db.Begin()
	if err != nil {
		return err
	}
	// defer rolling back and closing the transaction
	defer func() {
		rollbackError := trxn.Rollback()
		if rollbackError != nil {
			err = rollbackError
		}
	}()

	_, err = trxn.Exec(query, args...)
	return
}

// makes dsn to open up connection
// dsn is made up of the format:
//     [user[:password]@][protocol[(address)]]/dbname[?param1=value1&...&paramN=valueN]
func makeDsn(dsn map[string]string) string {
	var dsnString string
	user, userok := dsn["user"]
	if userok {
		dsnString = user
	}
	password, ok := dsn["password"]
	if ok {
		dsnString = dsnString + ":" + password
	}
	if userok {
		dsnString = dsnString + "@"
	}
	dsnString = dsnString + dsn["host"]
	dsnString = dsnString + "/" + dsn["dbname"]
	dsnString = dsnString + "?timeout=5s"
	dsnString = dsnString + "&lock_wait_timeout=" + strconv.Itoa(LOCK_WAIT_TIMEOUT)
	dsnString = dsnString + "&innodb_lock_wait_timeout=" + strconv.Itoa(INNODB_LOCK_WAIT_TIMEOUT)
	tls, ok := dsn["tls"]
	if ok {
		dsnString = dsnString + "&tls=" + tls
	}
	return dsnString
}

// create connection to mysql database here
// when an error is encountered, still return database so that the logger may be used
func New(user, password, host, databaseName, config string, tlsConfig *TlsConfig) (MysqlDB, error) {
	dsn := map[string]string{}
	if databaseName == "" {
		dsn["dbname"] = "information_schema"
	} else {
		dsn["dbname"] = databaseName
	}
	database := &mysqlDB{}

	if tlsConfig.UseTls {
		rootCAs := x509.NewCertPool()
		{
			pem, err := ioutil.ReadFile(tlsConfig.RootCA)
			if err != nil {
				return database, err
			}
			if ok := rootCAs.AppendCertsFromPEM(pem); !ok {
				return database, errors.New("Failed to append PEM.")
			}
		}
		clientCerts := make([]tls.Certificate, 0, 1)
		{
			certs, err := tls.LoadX509KeyPair(tlsConfig.ClientCert, tlsConfig.ClientKey)
			if err != nil {
				return database, err
			}
			clientCerts = append(clientCerts, certs)
		}
		mysql.RegisterTLSConfig("custom", &tls.Config{
			RootCAs:            rootCAs,
			Certificates:       clientCerts,
			InsecureSkipVerify: true,
		})
		dsn["tls"] = "custom"
	}

	if user != "" {
		dsn["user"] = user
	}
	if password != "" {
		dsn["password"] = password
	}

	// ex: "unix(/var/lib/mysql/mysql.sock)"
	// ex: "tcp(your.db.host.com:3306)"
	dsn["host"] = host

	//Parse config file to get username and password
	if config != "" {
		_, err := os.Stat(config)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return database, errors.New("'" + config + "' does not exist")
		}
		// read config file to get password
		c, err := conf.ReadConfigFile(config)
		if err != nil {
			return database, err
		}
		user, err := c.GetString("client", "user")
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return database, errors.New("user does not exist in '" + config + "'")
		}
		password, err := c.GetString("client", "password")
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return database, errors.New("password does not exist in '" + config + "'")
		}
		user = strings.Trim(user, " \"")
		password = strings.Trim(password, " \"")
		dsn["user"] = user
		dsn["password"] = password
	}

	if (user == "") && (password != "") {
		return database, errors.New("can't specify a password without a user")
	}
	database.dsnString = makeDsn(dsn)

	//make connection to db
	db, err := sql.Open("mysql", database.dsnString)
	if err != nil {
		return database, err
	}
	database.Db = db

	//ping db to verify connection
	err = database.Db.Ping()
	if err != nil {
		return database, err
	}
	return database, nil
}

func (database *mysqlDB) Log(in interface{}) {
	_, f, line, ok := runtime.Caller(1)
	if ok {
		log.Println("Log from: " + f + " line: " + strconv.Itoa(line))
	}
	log.Println(in)
}

func (database *mysqlDB) Close() {
	database.Db.Close()
}
