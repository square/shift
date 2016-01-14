// These test connectivity and interactions with a mysql database.
// These do not test using the same queries used for metrics collection.
// The tmpmysqld package is used to make temporary test databases
// to connect to. The package is used to test that the query functions
// work as intended.
//
// Since these tests make use of a temporary mysql instance. Connections
// to permanent databases requiring passwords should be tested manually.
//
// Integration/Acceptance testing is harder and is avoided because
// creating and populating a fake database with the necessary information
// may be more trouble than is worth. Manual testing may be required for
// full acceptance tests.

package dbclient

import (
	"testing"

	"github.com/square/shift/runner/Godeps/_workspace/src/github.com/codahale/tmpmysqld"
)

var (
	expectedValues = map[interface{}]interface{}{}
	server         = new(tmpmysql.MySQLServer)
)

const (
	prefix     = "./testfiles/"
	fakeDBName = "foobar"
)

//initialize test mysql instance and populate with data
func initDB(t testing.TB) mysqlDB {
	var err error
	server, err = tmpmysql.NewMySQLServer("inspect_mysql_test")
	if err != nil {
		t.Fatal(err)
	}

	test := new(mysqlDB)
	test.Db = server.DB
	test.dsnString = "/inspect_mysql_test"

	commands := []string{`
    CREATE TEMPORARY TABLE people (
        name VARCHAR(50) NOT NULL,
        age INT UNSIGNED NOT NULL,
        birthday VARCHAR(50) NOT NULL);`,
		`
    INSERT INTO people
        (name, age, birthday)
        VALUES
        ('alice', 20, 'Jan');`,
		`
    INSERT INTO people
        (name, age, birthday)
        VALUES
        ('bob', 21, 'Feb');`,
		`
    INSERT INTO people
        (name, age, birthday)
        VALUES
        ('charlie', 22, 'Mar');`,
		`
    INSERT INTO people
        (name, age, birthday)
        VALUES
        ('david', 23, 'Apr');`}
	for _, cmd := range commands {
		_, err := test.Db.Exec(cmd)
		if err != nil {
			t.Fatal(err)
		}
	}
	return *test
}

//tests string manipulation of making dsn string
func TestMakeDsn1(t *testing.T) {
	dsn := map[string]string{
		"user":     "brian",
		"password": "secret...shhh!",
		"dbname":   "mysqldb",
	}
	expected := "brian:secret...shhh!@/mysqldb?timeout=5s" +
		"&lock_wait_timeout=1&innodb_lock_wait_timeout=1"
	result := makeDsn(dsn)
	if result != expected {
		t.Error("Incorrect result, expected: " + expected + " but got: " + result)
	}
}

func TestMakeDsn2(t *testing.T) {
	dsn := map[string]string{
		"dbname": "mysqldb",
	}
	expected := "/mysqldb?timeout=5s" +
		"&lock_wait_timeout=1&innodb_lock_wait_timeout=1"
	result := makeDsn(dsn)
	if result != expected {
		t.Error("Incorrect result, expected: " + expected + " but got: " + result)
	}
}

func TestMakeDsn3(t *testing.T) {
	dsn := map[string]string{
		"user":     "brian",
		"password": "secret...shhh!",
		"host":     "unix(mysql.sock)",
		"dbname":   "mysqldb",
	}
	expected := "brian:secret...shhh!@unix(mysql.sock)/mysqldb?timeout=5s" +
		"&lock_wait_timeout=1&innodb_lock_wait_timeout=1"
	result := makeDsn(dsn)
	if result != expected {
		t.Error("Incorrect result, expected: " + expected + " but got: " + result)
	}
}

//test that the correct data is returned,
// as well as test that the ordering is preserved
func TestMakeQuery1(t *testing.T) {
	testdb := initDB(t)
	defer func() {
		testdb.Db.Close()
		server.Stop()
	}()

	cols, data, err := testdb.runQuery("SELECT name FROM people;")
	if err != nil {
		t.Error(err)
	}
	//its important to test lengths so tests don't panic and exit early
	if len(cols) != 1 || len(data) != 1 || len(data[0]) != 4 {
		t.Error("Unexpected data returned")
	}
	if cols[0] != "name" || data[0][0] != "alice" ||
		data[0][1] != "bob" || data[0][2] != "charlie" || data[0][3] != "david" {
		t.Error("Unexpected data returned")
	}
}

func TestMakeQuery2(t *testing.T) {
	testdb := initDB(t)
	defer func() {
		testdb.Db.Close()
		server.Stop()
	}()

	cols, data, err := testdb.runQuery("SELECT name, age FROM people;")
	if err != nil {
		t.Error(err)
	}
	//its important to test lengths so tests don't panic and exit early
	if len(cols) != 2 || len(data) != 2 || len(data[0]) != 4 || len(data[1]) != 4 {
		t.Error("Unexpected data size returned")
	}
	if cols[0] != "name" || data[0][0] != "alice" ||
		data[0][1] != "bob" || data[0][2] != "charlie" || data[0][3] != "david" ||
		data[1][0] != "20" || data[1][1] != "21" || data[1][2] != "22" ||
		data[1][3] != "23" {
		t.Error("Unexpected data returned")
	}
}

//after ensuring TestMakeQuery1 and TestMakeQuery2 are correct,
//can test QueryReturnColumnDict and QueryMapFirstColumnToRow.
//these tests ensure that the results returned to mysqlstat and mysqlstattables
//are formatted as expected.
func TestQueryReturnColumnDict1(t *testing.T) {
	testdb := initDB(t)
	defer func() {
		testdb.Db.Close()
		server.Stop()
	}()

	res, err := testdb.QueryReturnColumnDict("SELECT name FROM people;")
	if err != nil {
		t.Error(err)
	}
	data, ok := res["name"]
	//its important to test lengths so tests don't panic and exit early
	if !ok || len(data) != 4 {
		t.Error("Unexpected data returned")
	}
	if data[0] != "alice" || data[1] != "bob" ||
		data[2] != "charlie" || data[3] != "david" {
		t.Error("Unexpected data returned")
	}
}

func TestQueryReturnColumnDict2(t *testing.T) {
	testdb := initDB(t)
	defer func() {
		testdb.Db.Close()
		server.Stop()
	}()

	res, err := testdb.QueryReturnColumnDict("SELECT name, birthday FROM people;")
	if err != nil {
		t.Error(err)
	}
	names, namesok := res["name"]
	bday, bdayok := res["birthday"]
	//its important to test lengths so tests don't panic and exit early
	if !namesok || !bdayok || len(names) != 4 || len(bday) != 4 {
		t.Error("Unexpected data returned")
	}
	if names[0] != "alice" || names[1] != "bob" ||
		names[2] != "charlie" || names[3] != "david" {
		t.Error("Unexpected name returned")
	}
	if bday[0] != "Jan" || bday[1] != "Feb" ||
		bday[2] != "Mar" || bday[3] != "Apr" {
		t.Error("Unexpected birthday returned")
	}
}

func TestQueryMapFirstColumnToRow1(t *testing.T) {
	testdb := initDB(t)
	defer func() {
		testdb.Db.Close()
		server.Stop()
	}()

	res, err := testdb.QueryMapFirstColumnToRow("SELECT name, birthday FROM people;")
	if err != nil {
		t.Error(err)
	}
	alice, aliceok := res["alice"]
	bob, bobok := res["bob"]
	charlie, charlieok := res["charlie"]
	david, davidok := res["david"]
	if !aliceok || !bobok || !charlieok || !davidok {
		t.Error("Unexpected data returned")
	}
	//its important to test lengths so tests don't panic and exit early
	if len(alice) != 1 || len(alice) != 1 || len(alice) != 1 || len(alice) != 1 {
		t.Error("Unexpected data size returned")
	}
	if alice[0] != "Jan" || bob[0] != "Feb" ||
		charlie[0] != "Mar" || david[0] != "Apr" {
		t.Error("Unexpected birthday returned")
	}
}

func TestQueryMapFirstColumnToRow2(t *testing.T) {
	testdb := initDB(t)
	defer func() {
		testdb.Db.Close()
		server.Stop()
	}()

	res, err := testdb.QueryMapFirstColumnToRow("SELECT name, birthday, age FROM people;")
	if err != nil {
		t.Error(err)
	}
	alice, aliceok := res["alice"]
	bob, bobok := res["bob"]
	charlie, charlieok := res["charlie"]
	david, davidok := res["david"]
	if !aliceok || !bobok || !charlieok || !davidok {
		t.Error("Unexpected data returned")
	}
	//its important to test lengths so tests don't panic and exit early
	if len(alice) != 2 || len(alice) != 2 || len(alice) != 2 || len(alice) != 2 {
		t.Error("Unexpected data size returned")
	}
	if alice[0] != "Jan" || bob[0] != "Feb" ||
		charlie[0] != "Mar" || david[0] != "Apr" {
		t.Error("Unexpected birthday returned")
	}
	if alice[1] != "20" || bob[1] != "21" ||
		charlie[1] != "22" || david[1] != "23" {
		t.Error("Unexpected age returned")
	}
}

func TestQueryInsertUpdate1(t *testing.T) {
	testdb := initDB(t)
	defer func() {
		testdb.Db.Close()
		server.Stop()
	}()

	err := testdb.QueryInsertUpdate("INSERT INTO people (name, birthday, age) values ('charlie', 'Feb', 20)")
	if err != nil {
		t.Errorf("Unexpected error returned (error: %s)", err)
	}
}

func TestQueryInsertUpdate2(t *testing.T) {
	testdb := initDB(t)
	defer func() {
		testdb.Db.Close()
		server.Stop()
	}()

	err := testdb.QueryInsertUpdate("INSERT INTO faketable (name, birthday, age) values ('charlie', 'Feb', 20)")
	if err == nil {
		t.Errorf("Expected error, did not get one.")
	}
}

func TestValidateInsertStatement1(t *testing.T) {
	testdb := initDB(t)
	defer func() {
		testdb.Db.Close()
		server.Stop()
	}()

	err := testdb.ValidateInsertStatement("INSERT INTO people (name, birthday, age) values ('charlie', 'Feb', 20)")
	if err != nil {
		t.Errorf("Unexpected error returned (error: %s)", err)
	}
}

func TestValidateInsertStatement2(t *testing.T) {
	testdb := initDB(t)
	defer func() {
		testdb.Db.Close()
		server.Stop()
	}()

	err := testdb.ValidateInsertStatement("INSERT INTO this is an invalid statement")
	if err == nil {
		t.Errorf("Expected error, did not get one.")
	}
}

//Tests a "bad" connection to the database. On losing a connection
//to a mysql db, metrics collector should retry connecting to database.
func TestBadConnection1(t *testing.T) {
	testdb := initDB(t)
	defer func() {
		testdb.Db.Close()
		server.Stop()
	}()

	_, _, err := testdb.queryDb("SELECT * FROM people;")
	if err != nil {
		t.Error(err)
	}
	//close the connection to the db to ~simulate (kinda)~ a lost connection
	testdb.Db.Close()

	_, _, err = testdb.queryDb("SELECT * FROM people;")
	if err != nil {
		t.Error("failed to reconnect: %v", err)
	}
}
