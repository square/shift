package migration

import (
	"errors"
	"io"
	"os"
	"reflect"
	"regexp"
	"strings"
	"testing"

	"github.com/square/shift/runner/pkg/dbclient"
	"github.com/square/shift/runner/pkg/testutils"
)

const (
	validHost     = "global.rw.hostname"
	validInsert   = "INSERT  INTO\n table t1 (c1) values (5)"
	invalidInsert = "INSERT INTOS table t1 (c1) values (5)"
)

// test setting up a db client for a migration
var setupDbClientTests = []struct {
	cert             string
	key              string
	rootCA           string
	migration        *Migration
	expectedDbClient *testUtils.StubDbClient
	expectedError    error
}{
	// no cert, no tls
	{"", "key", "rootCA", &Migration{Host: validHost}, &testUtils.StubDbClient{Host: "tcp(global.rw.hostname:1243)", UseTls: false}, nil},
	// no key, no tls
	{"cert", "", "rootCA", &Migration{Host: validHost}, &testUtils.StubDbClient{Host: "tcp(global.rw.hostname:1243)", UseTls: false}, nil},
	// no rootCA, no tls
	{"cert", "key", "", &Migration{Host: validHost}, &testUtils.StubDbClient{Host: "tcp(global.rw.hostname:1243)", UseTls: false}, nil},
	// cert and key and rootCA, yes tls
	{"cert", "key", "rootCA", &Migration{Host: validHost}, &testUtils.StubDbClient{Host: "tcp(global.rw.hostname:1243)", UseTls: true}, nil},
	// error from the db client package
	{"", "", "", &Migration{Host: validHost}, nil, ErrDbConnect},
}

func TestSetupDbClient(t *testing.T) {
	for _, tt := range setupDbClientTests {
		migration := tt.migration
		newDbClient = func(user, password, host, database, config string,
			tlsconfig *dbclient.TlsConfig) (dbclient.MysqlDB, error) {
			if tt.expectedError != nil {
				return nil, errors.New("there was an error")
			} else {
				return &testUtils.StubDbClient{Host: host, UseTls: tlsconfig.UseTls}, nil
			}
		}

		actualError := migration.SetupDbClient("db_user", "", tt.cert, tt.key, tt.rootCA, 1243)
		expectedError := tt.expectedError
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		actualDbClient := migration.DbClient
		expectedDbClient := tt.expectedDbClient
		if actualError == nil {
			if !reflect.DeepEqual(actualDbClient, expectedDbClient) {
				t.Errorf("db client = %v, want %v", actualDbClient, expectedDbClient)
			}
		}
	}
}

// test getting the migration table name
var getMigTableTests = []struct {
	stateFile            string
	stateFileExists      bool
	stateFileIsYaml      bool
	stateFileHasMigTable bool
	migTableInStateFile  string
	expectedMigTable     string
	expectedError        error
}{
	// stateFile is not set
	{"", true, true, true, "table", "", ErrStateFile},
	// stateFile doesn't exist
	{"/tmp/statefile.txt", false, true, true, "table", "", ErrStateFile},
	// stateFile exists but isn't expected format
	{"statefile.txt", true, false, true, "table", "", ErrStateFile},
	// stateFile exists but 'mig_tbl' key isn't in it
	{"statefile.txt", true, true, false, "table", "", ErrStateFile},
	// stateFile exists but 'mig_tbl' key is empty
	{"statefile.txt", true, true, true, "", "", ErrStateFile},
	// succeed
	{"statefile.txt", true, true, true, "_table_new", "_table_new", nil},
}

func TestGetMigTable(t *testing.T) {
	for _, tt := range getMigTableTests {
		StubDbClient := &testUtils.StubDbClient{}
		migration := &Migration{DbClient: StubDbClient, StateFile: tt.stateFile}

		if tt.stateFileExists {
			stateFileName := tt.stateFile
			stateFile, _ := os.Create(stateFileName)
			defer os.Remove(stateFileName)
			if tt.stateFileIsYaml {
				if tt.stateFileHasMigTable {
					_, _ = stateFile.WriteString("mig_tbl: " + tt.migTableInStateFile)
				} else {
					_, _ = stateFile.WriteString("something: else")
				}
			} else {
				_, _ = stateFile.WriteString("some random text")
			}
			stateFile.Close()
		}

		actualMigTable, actualError := GetMigTable(migration)
		expectedError := tt.expectedError
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		expectedMigTable := tt.expectedMigTable
		if actualMigTable != expectedMigTable {
			t.Errorf("migTable = %v, want %v", actualMigTable, expectedMigTable)
		}
	}
}

// tests for validating the syntax of a final insert
var validateFinalInsertTests = []struct {
	finalInsert   string
	failQuery     int
	expectedError error
}{
	// invalid final insert
	{invalidInsert, 0, ErrInvalidInsert{}},
	// final insert fails
	{validInsert, 1, ErrInvalidInsert{}},
	// valid final insert
	{validInsert, 0, nil},
}

func TestValidateFinalInsert(t *testing.T) {
	for _, tt := range validateFinalInsertTests {
		StubDbClient := &testUtils.StubDbClient{}
		migration := &Migration{DbClient: StubDbClient, FinalInsert: tt.finalInsert}
		testUtils.FailQuery = tt.failQuery

		expectedError := tt.expectedError
		actualError := migration.ValidateFinalInsert()
		switch actualError.(type) {
		default:
			if actualError != expectedError {
				t.Errorf("error = %v, want %v", actualError, expectedError)
			}
		case ErrInvalidInsert:
			if _, ok := expectedError.(ErrInvalidInsert); !ok {
				t.Errorf("error = %v, want %v", actualError, expectedError)
			}
		}
	}
}

// tests for prefixing a table name with the current timestamp
var timestampedTableTests = []struct {
	table string
}{
	{"table1"},
	// table name is too long
	{"table_name_that_is_fifty_nine_characters_longgggggggggggggg"},
}

func TestTimestampedTable(t *testing.T) {
	for _, tt := range timestampedTableTests {
		var clippedTable string
		// 18 is the length of the timestamp prefix that gets added to
		// the beginning of the table name
		availChars := maxTableLength - 18
		if len(tt.table) > availChars {
			clippedTable = tt.table[0:availChars]
		} else {
			clippedTable = tt.table
		}

		expectedResponse := "[0-9]{17}_" + clippedTable
		expectedRegex := regexp.MustCompile(expectedResponse)
		actualResponse := timestampedTable(tt.table)

		responseMatches := expectedRegex.MatchString(actualResponse)
		if !responseMatches {
			t.Errorf("response (%v) doesn't match %v", actualResponse, expectedResponse)
		}
	}
}

// test collecing table stats from the database for a migration
var collectTableStatsTests = []struct {
	failQuery          int
	queryCol           map[string][]string
	expectedTableStats *TableStats
	expectedError      error
}{
	// fail to execute table stats query
	{1, nil, nil, ErrQueryFailed{}},
	// fail to get table stats when not all fields are returned in query
	{0, map[string][]string{
		"DATA_LENGTH":  []string{"98"},
		"INDEX_LENGTH": []string{"32"},
		"TABLE_ROWS":   []string{},
	}, nil, ErrTableStats},
	// fail to get table stats when a field returns more than one value
	{0, map[string][]string{
		"DATA_LENGTH":  []string{"98"},
		"INDEX_LENGTH": []string{"32"},
		"TABLE_ROWS":   []string{"5", "9"},
	}, nil, ErrTableStats},
	// fail to get table stats when not all expected columns are returned
	{0, map[string][]string{
		"INDEX_LENGTH": []string{"32"},
		"TABLE_ROWS":   []string{"5"},
	}, nil, ErrTableStats},
	// successful collection of table stats
	{0, map[string][]string{
		"DATA_LENGTH":  []string{"98"},
		"INDEX_LENGTH": []string{"32"},
		"TABLE_ROWS":   []string{"5"},
	}, &TableStats{
		TableSize: "98",
		TableRows: "5",
		IndexSize: "32",
	}, nil},
}

func TestCollectTableStats(t *testing.T) {
	for _, tt := range collectTableStatsTests {
		StubDbClient := &testUtils.StubDbClient{}
		migration := &Migration{DbClient: StubDbClient}
		testUtils.FailQuery = tt.failQuery
		testUtils.TestQueryCol = tt.queryCol

		actualTableStats, actualError := migration.CollectTableStats()
		expectedError := tt.expectedError
		switch actualError.(type) {
		default:
			if actualError != expectedError {
				t.Errorf("error = %v, want %v", actualError, expectedError)
			}
		case ErrQueryFailed:
			if _, ok := expectedError.(ErrQueryFailed); !ok {
				t.Errorf("error = %v, want %v", actualError, expectedError)
			}
		}

		expectedTableStats := tt.expectedTableStats
		if !reflect.DeepEqual(actualTableStats, expectedTableStats) {
			t.Errorf("table stats = %v, want %v", actualTableStats, expectedTableStats)
		}
	}
}

// tests for running a dry run of creating a new table/view
var dryRunCreatesNewTests = []struct {
	readQueryError  error
	writeQueryError error
	directDropError error
	queryCol        map[string][]string
	expectedError   error
}{
	// fail to run the query to see if the table/view already exists
	{ErrQueryFailed{}, nil, nil, nil, ErrQueryFailed{}},
	// table/view already exists
	{nil, nil, nil, map[string][]string{"count": []string{"1"}}, ErrDryRunCreatesNew},
	// write query to create the table/view fails
	{nil, ErrQueryFailed{}, nil, map[string][]string{"count": []string{"0"}}, ErrQueryFailed{}},
	// direct drop fails
	{nil, nil, ErrDirectDrop, map[string][]string{"count": []string{"0"}}, ErrDirectDrop},
	// succeed
	{nil, nil, nil, map[string][]string{"count": []string{"0"}}, nil},
}

func TestDryRunCreatesNew(t *testing.T) {
	for _, tt := range dryRunCreatesNewTests {
		StubDbClient := &testUtils.StubDbClient{}
		migration := &Migration{DbClient: StubDbClient}

		RunReadQuery = func(*Migration, string, ...interface{}) (map[string][]string, error) {
			return tt.queryCol, tt.readQueryError
		}
		RunWriteQuery = func(*Migration, string, ...interface{}) error {
			return tt.writeQueryError
		}
		DirectDrop = func(*Migration) error {
			return tt.directDropError
		}

		actualError := migration.DryRunCreatesNew()
		expectedError := tt.expectedError
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}
	}
}

// tests for running a direct drop of a table/view
var directDropTests = []struct {
	table              string
	runType            int
	action             int
	mode               int
	writeQueryError    error
	expectedError      error
	expectedWriteQuery string
}{
	// fail on write query
	{"a", SHORT_RUN, DROP_ACTION, TABLE_MODE, ErrQueryFailed{}, ErrQueryFailed{}, "DROP TABLE a"},
	// succeed drop table
	{"b", SHORT_RUN, DROP_ACTION, TABLE_MODE, nil, nil, "DROP TABLE b"},
	// succeed drop view
	{"c", SHORT_RUN, CREATE_ACTION, VIEW_MODE, nil, nil, "DROP VIEW c"},
}

func TestDirectDrop(t *testing.T) {
	for _, tt := range directDropTests {
		StubDbClient := &testUtils.StubDbClient{}
		migration := &Migration{
			DbClient: StubDbClient,
			Table:    tt.table,
			RunType:  tt.runType,
			Mode:     tt.mode,
			Action:   tt.action,
		}

		var actualWriteQuery string
		RunWriteQuery = func(mig *Migration, query string, args ...interface{}) error {
			actualWriteQuery = query
			return tt.writeQueryError
		}

		actualError := migration.DirectDrop()
		expectedError := tt.expectedError
		switch actualError.(type) {
		default:
			if actualError != expectedError {
				t.Errorf("error = %v, want %v", actualError, expectedError)
			}
		case ErrQueryFailed:
			if _, ok := expectedError.(ErrQueryFailed); !ok {
				t.Errorf("error = %v, want %v", actualError, expectedError)
			}
		}

		expectedWriteQuery := tt.expectedWriteQuery
		if actualWriteQuery != expectedWriteQuery {
			t.Errorf("query = %v, want %v", actualWriteQuery, expectedWriteQuery)
		}
	}
}

// tests for renaming two tables
var swapTablesTests = []struct {
	writeQueryError error
	expectedError   error
}{
	// query failed
	{ErrQueryFailed{}, ErrQueryFailed{}},
	// success
	{nil, nil},
}

func TestSwapTables(t *testing.T) {
	for _, tt := range swapTablesTests {
		StubDbClient := &testUtils.StubDbClient{}
		migration := &Migration{DbClient: StubDbClient}

		RunWriteQuery = func(mig *Migration, query string, args ...interface{}) error {
			return tt.writeQueryError
		}

		actualError := migration.swapTables("t1s", "t1d", "t2s", "t2d")
		expectedError := tt.expectedError
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}
	}
}

// tests for swapping two tables as part of an OSC
var swapOscTablesTests = []struct {
	table            string
	migTable         string
	oldTable         string
	migTableError    error
	swapTableError   error
	expectedSwapArgs []string
	expectedError    error
}{
	// error getting mig table
	{"table", "", "", ErrStateFile, nil, []string{"", "", "", ""}, ErrStateFile},
	// error swapping tables
	{"table", "_table_new", "", nil, ErrQueryFailed{}, []string{"table", "", "_table_new", "table"}, ErrQueryFailed{}},
	// successfully swap tables
	{"table", "_table_new", "_table_old", nil, nil, []string{"table", "_table_old", "_table_new", "table"}, nil},
}

func TestSwapOscTables(t *testing.T) {
	for _, tt := range swapOscTablesTests {
		StubDbClient := &testUtils.StubDbClient{}
		migration := &Migration{DbClient: StubDbClient, Table: tt.table}

		GetMigTable = func(*Migration) (string, error) {
			return tt.migTable, tt.migTableError
		}
		TimestampedTable = func(string) string {
			return tt.oldTable
		}

		var actualSwapArgs []string
		SwapTables = func(mig *Migration, t1s string, t1d string, t2s string, t2d string) error {
			actualSwapArgs = []string{t1s, t1d, t2s, t2d}
			return tt.swapTableError
		}

		actualOldTable, actualError := migration.SwapOscTables()
		expectedError := tt.expectedError
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		expectedOldTable := tt.oldTable
		if actualOldTable != expectedOldTable {
			t.Errorf("old table = %v, want %v", actualOldTable, expectedOldTable)
		}

		if tt.migTableError == nil {
			eq := reflect.DeepEqual(actualSwapArgs, tt.expectedSwapArgs)
			if !eq {
				t.Errorf("swap args = %v, want %v", actualSwapArgs, tt.expectedSwapArgs)
			}
		}
	}
}

// tests for dropping a tables triggers
var dropTriggersTests = []struct {
	readQueryError     error
	writeQueryError    error
	queryCol           map[string][]string
	expectedError      error
	expectedWriteQuery string
}{
	// fail to run the read query
	{ErrQueryFailed{}, nil, nil, ErrQueryFailed{}, ""},
	// fail to run the write query
	{nil, ErrQueryFailed{}, map[string][]string{"trigger_name": []string{"t1"}}, ErrQueryFailed{}, "DROP TRIGGER IF EXISTS `db`.`t1`"},
	// successfully drop a trigger
	{nil, nil, map[string][]string{"trigger_name": []string{"t1"}}, nil, "DROP TRIGGER IF EXISTS `db`.`t1`"},
}

func TestDropTriggers(t *testing.T) {
	for _, tt := range dropTriggersTests {
		StubDbClient := &testUtils.StubDbClient{}
		migration := &Migration{DbClient: StubDbClient, Database: "db", Table: "table"}

		RunReadQuery = func(*Migration, string, ...interface{}) (map[string][]string, error) {
			return tt.queryCol, tt.readQueryError
		}
		var actualWriteQuery string
		RunWriteQuery = func(mig *Migration, query string, args ...interface{}) error {
			actualWriteQuery = query
			return tt.writeQueryError
		}

		actualError := migration.DropTriggers(migration.Table)
		expectedError := tt.expectedError
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		expectedWriteQuery := tt.expectedWriteQuery
		if actualWriteQuery != expectedWriteQuery {
			t.Errorf("query = %v, want %v", actualWriteQuery, expectedWriteQuery)
		}
	}
}

// tests for moving a table to the pending drops db
var moveToPendingDropsTests = []struct {
	sourceTable     string
	destTable       string
	writeQueryError error
	expectedError   error
}{
	// fail to run the query
	{"table1", "table1_old", ErrQueryFailed{}, ErrQueryFailed{}},
	// succeed
	{"table", "table1_old", nil, nil},
}

func TestMoveToPendingDrops(t *testing.T) {
	for _, tt := range moveToPendingDropsTests {
		StubDbClient := &testUtils.StubDbClient{}
		migration := &Migration{DbClient: StubDbClient, Database: "db", PendingDropsDb: "_pending_drops"}

		desiredWriteQuery := "RENAME TABLE `db`.`" + tt.sourceTable + "` TO `_pending_drops`.`" + tt.destTable + "`"

		var actualWriteQuery string
		RunWriteQuery = func(mig *Migration, query string, args ...interface{}) error {
			actualWriteQuery = query
			return tt.writeQueryError
		}

		actualError := migration.MoveToPendingDrops(tt.sourceTable, tt.destTable)
		expectedError := tt.expectedError
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		if actualWriteQuery != desiredWriteQuery {
			t.Errorf("write query = %v, want %v", actualWriteQuery, desiredWriteQuery)
		}
	}
}

// tests for cleaning up after a migration
var cleanUpTests = []struct {
	dropTriggersError error
	getMigTableError  error
	migTable          string
	pdTable           string
	moveToPDError     error
	expectedError     error
}{
	// error dropping triggers
	{ErrQueryFailed{}, nil, "", "", nil, ErrQueryFailed{}},
	// error getting mig table
	{nil, ErrStateFile, "", "", nil, ErrStateFile},
	// error moving to pending drops
	{nil, nil, "_t1_new", "20150826_t1_new", ErrQueryFailed{}, ErrQueryFailed{}},
	// success
	{nil, nil, "_t1_new", "20150826_t1_new", nil, nil},
}

func TestCleanUp(t *testing.T) {
	for _, tt := range cleanUpTests {
		migration := &Migration{Table: "t1"}

		DropTriggers = func(mig *Migration, table string) error {
			if table != "t1" {
				t.Errorf("orig table = %v, want %v", table, "t1")
			}
			return tt.dropTriggersError
		}
		GetMigTable = func(*Migration) (string, error) {
			return tt.migTable, tt.getMigTableError
		}
		TimestampedTable = func(table string) string {
			if table != tt.migTable {
				t.Errorf("mig table = %v, want %v", table, tt.migTable)
			}
			return tt.pdTable
		}
		MoveToPendingDrops = func(mig *Migration, src string, dest string) error {
			if src != tt.migTable {
				t.Errorf("src table = %v, want %v", src, tt.migTable)
			}
			if dest != tt.pdTable {
				t.Errorf("dest table = %v, want %v", dest, tt.pdTable)
			}

			return tt.moveToPDError
		}

		actualError := migration.CleanUp()
		expectedError := tt.expectedError
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}
	}
}

// test running write queries (ex: final insert) for a migration
var runWriteQueryTests = []struct {
	failQuery     int
	query         string
	expectedError error
}{
	// fail to execute insert
	{1, "insert into table", ErrQueryFailed{}},
	// successfully execute insert
	{0, "insert into table", nil},
}

func TestRunWriteQuery(t *testing.T) {
	for _, tt := range runWriteQueryTests {
		StubDbClient := &testUtils.StubDbClient{}
		migration := &Migration{DbClient: StubDbClient}
		testUtils.FailQuery = tt.failQuery

		actualError := migration.RunWriteQuery(tt.query)
		expectedError := tt.expectedError
		switch actualError.(type) {
		default:
			if actualError != expectedError {
				t.Errorf("error = %v, want %v", actualError, expectedError)
			}
		case ErrQueryFailed:
			if _, ok := expectedError.(ErrQueryFailed); !ok {
				t.Errorf("error = %v, want %v", actualError, expectedError)
			}
		}
	}
}

// test running read queries (ex: collect table stats) for a migration
var runReadQueryTests = []struct {
	failQuery        int
	queryCol         map[string][]string
	expectedResponse map[string][]string
	expectedError    error
}{
	// fail to execute query
	{1, map[string][]string{"count": []string{"1"}}, nil, ErrQueryFailed{}},
	// successfully execute query
	{0, map[string][]string{"count": []string{"1"}}, map[string][]string{"count": []string{"1"}}, nil},
}

func TestRunReadQuery(t *testing.T) {
	for _, tt := range runReadQueryTests {
		StubDbClient := &testUtils.StubDbClient{}
		migration := &Migration{DbClient: StubDbClient}
		testUtils.FailQuery = tt.failQuery
		testUtils.TestQueryCol = tt.queryCol

		actualResponse, actualError := migration.RunReadQuery("select count(*) as count from table")
		expectedError := tt.expectedError
		switch actualError.(type) {
		default:
			if actualError != expectedError {
				t.Errorf("error = %v, want %v", actualError, expectedError)
			}
		case ErrQueryFailed:
			if _, ok := expectedError.(ErrQueryFailed); !ok {
				t.Errorf("error = %v, want %v", actualError, expectedError)
			}
		}

		expectedResponse := tt.expectedResponse
		eq := reflect.DeepEqual(actualResponse, expectedResponse)
		if !eq {
			t.Errorf("response = %v, want %v", actualResponse, expectedResponse)
		}
	}
}

// test watching stdout/stderr of a migration
var watchMigrationOutputTests = []struct {
	watchFunc        func(migration *Migration, stderrPipe io.Reader, errChan chan error, ptOscLogChan chan string)
	stderr           string
	expectedLogLines []string
	expectedError    error
}{
	// no errors with stdout
	{WatchMigrationStdout, "line one\nline two\nline three",
		[]string{"stdout: line one", "stdout: line two", "stdout: line three"}, nil},
	// got stderr, which means there was an error
	{WatchMigrationStderr, "line one\nline two\nline three",
		[]string{"stderr: line one", "stderr: line two", "stderr: line three"}, ErrPtOscUnexpectedStderr},
	// nothing sent to stderr
	{WatchMigrationStderr, "", nil, nil},
}

func TestWatchMigrationOutput(t *testing.T) {
	for _, tt := range watchMigrationOutputTests {
		stderrReader := strings.NewReader(tt.stderr)

		errChan := make(chan error, 1)
		logChan := make(chan string, len(tt.expectedLogLines))

		migration := &Migration{}
		go tt.watchFunc(migration, stderrReader, errChan, logChan)

		actualError := <-errChan
		var actualLogLines []string
		for i := 0; i < len(tt.expectedLogLines); i++ {
			line := <-logChan
			actualLogLines = append(actualLogLines, line)
		}

		expectedError := tt.expectedError
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		expectedLogLines := tt.expectedLogLines
		if !reflect.DeepEqual(actualLogLines, expectedLogLines) {
			t.Errorf("log lines = %v, want %v", actualLogLines, expectedLogLines)
		}
	}
}

// test watching stderr during the copy step of a migration
var watchMigrationCopyStderrTests = []struct {
	stderr               string
	expectedLogLines     []string
	expectedCopyPercents []int
	expectedError        error
}{
	// last line of stderr is what we expected 1
	{"line one\nCopying `db`.`table`:   6% 04:21 remain\nCopying `db`.`table`:   72% 01:21 remain",
		[]string{"stderr: line one", "stderr: Copying `db`.`table`:   6% 04:21 remain",
			"stderr: Copying `db`.`table`:   72% 01:21 remain"}, []int{6, 72}, nil},
	// last line of stderr is what we expected 2
	{"line one\nCopying `db`.`table`:   6% 04:21 remain\nReplica something something Waiting.",
		[]string{"stderr: line one", "stderr: Copying `db`.`table`:   6% 04:21 remain",
			"stderr: Replica something something Waiting."}, []int{6}, nil},
	// last line of stderr is what we expected 3
	{"line one\nCopying `db`.`table`:   6% 04:21 remain\nPausing because something",
		[]string{"stderr: line one", "stderr: Copying `db`.`table`:   6% 04:21 remain",
			"stderr: Pausing because something"}, []int{6}, nil},
	// last line of stderr was not what we expected
	{"line one\nCopying `db`.`table`:   6% 04:21 remain\nnot expected",
		[]string{"stderr: line one", "stderr: Copying `db`.`table`:   6% 04:21 remain",
			"stderr: not expected"}, []int{6}, ErrPtOscUnexpectedStderr},
	// nothing sent to stderr
	{"", nil, nil, nil},
}

func TestWatchMigrationCopyStderr(t *testing.T) {
	for _, tt := range watchMigrationCopyStderrTests {
		stderrReader := strings.NewReader(tt.stderr)

		errChan := make(chan error, 1)
		logChan := make(chan string, len(tt.expectedLogLines))
		copyPercentChan := make(chan int, len(tt.expectedCopyPercents))

		migration := &Migration{}
		go WatchMigrationCopyStderr(migration, stderrReader, copyPercentChan, errChan, logChan)

		actualError := <-errChan

		var actualLogLines []string
		for i := 0; i < len(tt.expectedLogLines); i++ {
			line := <-logChan
			actualLogLines = append(actualLogLines, line)
		}
		var actualCopyPercents []int
		for i := 0; i < len(tt.expectedCopyPercents); i++ {
			percent := <-copyPercentChan
			actualCopyPercents = append(actualCopyPercents, percent)
		}

		expectedError := tt.expectedError
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		expectedLogLines := tt.expectedLogLines
		if !reflect.DeepEqual(actualLogLines, expectedLogLines) {
			t.Errorf("log lines = %v, want %v", actualLogLines, expectedLogLines)
		}

		expectedCopyPercents := tt.expectedCopyPercents
		if !reflect.DeepEqual(actualCopyPercents, expectedCopyPercents) {
			t.Errorf("copy percents = %v, want %v", actualCopyPercents, expectedCopyPercents)
		}
	}
}
