// Provide methods to be run on a migration.
package migration

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/square/shift/runner/pkg/dbclient"

	"github.com/square/shift/runner/Godeps/_workspace/src/github.com/golang/glog"
	"github.com/square/shift/runner/Godeps/_workspace/src/gopkg.in/yaml.v2"
)

const (
	maxTableLength = 64
)

// These constants are defined to match with migration's types
// from the UI
const (
	LONG_RUN         = 1
	SHORT_RUN        = 2
	NOCHECKALTER_RUN = 4

	TABLE_MODE = 0
	VIEW_MODE  = 1

	CREATE_ACTION = 0
	DROP_ACTION   = 1
	ALTER_ACTION  = 2

	// migration statuses
	PrepMigrationStatus = 0
	RunMigrationStatus  = 3
	RenameTablesStatus  = 5
	CancelStatus        = 9
	PauseStatus         = 11
)

var (
	MODE_TO_STRING = map[int]string{
		TABLE_MODE: "TABLE",
		VIEW_MODE:  "VIEW",
	}
)

var (
	// regexes for matching pt-osc output
	copyPercentageRegex = regexp.MustCompile("^(?i)Copying `.*`\\.`.*`: +([0-9]|[1-9][0-9]|100)% .*")
	waitingRegex        = regexp.MustCompile("^(?i)Replica.*Waiting\\.$")
	pausingRegex        = regexp.MustCompile("^(?i)Pausing because.*")

	// client functions
	newDbClient = dbclient.New

	// migration methods
	WatchMigrationStdout     = (*Migration).WatchMigrationStdout
	WatchMigrationStderr     = (*Migration).WatchMigrationStderr
	WatchMigrationCopyStderr = (*Migration).WatchMigrationCopyStderr
	GetMigTable              = (*Migration).getMigTable
	SwapTables               = (*Migration).swapTables
	RunReadQuery             = (*Migration).RunReadQuery
	RunWriteQuery            = (*Migration).RunWriteQuery
	DirectDrop               = (*Migration).DirectDrop
	MoveToPendingDrops       = (*Migration).MoveToPendingDrops
	DropTriggers             = (*Migration).DropTriggers
	CleanUp                  = (*Migration).CleanUp
	TimestampedTable         = timestampedTable

	// define errors
	ErrDbConnect   = errors.New("migration: failed to connect to the database")
	ErrQueryFailed = errors.New("migration: query failed")
	ErrStateFile   = errors.New("migration: problem reading statefile")
	ErrTableStats  = errors.New("migration: collecting table stats query didn't return as expected. This is likely due to either " +
		"the database name or table name being incorrect.")
	ErrInvalidInsert    = errors.New("migration: invalid final insert statement")
	ErrDryRunCreatesNew = errors.New("migration: a dry run for creating the table/view didn't run as expected. This is likely due " +
		"to the table/view already existing.")
	ErrDirectDrop            = errors.New("migration: could not figure out how to drop the table/view directly.")
	ErrPtOscStdout           = errors.New("migration: failed to get stdout of pt-online-schema-change")
	ErrPtOscStderr           = errors.New("migration: failed to get stderr of pt-online-schema-change")
	ErrPtOscUnexpectedStderr = errors.New("migration: pt-online-schema-change stderr not as expected")
)

type Migration struct {
	Id             int
	Status         int
	Host           string
	Port           int
	Database       string
	Table          string
	DdlStatement   string
	FinalInsert    string
	Pid            int
	FilesDir       string
	StateFile      string
	LogFile        string
	DbClient       dbclient.MysqlDB
	RunType        int
	Mode           int
	Action         int
	PendingDropsDb string
	CustomOptions  map[string]string
}

type TableStats struct {
	TableRows string
	TableSize string
	IndexSize string
}

// dbClient creates a mysql client that connects to a database host.
func (migration *Migration) SetupDbClient(user, password, cert, key, rootCA string, port int) error {
	tlsConfig := &dbclient.TlsConfig{}
	if (cert != "") && (key != "") && (rootCA != "") {
		tlsConfig.UseTls = true
		tlsConfig.RootCA = rootCA
		tlsConfig.ClientCert = cert
		tlsConfig.ClientKey = key
	}
	host := "tcp(" + migration.Host + ":" + strconv.Itoa(port) + ")"
	db, err := newDbClient(user, password, host, migration.Database, "", tlsConfig)
	if err != nil {
		glog.Errorf("Failed to connect to the database (error: %s).", err)
		return ErrDbConnect
	} else {
		migration.DbClient = db
	}
	glog.Infof("Successfully connected to the database (host = %s, user = %s, database = %s, root ca = %s, cert = %s, key = %s).",
		host, user, migration.Database, rootCA, cert, key)
	return nil
}

// getMigTable gets the 'mig_tbl' field from the migration's state file.
func (migration *Migration) getMigTable() (string, error) {
	var migTable string
	// load up the state file
	if migration.StateFile == "" {
		return migTable, ErrStateFile
	}
	stateFileContents, err := ioutil.ReadFile(migration.StateFile)
	if err != nil {
		return migTable, ErrStateFile
	}

	// get the "mig_tbl" key/value from the state file
	var contents map[interface{}]interface{}
	err = yaml.Unmarshal(stateFileContents, &contents)
	if err != nil {
		return migTable, ErrStateFile
	}
	if val, ok := contents["mig_tbl"]; ok {
		switch vv := val.(type) {
		case string:
			migTable = vv
		}
	}
	if migTable == "" {
		return migTable, ErrStateFile
	}

	return migTable, nil
}

// ClollectTableStats queries a database to get the table stats
// (ex: size, rows, etc.) for a migration.
func (migration *Migration) CollectTableStats() (*TableStats, error) {
	query := "SELECT DATA_LENGTH, INDEX_LENGTH, TABLE_ROWS FROM information_schema.tables WHERE table_schema=? AND table_name=?"
	args := []interface{}{migration.Database, migration.Table}
	response, err := migration.RunReadQuery(query, args...)
	if err != nil {
		return nil, err
	}
	for _, value := range response {
		if len(value) != 1 {
			return nil, ErrTableStats
		}
	}
	tableRows, trOk := response["TABLE_ROWS"]
	tableSize, tsOk := response["DATA_LENGTH"]
	indexSize, isOk := response["INDEX_LENGTH"]
	if !trOk || !tsOk || !isOk {
		return nil, ErrTableStats
	}
	tableStats := &TableStats{
		TableRows: tableRows[0],
		TableSize: tableSize[0],
		IndexSize: indexSize[0],
	}
	return tableStats, nil
}

// ValidateFinalInsert validates the syntax of the final insert statement,
// and starts/rolls back a trxn to verify that the insert won't fail.
func (migration *Migration) ValidateFinalInsert() error {
	finalInsert := migration.FinalInsert
	validInsertRegex := regexp.MustCompile("^(?i)(INSERT\\s+INTO\\s+)[^;]+$")
	validInsertSyntax := validInsertRegex.MatchString(finalInsert)
	if !validInsertSyntax {
		return ErrInvalidInsert
	}

	glog.Infof("mig_id=%d: Validating final insert '%s' in a transaction and rolling it back.", migration.Id, finalInsert)
	err := migration.DbClient.ValidateInsertStatement(finalInsert)
	if err != nil {
		glog.Errorf("mig_id=%d: Final insert '%s' failed (error: %s).", migration.Id, finalInsert, err)
		return ErrInvalidInsert
	}
	glog.Infof("mig_id=%d: Final insert '%s' was successfully validated and rolled back.", migration.Id, finalInsert)

	return nil
}

// DryRunCreatesNew does a dry run for creating a new table/view. First it verifies
// that the table/view doesn't already exist, and then it creates/drops it to verify
// that the ddl is valid.
func (migration *Migration) DryRunCreatesNew() error {
	// verify the table/view doesn't already exist
	query := "SELECT COUNT(*) as count FROM information_schema.tables WHERE table_schema=? AND table_name=?"
	args := []interface{}{migration.Database, migration.Table}
	response, err := RunReadQuery(migration, query, args...)
	if err != nil {
		return err
	}
	if response["count"][0] != "0" {
		glog.Errorf("mig_id=%d: Table/view already exists.", migration.Id)
		return ErrDryRunCreatesNew
	}

	// create and immediately drop the new table/view to verify the validity
	// of the ddl
	err = RunWriteQuery(migration, migration.DdlStatement)
	if err != nil {
		return err
	}
	return DirectDrop(migration)
}

// DirectDrop will drop a table/view directly on the database
func (migration *Migration) DirectDrop() error {
	dropQuery := "DROP " + MODE_TO_STRING[migration.Mode] + " " + migration.Table
	return RunWriteQuery(migration, dropQuery)
}

// swapTables renames two tables atomically.
func (migration *Migration) swapTables(table1Source, table1Dest, table2Source, table2Dest string) error {
	query := "RENAME TABLE " + table1Source + " TO " + table1Dest + ", " + table2Source + " TO " + table2Dest
	return RunWriteQuery(migration, query)
}

// SwapOscTables swaps the original table and migration table for an OSC, and returns
// the name of the table that the original table got renamed to
func (migration *Migration) SwapOscTables() (string, error) {
	var oldTable string
	// get the name of the temporary migration table
	migTable, err := GetMigTable(migration)
	if err != nil {
		return oldTable, err
	}

	// prep the "old" table name
	oldTable = TimestampedTable(migration.Table)

	// swap the tables
	// current table -> old table, mig table -> current table
	err = SwapTables(migration, migration.Table, oldTable, migTable, migration.Table)
	if err != nil {
		glog.Errorf("mig_id=%d: Table swap failed.", migration.Id)
		return "", err
	}

	return oldTable, nil
}

// DropTriggers drops the triggers that reference a migration's table.
func (migration *Migration) DropTriggers(table string) error {
	// get the triggers
	query := "SELECT trigger_name FROM information_schema.triggers WHERE trigger_schema=? AND event_object_table=?"
	args := []interface{}{migration.Database, table}
	response, err := RunReadQuery(migration, query, args...)
	if err != nil {
		return err
	}

	// loop through the triggers and drop each one
	for _, triggerName := range response["trigger_name"] {
		dropQuery := "DROP TRIGGER IF EXISTS `" + migration.Database + "`.`" + triggerName + "`"
		err := RunWriteQuery(migration, dropQuery)
		if err != nil {
			return err
		}
	}
	return nil
}

// MoveToPendingDrops moves a table to the pending_drops database
func (migration *Migration) MoveToPendingDrops(sourceTable, destTable string) error {
	query := "RENAME TABLE `" + migration.Database + "`.`" + sourceTable + "` TO `" + migration.PendingDropsDb +
		"`.`" + destTable + "`"
	err := RunWriteQuery(migration, query)
	if err != nil {
		return err
	}
	return nil
}

// TimestampedTable prefixes a table name with a timestamp
func timestampedTable(table string) string {
	t := time.Now()
	timestamp := fmt.Sprintf("%d%02d%02d%02d%02d%02d%03d", t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), t.Nanosecond()/1000000)
	timestampedTable := timestamp + "_" + table
	// clip the table name if it's too long
	if len(timestampedTable) > maxTableLength {
		timestampedTable = timestampedTable[0:maxTableLength]
	}
	return timestampedTable
}

// CleanUp cleans up after a migration by dropping triggers if they exist,
// and moving the shadow table into the _pending_drops database
func (migration *Migration) CleanUp() error {
	glog.Infof("mig_id=%d: cleaning up triggers.", migration.Id)
	err := DropTriggers(migration, migration.Table)
	if err != nil {
		return err
	}

	glog.Infof("mig_id=%d: cleaning up shadow table.", migration.Id)
	migTable, err := GetMigTable(migration)
	if err != nil {
		return err
	}
	pdTable := TimestampedTable(migTable)
	err = MoveToPendingDrops(migration, migTable, pdTable)
	if err != nil {
		return err
	}
	return nil
}

// RunReadQuery executes a read query on the database for a migration
func (migration *Migration) RunReadQuery(query string, args ...interface{}) (map[string][]string, error) {
	if args == nil {
		glog.Infof("mig_id=%d: Running query '%s'.", migration.Id, query)
	} else {
		glog.Infof("mig_id=%d: Running query '%s' (args: %v).", migration.Id, query, args)
	}
	response, err := migration.DbClient.QueryReturnColumnDict(query, args...)
	if err != nil {
		glog.Errorf("mig_id=%d: Query '%s' failed (error: %s).", migration.Id, query, err)
		return nil, ErrQueryFailed
	}
	glog.Infof("mig_id=%d: Query response was '%v'", migration.Id, response)
	return response, nil
}

// RunWriteQuery executes a write query on the database for a migration
func (migration *Migration) RunWriteQuery(query string, args ...interface{}) error {
	if args == nil {
		glog.Infof("mig_id=%d: Running query '%s'.", migration.Id, query)
	} else {
		glog.Infof("mig_id=%d: Running query '%s' (args: %v).", migration.Id, query, args)
	}
	err := migration.DbClient.QueryInsertUpdate(query, args...)
	if err != nil {
		glog.Errorf("mig_id=%d: Query '%s' failed (error: %s).", migration.Id, query, err)
		return ErrQueryFailed
	}
	return nil
}

// WatchMigrationStdout scans stdout of a migration, line by line, and
// logs it to a file.
func (migration *Migration) WatchMigrationStdout(stdoutPipe io.Reader, errChan chan error, ptOscLogChan chan string) {
	scanner := bufio.NewScanner(stdoutPipe)
	for scanner.Scan() {
		line := scanner.Text()
		ptOscLogChan <- fmt.Sprintf("stdout: %s", line)
	}
	if err := scanner.Err(); err != nil {
		glog.Errorf("mig_id=%d: error getting stdout of pt-osc (error: %s)", migration.Id, err)
		errChan <- ErrPtOscStdout
		return
	}

	errChan <- nil
}

// WatchMigrationStderr scans stderr of a migration, line by line, and
// checks for any unexpected output. It also logs each line to a file
func (migration *Migration) WatchMigrationStderr(stderrPipe io.Reader, errChan chan error, ptOscLogChan chan string) {
	scanner := bufio.NewScanner(stderrPipe)
	var wasError bool

	for scanner.Scan() {
		line := scanner.Text()
		wasError = true
		ptOscLogChan <- fmt.Sprintf("stderr: %s", line)
	}
	if err := scanner.Err(); err != nil {
		glog.Errorf("mig_id=%d: error getting stderr of pt-osc (error: %s)", migration.Id, err)
		errChan <- ErrPtOscStderr
		return
	}

	// if there was anything sent to stderr, there was a problem
	if wasError {
		glog.Errorf("mig_id=%d: stderr is not empty. Something went wrong", migration.Id)
		errChan <- ErrPtOscUnexpectedStderr
		return
	}

	errChan <- nil
}

// WatchMigrationCopyStderr scans stderr of a migration on the copy step,
// and parses each line to get the % copied. It also checks for unexpected
// output, and it logs each line to a file
func (migration *Migration) WatchMigrationCopyStderr(stderrPipe io.Reader, copyPercentChan chan int, errChan chan error, ptOscLogChan chan string) {
	scanner := bufio.NewScanner(stderrPipe)
	var line string
	var wasError bool

	for scanner.Scan() {
		line = scanner.Text()
		wasError = true
		ptOscLogChan <- fmt.Sprintf("stderr: %s", line)

		copyPercentageMatch := copyPercentageRegex.MatchString(line)
		if copyPercentageMatch {
			if len(strings.Fields(line)) < 3 {
				glog.Errorf("mig_id=%d: couldn't get copy percentage from '%s'. Continuing anyway", migration.Id, line)
			}
			copyPercentageS := strings.TrimSuffix(strings.Fields(line)[2], "%")
			copyPercentage, err := strconv.Atoi(copyPercentageS)
			if err != nil {
				glog.Errorf("mig_id=%d: couldn't get int percentage from '%s'. Continuing anyway", migration.Id, line)
			}
			glog.Infof("mig_id=%d: updating migration with copy percentage of %d", migration.Id, copyPercentage)
			copyPercentChan <- copyPercentage
		}
	}
	if err := scanner.Err(); err != nil {
		glog.Errorf("mig_id=%d: error getting stderr of pt-osc (error: %s)", migration.Id, err)
		errChan <- ErrPtOscStderr
		return
	}

	// 0 lines of stderr is okay, because that just means the migration went super quick. if there
	// are lines of stderr, though, and the last line isn't one that we expect, there was a problem
	if wasError {
		copyPercentageMatch := copyPercentageRegex.MatchString(line)
		waitingMatch := waitingRegex.MatchString(line)
		pausingMatch := pausingRegex.MatchString(line)
		if !copyPercentageMatch && !waitingMatch && !pausingMatch {
			glog.Errorf("mig_id=%d: last line of stderror was not what we expect (was: %s). Something went wrong", migration.Id, line)
			errChan <- ErrPtOscUnexpectedStderr
			return
		}
	}

	errChan <- nil
}

func (migration *Migration) ReadStateFile() ([]byte, error) {
	return ioutil.ReadFile(migration.StateFile)
}

func (migration *Migration) WriteStateFile(content []byte) error {
	err := ioutil.WriteFile(migration.StateFile, content, 0777)
	return err
}
