package runner

import (
	"bufio"
	"bytes"
	"errors"
	"os"
	"os/signal"
	"reflect"
	"regexp"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/square/shift/runner/pkg/migration"
	"github.com/square/shift/runner/pkg/rest"
	"github.com/square/shift/runner/pkg/testutils"
)

const (
	validHost       = "global.rw.hostname"
	validDdl1       = "ALTEr  TABLE t1 DROP COLUMN c1"
	validDdl2       = "ALTEr  VIEw v1 DROP COLUMN c1"
	validDirectDdl1 = "CREAte Table t1"
	validDirectDdl2 = "drop table v1"
	validDirectDdl3 = "drop view v1"
	finalInsert     = "INSERT  INTO\n table t1 (c1) values (5)"
	port            = 3306
	database        = "db1"
	table           = "t1"
	stateFile       = "/p/state.txt"
	pendingDropsDb  = "_pending_drops"
)

var (
	validTableStats = migration.TableStats{TableRows: "5", TableSize: "98", IndexSize: "32"}
	payloadReceived map[string]string
	writePayload    map[string]string
	appendPayload   []map[string]string
	ErrStaged       = &rest.RestError{"Staged", errors.New("there was an error")}
	ErrUnstage      = &rest.RestError{"Unstage", errors.New("there was an error")}
	ErrNextStep     = &rest.RestError{"NextStep", errors.New("there was an error")}
	ErrUpdate       = &rest.RestError{"Update", errors.New("there was an error")}
	ErrComplete     = &rest.RestError{"Complete", errors.New("there was an error")}
	ErrCancel       = &rest.RestError{"Cancel", errors.New("there was an error")}
	ErrFail         = &rest.RestError{"Fail", errors.New("there was an error")}
	ErrError        = &rest.RestError{"Error", errors.New("there was an error")}
	ErrAppendToFile = &rest.RestError{"AppendToFile", errors.New("there was an error")}
	ErrWriteFile    = &rest.RestError{"WriteFile", errors.New("there was an error")}
	ErrOffer        = &rest.RestError{"Offer", errors.New("there was an error")}
	ErrUnpinRunHost = &rest.RestError{"UnpinHost", errors.New("there was an error")}
	ErrGetFile      = &rest.RestError{"GetFile", errors.New("there was an error")}
)

func validTableStatsPayload(id, startOrEnd string) map[string]string {
	return map[string]string{
		"id":                       id,
		"table_rows_" + startOrEnd: "5",
		"table_size_" + startOrEnd: "98",
		"index_size_" + startOrEnd: "32",
	}
}

// stub a rest client. for each method, 0 means return an empty response,
// 1 means return a normal response, anything else means return an error.
type stubRestClient struct {
	// methods
	staged       int
	unstage      int
	nextStep     int
	update       int
	complete     int
	fail         int
	err          int
	cancel       int
	offer        int
	unpinRunHost int
	appendToFile int
	writeFile    int
	getFile      int
}

func (restClient stubRestClient) Staged() (rest.RestResponseItems, error) {
	if restClient.staged == 0 {
		return []rest.RestResponseItem{}, nil
	} else if restClient.staged == 1 {
		migration := make(map[string]interface{})
		return []rest.RestResponseItem{migration}, nil
	} else {
		return nil, ErrStaged
	}
}

func (restClient stubRestClient) Unstage(params map[string]string) (rest.RestResponseItem, error) {
	payloadReceived = params
	if restClient.unstage == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.unstage == 1 {
		migration := make(map[string]interface{})
		return migration, nil
	} else {
		return nil, ErrUnstage
	}
}

func (restClient stubRestClient) NextStep(params map[string]string) (rest.RestResponseItem, error) {
	payloadReceived = params
	if restClient.nextStep == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.nextStep == 1 {
		migration := make(map[string]interface{})
		return migration, nil
	} else {
		return nil, ErrNextStep
	}
}

func (restClient stubRestClient) Update(params map[string]string) (rest.RestResponseItem, error) {
	payloadReceived = params
	if restClient.update == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.update == 1 {
		migration := make(map[string]interface{})
		return migration, nil
	} else {
		return nil, ErrUpdate
	}
}

func (restClient stubRestClient) Complete(params map[string]string) (rest.RestResponseItem, error) {
	payloadReceived = params
	if restClient.complete == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.complete == 1 {
		migration := make(map[string]interface{})
		return migration, nil
	} else {
		return nil, ErrComplete
	}
}

func (restClient stubRestClient) Fail(params map[string]string) (rest.RestResponseItem, error) {
	payloadReceived = params
	if restClient.fail == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.fail == 1 {
		migration := make(map[string]interface{})
		return migration, nil
	} else {
		return nil, ErrFail
	}
}

func (restClient stubRestClient) Error(params map[string]string) (rest.RestResponseItem, error) {
	payloadReceived = params
	if restClient.err == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.err == 1 {
		migration := make(map[string]interface{})
		return migration, nil
	} else {
		return nil, ErrError
	}
}

func (restClient stubRestClient) Cancel(params map[string]string) (rest.RestResponseItem, error) {
	payloadReceived = params
	if restClient.cancel == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.cancel == 1 {
		migration := make(map[string]interface{})
		return migration, nil
	} else {
		return nil, ErrCancel
	}
}

func (restClient stubRestClient) Offer(params map[string]string) (rest.RestResponseItem, error) {
	payloadReceived = params
	if restClient.offer == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.offer == 1 {
		migration := make(map[string]interface{})
		return migration, nil
	} else {
		return nil, ErrOffer
	}
}

func (restClient stubRestClient) UnpinRunHost(params map[string]string) (rest.RestResponseItem, error) {
	if restClient.unpinRunHost == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.unpinRunHost == 1 {
		migration := make(map[string]interface{})
		return migration, nil
	} else {
		return nil, ErrUnpinRunHost
	}
}

func (restClient stubRestClient) AppendToFile(params map[string]string) (rest.RestResponseItem, error) {
	params["contents"] = params["contents"][22:] // rips out timestamp
	appendPayload = append(appendPayload, params)
	if restClient.appendToFile == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.appendToFile == 1 {
		shiftFile := make(map[string]interface{})
		return shiftFile, nil
	} else {
		return nil, ErrAppendToFile
	}
}

func (restClient stubRestClient) WriteFile(params map[string]string) (rest.RestResponseItem, error) {
	writePayload = params
	if restClient.writeFile == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.writeFile == 1 {
		shiftFile := make(map[string]interface{})
		return shiftFile, nil
	} else {
		return nil, ErrWriteFile
	}
}

func (restClient stubRestClient) GetFile(params map[string]string) (rest.RestResponseItem, error) {
	if restClient.getFile == 0 {
		return rest.RestResponseItem{}, nil
	} else if restClient.getFile == 1 {
		shiftFile := make(map[string]interface{})
		return shiftFile, nil
	} else {
		return nil, ErrGetFile
	}
}

// initialize a stubbed rest client
func initRestClient(staged, unstage, nextStep, update, fail int) stubRestClient {
	return stubRestClient{
		staged:   staged,
		unstage:  unstage,
		nextStep: nextStep,
		update:   update,
		fail:     fail,
	}
}

// initialize a runner
func initRunner(restClient stubRestClient, logDir, defaultsFile, ptOscPath string) *runner {
	runner := &runner{}
	runner.RestClient = restClient
	runner.LogDir = logDir
	runner.MysqlDefaultsFile = defaultsFile
	runner.PtOscPath = ptOscPath
	runner.LogSyncInterval = 1
	runner.StateSyncInterval = 1
	runner.PendingDropsDb = pendingDropsDb
	return runner
}

var hostname, _ = os.Hostname()

// tests for replacing "%hostname%" with actual hostname in a string
var maybeReplaceHostnameTests = []struct {
	input            string
	expectedResponse string
}{
	{"dont-do-anything", "dont-do-anything"},
	{"insert-actual-%hostname%-here", "insert-actual-" + hostname + "-here"},
}

func TestMaybeReplaceHostname(t *testing.T) {
	for _, tt := range maybeReplaceHostnameTests {
		expectedResponse := tt.expectedResponse
		actualResponse := maybeReplaceHostname(tt.input)

		if actualResponse != expectedResponse {
			t.Errorf("response = %v, want %v", actualResponse, expectedResponse)
		}
	}
}

var killAndOfferMigrationsTests = []struct {
	runningMigrations         map[int]int
	expectedPayload           map[string]string
	expectedRunningMigrations map[int]int
}{
	{map[int]int{}, nil, map[int]int{}},
	{map[int]int{123: -1}, map[string]string{"id": "123"}, map[int]int{}},
}

func TestKillAndOfferMigrations(t *testing.T) {
	for _, tt := range killAndOfferMigrationsTests {
		payloadReceived = nil
		runningMigrations = tt.runningMigrations
		currentRunner := initRunner(stubRestClient{}, "", "", "")

		killPtOscById = func(migrationId int) error {
			return nil // nop
		}

		currentRunner.killAndOfferMigrations()

		expectedPayload := tt.expectedPayload
		actualPayload := payloadReceived
		if !reflect.DeepEqual(actualPayload, expectedPayload) {
			t.Errorf("payload = %v, want %v", actualPayload, expectedPayload)
		}

		expectedRunningMigrations := tt.expectedRunningMigrations
		actualRunningMigrations := runningMigrations
		if !reflect.DeepEqual(actualRunningMigrations, expectedRunningMigrations) {
			t.Errorf("running migrations = %v, want %v",
				actualRunningMigrations, expectedRunningMigrations)
		}

	}
}

// table driven test for getting runnable migrations
// for the 'staged' method, 1 means return a normal response, anything else means return
// an error.
var getRunnableMigrationsTests = []struct {
	staged                           int
	unstageRunnableMigrationResponse int
	expectedResponse                 []*migration.Migration
}{
	// fail to get the status of the migration
	{2, 1, nil},
	// fail to unstage runnable migration
	{1, 2, []*migration.Migration{}},
	// no new staged migrations
	{1, 0, []*migration.Migration{}},
	// successfully get a staged migration
	{1, 1, []*migration.Migration{&migration.Migration{}}},
}

func TestGetRunnableMigrations(t *testing.T) {
	for _, tt := range getRunnableMigrationsTests {
		payloadReceived = nil
		currentRunner := initRunner(stubRestClient{staged: tt.staged}, "", "", "")
		// stub out the runner methods that are invoked in getRunnableMigrations
		unstageRunnableMigration = func(*runner, rest.RestResponseItem) (*migration.Migration, error) {
			if tt.unstageRunnableMigrationResponse == 1 {
				return &migration.Migration{}, nil
			} else {
				return nil, errors.New("error")
			}
		}

		expectedResponse := tt.expectedResponse
		actualResponse := currentRunner.getRunnableMigrations()

		if len(actualResponse) != len(expectedResponse) {
			t.Errorf("migration = %v, want %v", actualResponse, expectedResponse)
		}
	}
}

// table driven test for unstaging a runnable migration. test all possible scenarios,
// and validate the payload sent to the shift api
// for the 'unstage' method, 1 means return a normal response, anything else means return
// an error.
var unstageRunnableMigrationTests = []struct {
	migration         rest.RestResponseItem
	statusesToRun     []int
	runnerHostname    string
	unstage           int
	expectedError     error
	expectedMigration *migration.Migration
	expectedPayload   map[string]string
}{
	// fail to get the status of the migration
	{nil, nil, "host", 1, ErrInvalidMigration, nil, nil},
	// don't run since it's not in the list of statuses to run
	{map[string]interface{}{
		"status":  float64(2),
		"runtype": float64(migration.LONG_RUN),
		"mode":    float64(migration.TABLE_MODE),
		"action":  float64(migration.ALTER_ACTION),
	}, []int{1}, "host", 1, nil, nil, nil},
	// fail to get the id of the migration
	{map[string]interface{}{
		"status":  float64(1),
		"runtype": float64(migration.LONG_RUN),
		"mode":    float64(migration.TABLE_MODE),
		"action":  float64(migration.ALTER_ACTION),
	}, []int{1}, "host", 1, ErrInvalidMigration, nil, nil},
	// fail to unstage the migration
	{map[string]interface{}{
		"status":        float64(1),
		"id":            float64(7),
		"host":          validHost,
		"port":          float64(port),
		"database":      database,
		"table":         table,
		"ddl_statement": validDdl1,
		"final_insert":  finalInsert,
		"runtype":       float64(migration.LONG_RUN),
		"mode":          float64(migration.TABLE_MODE),
		"action":        float64(migration.ALTER_ACTION),
	}, []int{1}, "host", 2, ErrUnstage, nil, map[string]string{"id": "7"}},
	// successfully unstage a migration not pinned to any host
	{map[string]interface{}{
		"status":        float64(1),
		"id":            float64(7),
		"host":          validHost,
		"port":          float64(port),
		"database":      database,
		"table":         table,
		"ddl_statement": validDdl1,
		"final_insert":  finalInsert,
		"runtype":       float64(migration.LONG_RUN),
		"mode":          float64(migration.TABLE_MODE),
		"action":        float64(migration.ALTER_ACTION),
	}, []int{1}, "host", 1, nil, &migration.Migration{
		Id:             7,
		Status:         1,
		Host:           validHost,
		Port:           port,
		Database:       database,
		Table:          table,
		DdlStatement:   validDdl1,
		FinalInsert:    finalInsert,
		FilesDir:       "id-7/",
		StateFile:      "id-7/statefile.txt",
		LogFile:        "id-7/ptosc-output.log",
		RunType:        migration.LONG_RUN,
		Mode:           migration.TABLE_MODE,
		Action:         migration.ALTER_ACTION,
		CustomOptions:  map[string]string{},
		PendingDropsDb: pendingDropsDb,
	}, map[string]string{"id": "7"}},
}

func TestUnstageRunnableMigration(t *testing.T) {
	for _, tt := range unstageRunnableMigrationTests {
		payloadReceived = nil
		runner := initRunner(stubRestClient{unstage: tt.unstage}, "", "", "")
		runner.Hostname = tt.runnerHostname
		statusesToRun = tt.statusesToRun

		expectedError := tt.expectedError
		expectedMigration := tt.expectedMigration
		expectedPayload := tt.expectedPayload
		actualMigration, actualError := runner.unstageRunnableMigration(tt.migration)
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		if !reflect.DeepEqual(actualMigration, expectedMigration) {
			t.Errorf("migration = %v, want %v", actualMigration, expectedMigration)
		}

		actualPayload := payloadReceived
		if !reflect.DeepEqual(actualPayload, expectedPayload) {
			t.Errorf("payload = %v, want %v", actualPayload, expectedPayload)
		}
	}
}

// test what happens when a migration is failed. since this function
// has no return value, we validate correct behavior by checking the
// payload that we send to the shift api via the rest package
func TestFailMigration(t *testing.T) {
	payloadReceived = nil
	migrationId := 3
	errorMsg := "There was an error"
	runner := initRunner(stubRestClient{}, "", "", "")
	mig := &migration.Migration{Id: migrationId}

	expectedPayload := map[string]string{
		"id":            "3",
		"error_message": errorMsg,
	}
	runner.failMigration(mig, errorMsg)

	actualPayload := payloadReceived
	if !reflect.DeepEqual(actualPayload, expectedPayload) {
		t.Errorf("actual = %v, want %v", actualPayload, expectedPayload)
	}
}

// table driven test for processing a migration. since this function has
// no return value, we validate correct behavior by how many times each method
// is called (methodCallCounts).
// for each method, 1 means return a normal response, anything else means return
// an error.
var processMigrationTests = []struct {
	migrationStatus            int
	setupDbClientResponse      int
	prepMigrationStepResponse  int
	runMigrationStepResponse   int
	renameTablesStepResponse   int
	pauseMigrationStepResponse int
	killMigStepResponse        int
	hostOverride               string
	methodCallCounts           map[string]int
}{
	// fail on setupDbClient step
	{migration.PrepMigrationStatus, 0, 0, 0, 0, 0, 0, "", map[string]int{
		"failMigration":      1,
		"setupDbClient":      1,
		"prepMigrationStep":  0,
		"runMigrationStep":   0,
		"renameTablesStep":   0,
		"pauseMigrationStep": 0,
		"killMigStep":        0,
	}},
	// fail on prepMigrationStep
	{migration.PrepMigrationStatus, 1, 0, 0, 0, 0, 0, "", map[string]int{
		"failMigration":      1,
		"setupDbClient":      1,
		"prepMigrationStep":  1,
		"runMigrationStep":   0,
		"renameTablesStep":   0,
		"pauseMigrationStep": 0,
		"killMigStep":        0,
	}},
	// successfully complete prepMigrationStep
	{migration.PrepMigrationStatus, 1, 1, 0, 0, 0, 0, "", map[string]int{
		"failMigration":      0,
		"setupDbClient":      1,
		"prepMigrationStep":  1,
		"runMigrationStep":   0,
		"renameTablesStep":   0,
		"pauseMigrationStep": 0,
		"killMigStep":        0,
	}},
	// fail on runMigrationStep
	{migration.RunMigrationStatus, 1, 0, 0, 0, 0, 0, "", map[string]int{
		"failMigration":      1,
		"setupDbClient":      1,
		"prepMigrationStep":  0,
		"runMigrationStep":   1,
		"renameTablesStep":   0,
		"pauseMigrationStep": 0,
		"killMigStep":        0,
	}},
	// successfully complete runMigrationStep
	{migration.RunMigrationStatus, 1, 0, 1, 0, 0, 0, "", map[string]int{
		"failMigration":      0,
		"setupDbClient":      1,
		"prepMigrationStep":  0,
		"runMigrationStep":   1,
		"renameTablesStep":   0,
		"pauseMigrationStep": 0,
		"killMigStep":        0,
	}},
	// fail on renameTablesStep
	{migration.RenameTablesStatus, 1, 0, 0, 0, 0, 0, "", map[string]int{
		"failMigration":      1,
		"setupDbClient":      1,
		"prepMigrationStep":  0,
		"runMigrationStep":   0,
		"renameTablesStep":   1,
		"pauseMigrationStep": 0,
		"killMigStep":        0,
	}},
	// successfully complete renameTablesStep hostOverride
	{migration.RenameTablesStatus, 1, 0, 0, 1, 0, 0, "rw.hostname", map[string]int{
		"failMigration":      0,
		"setupDbClient":      1,
		"prepMigrationStep":  0,
		"runMigrationStep":   0,
		"renameTablesStep":   1,
		"pauseMigrationStep": 0,
		"killMigStep":        0,
	}},
	// successfully complete renameTablesStep
	{migration.RenameTablesStatus, 1, 0, 0, 1, 0, 0, "", map[string]int{
		"failMigration":      0,
		"setupDbClient":      1,
		"prepMigrationStep":  0,
		"runMigrationStep":   0,
		"renameTablesStep":   1,
		"pauseMigrationStep": 0,
		"killMigStep":        0,
	}},
	// fail on pauseMigrationStep
	{migration.PauseStatus, 1, 0, 0, 0, 0, 0, "", map[string]int{
		"failMigration":      1,
		"setupDbClient":      1,
		"prepMigrationStep":  0,
		"runMigrationStep":   0,
		"renameTablesStep":   0,
		"pauseMigrationStep": 1,
		"killMigStep":        0,
	}},
	// successfully complete pauseMigrationStep
	{migration.PauseStatus, 1, 0, 0, 0, 1, 0, "", map[string]int{
		"failMigration":      0,
		"setupDbClient":      1,
		"prepMigrationStep":  0,
		"runMigrationStep":   0,
		"renameTablesStep":   0,
		"pauseMigrationStep": 1,
		"killMigStep":        0,
	}},
	// fail on killMigration step
	{migration.CancelStatus, 1, 0, 0, 0, 0, 0, "", map[string]int{
		"failMigration":      1,
		"setupDbClient":      1,
		"prepMigrationStep":  0,
		"runMigrationStep":   0,
		"renameTablesStep":   0,
		"pauseMigrationStep": 0,
		"killMigStep":        1,
	}},
	// successfully kill a migration
	{migration.CancelStatus, 1, 0, 0, 0, 0, 1, "", map[string]int{
		"failMigration":      0,
		"setupDbClient":      1,
		"prepMigrationStep":  0,
		"runMigrationStep":   0,
		"renameTablesStep":   0,
		"pauseMigrationStep": 0,
		"killMigStep":        1,
	}},
	// unknown status
	{99, 1, 0, 0, 0, 0, 0, "", map[string]int{
		"failMigration":      1,
		"setupDbClient":      1,
		"prepMigrationStep":  0,
		"runMigrationStep":   0,
		"renameTablesStep":   0,
		"pauseMigrationStep": 0,
		"killMigStep":        0,
	}},
}

func TestProcessMigration(t *testing.T) {
	for _, tt := range processMigrationTests {
		testRunner := initRunner(stubRestClient{}, "", "", "")
		unstagedMigrationsWaitGroup.Add(1)
		// keep track of the # of calls for each method
		methodCallCounts := map[string]int{
			"failMigration":      0,
			"setupDbClient":      0,
			"prepMigrationStep":  0,
			"runMigrationStep":   0,
			"renameTablesStep":   0,
			"pauseMigrationStep": 0,
			"killMigStep":        0,
		}
		mig := &migration.Migration{Status: tt.migrationStatus,
			Host: tt.hostOverride}

		failMigration = func(*runner, *migration.Migration, string) {
			methodCallCounts["failMigration"]++
			return
		}
		SetupDbClient = func(*migration.Migration, string, string, string, string, string, int) error {
			methodCallCounts["setupDbClient"]++
			if tt.setupDbClientResponse == 1 {
				return nil
			} else {
				return errors.New("error")
			}
		}
		prepMigrationStep = func(*runner, *migration.Migration) error {
			methodCallCounts["prepMigrationStep"]++
			if tt.prepMigrationStepResponse == 1 {
				return nil
			} else {
				return errors.New("error")
			}
		}
		runMigrationStep = func(*runner, *migration.Migration) error {
			methodCallCounts["runMigrationStep"]++
			if tt.runMigrationStepResponse == 1 {
				return nil
			} else {
				return errors.New("error")
			}
		}
		renameTablesStep = func(*runner, *migration.Migration) error {
			methodCallCounts["renameTablesStep"]++
			if tt.renameTablesStepResponse == 1 {
				return nil
			} else {
				return errors.New("error")
			}
		}
		pauseMigrationStep = func(*runner, *migration.Migration) error {
			methodCallCounts["pauseMigrationStep"]++
			if tt.pauseMigrationStepResponse == 1 {
				return nil
			} else {
				return errors.New("error")
			}
		}
		killMigration = func(*runner, *migration.Migration) error {
			methodCallCounts["killMigStep"]++
			if tt.killMigStepResponse == 1 {
				return nil
			} else {
				return errors.New("error")
			}
		}

		expected := tt.methodCallCounts
		testRunner.processMigration(mig)
		actual := methodCallCounts
		if !reflect.DeepEqual(actual, expected) {
			t.Errorf("actual = %v, want %v", actual, expected)
		}
	}
}

// table driven test for the prep migration step. test all possible scenarios,
// and validate the payload sent to the shift api
var prepMigrationStepTests = []struct {
	update            int
	nextStep          int
	ddlStatement      string
	runType           int
	mode              int
	action            int
	tableStats        *migration.TableStats
	finalInsertError  error
	ptOscError        error
	queryError        error
	dryRunCreateError error
	expectedError     error
	expectedPayload   map[string]string
}{
	// fail validating final insert
	{0, 0, validDdl1, migration.LONG_RUN, migration.TABLE_MODE, migration.ALTER_ACTION,
		nil, migration.ErrInvalidInsert{}, nil, nil, nil, migration.ErrInvalidInsert{}, nil},
	// fail running pt-osc dry run
	{0, 0, validDdl1, migration.LONG_RUN, migration.TABLE_MODE, migration.ALTER_ACTION,
		nil, nil, migration.ErrPtOscUnexpectedStderr, nil, nil, migration.ErrPtOscUnexpectedStderr, nil},
	// fail running direct create dry run
	{0, 0, validDirectDdl1, migration.SHORT_RUN, migration.TABLE_MODE, migration.CREATE_ACTION,
		nil, nil, nil, nil, migration.ErrDryRunCreatesNew, migration.ErrDryRunCreatesNew, nil},
	// fail collecting table status
	{0, 0, validDirectDdl2, migration.SHORT_RUN, migration.TABLE_MODE, migration.DROP_ACTION,
		&validTableStats, nil, nil, migration.ErrQueryFailed{}, nil, migration.ErrQueryFailed{}, nil},
	// fail updating the migration
	{2, 0, validDdl1, migration.LONG_RUN, migration.TABLE_MODE, migration.ALTER_ACTION,
		&validTableStats, nil, nil, nil, nil, ErrUpdate, validTableStatsPayload("7", "start")},
	// fail moving the migration to the next step
	{0, 2, validDirectDdl1, migration.SHORT_RUN, migration.TABLE_MODE, migration.CREATE_ACTION,
		nil, nil, nil, nil, nil, ErrNextStep, map[string]string{"id": "7"}},
	// succeeed nocheckalter run
	{0, 0, validDdl1, migration.NOCHECKALTER_RUN, migration.TABLE_MODE, migration.ALTER_ACTION,
		&validTableStats, nil, nil, nil, nil, nil, map[string]string{"id": "7"}},
	// succeeed long run
	{0, 0, validDdl1, migration.LONG_RUN, migration.TABLE_MODE, migration.ALTER_ACTION,
		&validTableStats, nil, nil, nil, nil, nil, map[string]string{"id": "7"}},
}

func TestPrepMigrationStep(t *testing.T) {
	for _, tt := range prepMigrationStepTests {
		payloadReceived = nil
		currentRunner := initRunner(stubRestClient{update: tt.update, nextStep: tt.nextStep}, "", "", "")
		mig := &migration.Migration{
			Id:           7,
			FinalInsert:  finalInsert,
			DdlStatement: tt.ddlStatement,
			RunType:      tt.runType,
			Mode:         tt.mode,
			Action:       tt.action,
		}
		ValidateFinalInsert = func(*migration.Migration) error {
			return tt.finalInsertError
		}
		execPtOsc = func(*runner, *migration.Migration, commandOptionGenerator, chan int, bool) (bool, error) {
			return false, tt.ptOscError
		}
		DryRunCreatesNew = func(*migration.Migration) error {
			return tt.dryRunCreateError
		}
		CollectTableStats = func(*migration.Migration) (*migration.TableStats, error) {
			return tt.tableStats, tt.queryError
		}

		expectedError := tt.expectedError
		actualError := currentRunner.prepMigrationStep(mig)
		if actualError != expectedError {
			t.Errorf("response = %v, want %v", actualError, expectedError)
		}

		expectedPayload := tt.expectedPayload
		actualPayload := payloadReceived
		if !reflect.DeepEqual(actualPayload, expectedPayload) {
			t.Errorf("actual = %v, want %v", actualPayload, expectedPayload)
		}
	}
}

// tests for running the run migration step
var runMigrationStepTests = []struct {
	ddlStatement         string
	runType              int
	mode                 int
	action               int
	runDirectCreateError error
	runDirectDropError   error
	runPtOscError        error
	expectedError        error
}{
	// fail to create direct
	{
		validDirectDdl1, migration.SHORT_RUN,
		migration.TABLE_MODE, migration.CREATE_ACTION,
		migration.ErrQueryFailed{}, nil, nil, migration.ErrQueryFailed{},
	},
	// fail to drop direct
	{
		validDirectDdl2, migration.SHORT_RUN,
		migration.TABLE_MODE, migration.DROP_ACTION,
		nil, migration.ErrDirectDrop, nil, migration.ErrDirectDrop,
	},
	// run ptosc fails
	{
		validDdl1, migration.LONG_RUN,
		migration.TABLE_MODE, migration.ALTER_ACTION,
		nil, nil, ErrPtOscExec, ErrPtOscExec,
	},
	// run successfully long run
	{
		validDdl1, migration.LONG_RUN,
		migration.TABLE_MODE, migration.ALTER_ACTION,
		nil, nil, nil, nil,
	},
	// run successfully nocheckalter run
	{
		validDdl1, migration.NOCHECKALTER_RUN,
		migration.TABLE_MODE, migration.ALTER_ACTION,
		nil, nil, nil, nil,
	},
}

func TestRunMigrationStep(t *testing.T) {
	for _, tt := range runMigrationStepTests {
		mig := &migration.Migration{
			Id:           7,
			DbClient:     &testUtils.StubDbClient{},
			DdlStatement: tt.ddlStatement,
			RunType:      tt.runType,
			Mode:         tt.mode,
			Action:       tt.action,
		}
		currentRunner := initRunner(stubRestClient{}, "", "", "")
		runMigrationDirect = func(*runner, *migration.Migration) error {
			return tt.runDirectCreateError
		}
		runMigrationDirectDrop = func(*runner, *migration.Migration) error {
			return tt.runDirectDropError
		}
		runMigrationPtOsc = func(*runner, *migration.Migration) error {
			return tt.runPtOscError
		}

		expectedError := tt.expectedError
		actualError := currentRunner.runMigrationStep(mig)
		if actualError != expectedError {
			t.Errorf("response = %v, want %v", actualError, expectedError)
		}
	}
}

// tests for running a create migration directly against the db, and
// and validate the payload sent to the shift api
var runMigrationDirectCreateTests = []struct {
	complete         int
	directQueryError error
	finalInsertError error
	expectedError    error
	expectedPayload  map[string]string
}{
	// fail running migration query directly against the db
	{0, migration.ErrQueryFailed{}, nil, migration.ErrQueryFailed{}, nil},
	// fail running the final insert
	{0, nil, migration.ErrQueryFailed{}, migration.ErrQueryFailed{}, nil},
	// fail completing the migration
	{2, nil, nil, ErrComplete, map[string]string{"id": "7"}},
	// succeed
	{0, nil, nil, nil, map[string]string{"id": "7"}},
}

func TestRunMigrationDirectCreate(t *testing.T) {
	for _, tt := range runMigrationDirectCreateTests {
		payloadReceived = nil
		currentRunner := initRunner(stubRestClient{complete: tt.complete}, "", "", "")
		mig := &migration.Migration{Id: 7, FinalInsert: finalInsert}

		callCounter := 0
		RunWriteQuery = func(mig *migration.Migration, query string, args ...interface{}) (err error) {
			if callCounter == 0 {
				err = tt.directQueryError
			} else if callCounter == 1 {
				err = tt.finalInsertError
			}
			callCounter++
			return
		}

		expectedError := tt.expectedError
		actualError := currentRunner.runMigrationDirect(mig)
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		expectedPayload := tt.expectedPayload
		actualPayload := payloadReceived
		if !reflect.DeepEqual(actualPayload, expectedPayload) {
			t.Errorf("payload = %v, want %v", actualPayload, expectedPayload)
		}
	}
}

// tests for running a drop migration directly against the db, and
// and validate the payload sent to the shift api
var runMigrationDirectDropTests = []struct {
	complete           int
	ddlStatement       string
	runType            int
	mode               int
	action             int
	enableTrash        bool
	dropTriggersError  error
	directDropError    error
	moveToPendingError error
	finalInsertError   error
	expectedError      error
	expectedPayload    map[string]string
}{
	// fail to drop the triggers
	{0, validDirectDdl2, migration.SHORT_RUN, migration.TABLE_MODE, migration.DROP_ACTION, true, migration.ErrQueryFailed{}, nil, nil, nil, migration.ErrQueryFailed{}, nil},
	// fail to directly drop a view alter ddl
	{0, validDirectDdl3, migration.SHORT_RUN, migration.VIEW_MODE, migration.DROP_ACTION, true, nil, migration.ErrDirectDrop, nil, nil, migration.ErrDirectDrop, nil},
	// fail to directly drop a view normal alter
	{0, validDirectDdl2, migration.SHORT_RUN, migration.TABLE_MODE, migration.DROP_ACTION, true, nil, nil, migration.ErrQueryFailed{}, nil, migration.ErrQueryFailed{}, nil},
	// fail running the final insert
	{0, validDirectDdl2, migration.SHORT_RUN, migration.TABLE_MODE, migration.DROP_ACTION, true, nil, nil, nil, migration.ErrQueryFailed{}, migration.ErrQueryFailed{}, nil},
	// fail completing the migration
	{2, validDirectDdl2, migration.SHORT_RUN, migration.TABLE_MODE, migration.DROP_ACTION, true, nil, nil, nil, nil, ErrComplete, map[string]string{"id": "7"}},
	// succeed
	{0, validDirectDdl2, migration.SHORT_RUN, migration.TABLE_MODE, migration.DROP_ACTION, true, nil, nil, nil, nil, nil, map[string]string{"id": "7"}},
	// succeed without trash
	{0, validDirectDdl2, migration.SHORT_RUN, migration.TABLE_MODE, migration.DROP_ACTION, false, nil, nil, migration.ErrQueryFailed{}, nil, nil, map[string]string{"id": "7"}},
}

func TestRunMigrationDirectDrop(t *testing.T) {
	for _, tt := range runMigrationDirectDropTests {
		payloadReceived = nil
		currentRunner := initRunner(stubRestClient{complete: tt.complete}, "", "", "")
		mig := &migration.Migration{
			Id:           7,
			FinalInsert:  finalInsert,
			DdlStatement: tt.ddlStatement,
			RunType:      tt.runType,
			Mode:         tt.mode,
			Action:       tt.action,
			EnableTrash:  tt.enableTrash,
		}

		DropTriggers = func(*migration.Migration, string) error {
			return tt.dropTriggersError
		}
		DirectDrop = func(*migration.Migration) error {
			return tt.directDropError
		}
		MoveToPendingDrops = func(*migration.Migration, string, string) error {
			return tt.moveToPendingError
		}
		RunWriteQuery = func(mig *migration.Migration, query string, args ...interface{}) (err error) {
			if query == finalInsert {
				return tt.finalInsertError
			}
			return nil
		}

		expectedError := tt.expectedError
		actualError := currentRunner.runMigrationDirectDrop(mig)
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		expectedPayload := tt.expectedPayload
		actualPayload := payloadReceived
		if !reflect.DeepEqual(actualPayload, expectedPayload) {
			t.Errorf("payload = %v, want %v", actualPayload, expectedPayload)
		}
	}
}

// tests for running ptosc for a migration, and validate the payload sent
// to the shift api
var runMigrationPtOscTests = []struct {
	canceled        bool
	update          int
	nextStep        int
	errorOut        int
	ptOscError      error
	expectedError   error
	expectedPayload map[string]string
}{
	// fail updating the migration
	{false, 2, 0, 0, nil, ErrUpdate, map[string]string{"id": "7", "run_host": "host"}},
	// fail running pt-osc fail to error out
	{false, 0, 0, 2, ErrUnexpectedExit, ErrError,
		map[string]string{"id": "7", "error_message": ErrUnexpectedExit.Error()}},
	// fail running pt-osc error out successfully
	{false, 0, 0, 0, ErrUnexpectedExit, nil,
		map[string]string{"id": "7", "error_message": ErrUnexpectedExit.Error()}},
	// migration not canceled fail moving the migration to the next step
	{false, 0, 2, 0, nil, ErrNextStep, map[string]string{"id": "7"}},
	// migration not canceled success
	{false, 0, 2, 0, nil, ErrNextStep, map[string]string{"id": "7"}},
	// migration canceled success
	{true, 0, 0, 0, nil, nil, map[string]string{"id": "7", "run_host": "host"}},
}

func TestRunMigrationPtOsc(t *testing.T) {
	for _, tt := range runMigrationPtOscTests {
		unstagedMigrationsWaitGroup.Add(1)
		payloadReceived = nil
		currentRunner := initRunner(stubRestClient{nextStep: tt.nextStep, update: tt.update, err: tt.errorOut}, "", "", "")
		currentRunner.Hostname = "host"
		mig := &migration.Migration{Id: 7}
		execPtOsc = func(*runner, *migration.Migration, commandOptionGenerator, chan int, bool) (bool, error) {
			return tt.canceled, tt.ptOscError
		}

		expectedError := tt.expectedError
		actualError := currentRunner.runMigrationPtOsc(mig)
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		expectedPayload := tt.expectedPayload
		actualPayload := payloadReceived
		if !reflect.DeepEqual(actualPayload, expectedPayload) {
			t.Errorf("payload = %v, want %v", actualPayload, expectedPayload)
		}
	}
}

// tests for the rename tables step. test all possible scenarios,
// and validate the payload sent to the shift api
var renameTablesStepTests = []struct {
	update             int
	complete           int
	enableTrash        bool
	tableStats         *migration.TableStats
	swapOscTablesError error
	tableStatsError    error
	finalInsertError   error
	dropTriggersError  error
	moveToPendingError error
	expectedError      error
	expectedPayload    map[string]string
}{
	// fail running swap tables
	{0, 0, true, &validTableStats, migration.ErrQueryFailed{}, nil, nil, nil, nil, migration.ErrQueryFailed{}, nil},
	// fail dropping the triggers
	{0, 0, true, &validTableStats, nil, nil, nil, migration.ErrQueryFailed{}, nil, migration.ErrQueryFailed{}, nil},
	// fail moving to pending drops
	{0, 0, true, &validTableStats, nil, nil, nil, nil, migration.ErrQueryFailed{}, migration.ErrQueryFailed{}, nil},
	// fail getting table stats
	{0, 0, true, &validTableStats, nil, migration.ErrQueryFailed{}, nil, nil, nil, migration.ErrQueryFailed{}, nil},
	// fail updating the migration
	{2, 0, true, &validTableStats, nil, nil, nil, nil, nil, ErrUpdate, validTableStatsPayload("7", "end")},
	// fail running the final insert
	{0, 0, true, &validTableStats, nil, nil, migration.ErrQueryFailed{}, nil, nil, migration.ErrQueryFailed{}, validTableStatsPayload("7", "end")},
	// fail to complete the migration
	{0, 2, true, &validTableStats, nil, nil, nil, nil, nil, ErrComplete, map[string]string{"id": "7"}},
	// successfully complete the migration
	{0, 0, true, &validTableStats, nil, nil, nil, nil, nil, nil, map[string]string{"id": "7"}},
	// successfully complete the migration withou trash
	{0, 0, false, &validTableStats, nil, nil, nil, nil, migration.ErrQueryFailed{}, nil, map[string]string{"id": "7"}},
}

func TestRenameTablesStep(t *testing.T) {
	for _, tt := range renameTablesStepTests {
		payloadReceived = nil
		currentRunner := initRunner(stubRestClient{update: tt.update, complete: tt.complete}, "", "", "")
		mig := &migration.Migration{Id: 7, FinalInsert: finalInsert, Database: "db1", FilesDir: "id-7", StateFile: "id-7/statefile.txt", LogFile: "id-7/ptosc-output.log", EnableTrash: tt.enableTrash}
		SwapOscTables = func(*migration.Migration) (string, error) {
			return "_tablename_new", tt.swapOscTablesError
		}
		CollectTableStats = func(*migration.Migration) (*migration.TableStats, error) {
			return tt.tableStats, tt.tableStatsError
		}
		RunWriteQuery = func(mig *migration.Migration, query string, args ...interface{}) error {
			if query == finalInsert {
				return tt.finalInsertError
			}
			return nil
		}
		var actualOldTable string
		DropTriggers = func(mig *migration.Migration, oldTable string) error {
			actualOldTable = oldTable
			return tt.dropTriggersError
		}
		MoveToPendingDrops = func(*migration.Migration, string, string) error {
			return tt.moveToPendingError
		}

		MoveToBlackHole = func(*migration.Migration, string) error {
			return nil
		}

		expectedError := tt.expectedError
		actualError := currentRunner.renameTablesStep(mig)
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		expectedPayload := tt.expectedPayload
		actualPayload := payloadReceived
		if !reflect.DeepEqual(actualPayload, expectedPayload) {
			t.Errorf("payload = %v, want %v", actualPayload, expectedPayload)
		}

		if expectedError == nil {
			expectedOldTable := "_tablename_new"
			if actualOldTable != expectedOldTable {
				t.Errorf("oldTable = %v, want %v", actualOldTable, expectedOldTable)
			}
		}
	}
}

// tests for killing a migration's pt-osc process. instead of sending a kill for the tests, we
// instead send a SIGHUP and look to receive that signal. the process we use is the one
// running this test, which is why we don't want to send a SIGKILL
func TestKillPtOscProcess(t *testing.T) {
	pid := syscall.Getpid()
	mig := &migration.Migration{Id: 7}
	originalPtOscKillSignal := ptOscKillSignal
	ptOscKillSignal = syscall.SIGHUP

	runningMigrations[7] = pid
	// a different migration that is not being killed
	runningMigrations[13] = pid

	c := make(chan os.Signal, 1)
	signal.Notify(c, ptOscKillSignal)
	defer signal.Stop(c)

	// pid is in runnging migrations map, so signal is expected
	var expectedError error
	actualError := killPtOscProcess(mig)
	if actualError != expectedError {
		t.Errorf("error = %v, want %v", actualError, expectedError)
	}
	waitSig(t, c, ptOscKillSignal)

	expectedMigMap := map[int]int{13: pid}
	if !reflect.DeepEqual(runningMigrations, expectedMigMap) {
		t.Errorf("running migration map = %v, want %v", runningMigrations, expectedMigMap)
	}

	// pid is in runnging migrations map, but it's not a real process.
	// expect an error.
	runningMigrations[7] = 123456789
	expectedError = ErrPtOscKill
	actualError = killPtOscProcess(mig)
	if actualError != expectedError {
		t.Errorf("error = %v, want %v", actualError, expectedError)
	}

	expectedMigMap = map[int]int{13: pid, 7: 123456789}
	if !reflect.DeepEqual(runningMigrations, expectedMigMap) {
		t.Errorf("running migration map = %v, want %v", runningMigrations, expectedMigMap)
	}

	// cleanup
	runningMigrations = map[int]int{}
	ptOscKillSignal = originalPtOscKillSignal
}

func waitSig(t *testing.T, c <-chan os.Signal, sig os.Signal) {
	select {
	case s := <-c:
		if s != sig {
			t.Errorf("signal was %v, want %v", s, sig)
		}
	case <-time.After(1 * time.Second):
		t.Errorf("timeout waiting for %v", sig)
	}
}

// tests for pausing a migration
var pauseMigrationStepTests = []struct {
	killPtOscError  error
	nextStep        int
	expectedError   error
	expectedPayload map[string]string
}{
	// fail killing ptosc
	{ErrPtOscKill, 0, ErrPtOscKill, nil},
	// fail moving the migration to the next step
	{nil, 2, ErrNextStep, map[string]string{"id": "7"}},
	// successfully move the migration to the next step
	{nil, 0, nil, map[string]string{"id": "7"}},
}

func TestPauseMigrationStep(t *testing.T) {
	for _, tt := range pauseMigrationStepTests {
		payloadReceived = nil
		currentRunner := initRunner(stubRestClient{nextStep: tt.nextStep}, "", "", "")
		mig := &migration.Migration{Id: 7}
		killPtOsc = func(*migration.Migration) error {
			return tt.killPtOscError
		}

		expectedError := tt.expectedError
		actualError := currentRunner.pauseMigrationStep(mig)
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		expectedPayload := tt.expectedPayload
		actualPayload := payloadReceived
		if !reflect.DeepEqual(actualPayload, expectedPayload) {
			t.Errorf("payload = %v, want %v", actualPayload, expectedPayload)
		}
	}
}

// tests for killing a migration
var killMigrationTests = []struct {
	killPtOscError error
	cleanUpError   error
	expectedError  error
}{
	// fail killing ptosc
	{ErrPtOscKill, nil, ErrPtOscKill},
	// fail cleaning up the migration
	{nil, ErrPtOscCleanUp, ErrPtOscCleanUp},
	// success
	{nil, nil, nil},
}

func TestKillMigration(t *testing.T) {
	for _, tt := range killMigrationTests {
		runner := initRunner(stubRestClient{}, ".", "", "")
		mig := &migration.Migration{Id: 7, FilesDir: ".", StateFile: "./statefile.txt"}
		killPtOsc = func(*migration.Migration) error {
			return tt.killPtOscError
		}
		CleanUp = func(*migration.Migration) error {
			return tt.cleanUpError
		}

		expectedError := tt.expectedError
		actualError := runner.killMigration(mig)
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}
	}
}

// test recieiving log lines and sending them to a function to be written to
// a log file
func TestWriteToPtOscLog(t *testing.T) {
	runner := initRunner(stubRestClient{}, "", "", "")
	expectedLines := []string{"line one", "line two", "line three"}
	regexString := "\\[\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\] " // regex for matching timestamp
	ptOscLogChan := make(chan string, 3)
	for _, line := range expectedLines {
		ptOscLogChan <- line
	}

	actualLines := []string{}
	writerFunc := func(writer *bufio.Writer, line string, time time.Time) error {
		timestamp := line[:22]
		line = line[22:] // rips out time stamp
		match, _ := regexp.MatchString(regexString, timestamp)
		if !match {
			t.Errorf("timestamp = %v, want %v", timestamp, regexString)
		}
		actualLines = append(actualLines, line)
		return nil
	}
	close(ptOscLogChan)
	var waitGroup sync.WaitGroup
	waitGroup.Add(1)
	fileSyncWaitGroup.Add(1)
	runner.writeToPtOscLog(nil, ptOscLogChan, writerFunc, 1, &waitGroup)
	waitGroup.Wait()
	fileSyncWaitGroup.Wait()
	if !reflect.DeepEqual(actualLines, expectedLines) {
		t.Errorf("lines = %v, want %v", actualLines, expectedLines)
	}
}

// test writing a line to the ptosc log file
func TestWriteLineToPtOscLog(t *testing.T) {
	writeBuffer := bytes.NewBuffer(nil)
	testWriter := bufio.NewWriter(writeBuffer)
	line := "this is the message"
	currentTime := time.Date(2009, time.November, 10, 23, 0, 0, 0, time.UTC)
	formattedLine := "[" + currentTime.Format("2006-01-02 15:04:05") + "] " + line

	var expectedError error
	actualError := writeLineToPtOscLog(testWriter, formattedLine, currentTime)
	if actualError != expectedError {
		t.Errorf("error = %v, want %v", actualError, expectedError)
	}

	expectedLine := "[2009-11-10 23:00:00] this is the message\n"
	actualLine := writeBuffer.String()
	if actualLine != expectedLine {
		t.Errorf("line = %s, wanted %s", actualLine, expectedLine)
	}
}

// tests for generating the options to pass to pt-online-schema change, based on
// the status of the migration
var generatePtOscCommandTests = []struct {
	defaultsFile    string
	logDir          string
	stateFileExists bool
	migration       *migration.Migration
	expectedOptions []string
}{
	// options for the prepMigration step
	{"defaults-file.cnf", "/log/path/", false, &migration.Migration{Id: 7, DdlStatement: "alter table t1    drop column c",
		Database: "db", Table: "t", Status: 0, Host: "rw.hostname", Port: 1234, RunType: migration.NOCHECKALTER_RUN,
		CustomOptions: map[string]string{}},
		[]string{"--alter", "drop column c", "--dry-run", "-h", "rw.hostname", "-P", "1234", "--defaults-file",
			"defaults-file.cnf", "D=db,t=t"}},
	// options for the runMigration step statefile doesn't exist
	{"defaults-file.cnf", "/log/path/", false, &migration.Migration{Id: 7, DdlStatement: "alter table    t1 drop column c",
		Database: "db", Table: "t", Status: 3, Host: "rw.hostname", Port: 1234, StateFile: stateFile, RunType: migration.LONG_RUN,
		CustomOptions: map[string]string{}},
		[]string{"--max-load", "Threads_running=125", "--critical-load", "Threads_running=200", "--tries",
			"create_triggers:200:1,copy_rows:10000:1", "--max-lag", "1", "--set-vars", "wait_timeout=600,lock_wait_timeout=1",
			"--alter", "drop column c", "--execute", "-h", "rw.hostname", "-P", "1234", "--defaults-file", "defaults-file.cnf",
			"--progress", ptOscProgress, "--exit-at", "copy", "--save-state", stateFile, "D=db,t=t"}},
	// options for the runMigration step statefile does exist
	{"defaults-file.cnf", "/log/path/", true, &migration.Migration{Id: 7, DdlStatement: "alter table    t1 drop column c",
		Database: "db", Table: "t", Status: 3, Host: "rw.hostname", Port: 1234, StateFile: stateFile, RunType: migration.LONG_RUN,
		CustomOptions: map[string]string{}},
		[]string{"--max-load", "Threads_running=125", "--critical-load", "Threads_running=200", "--tries",
			"create_triggers:200:1,copy_rows:10000:1", "--max-lag", "1", "--set-vars", "wait_timeout=600,lock_wait_timeout=1",
			"--alter", "drop column c", "--execute", "-h", "rw.hostname", "-P", "1234", "--defaults-file", "defaults-file.cnf",
			"--progress", ptOscProgress, "--exit-at", "copy", "--save-state", "tmpstate.txt", "--load-state", "tmpstate.txt",
			"D=db,t=t"}},
	// options for the runMigration step statefile doesn't exist and runtype is "nocheck-alter"
	{"defaults-file.cnf", "/log/path/", false, &migration.Migration{Id: 7, DdlStatement: "alter table    t1 drop column c",
		Database: "db", Table: "t", Status: 3, Host: "rw.hostname", Port: 1234, StateFile: stateFile, RunType: migration.NOCHECKALTER_RUN,
		CustomOptions: map[string]string{}},
		[]string{"--max-load", "Threads_running=125", "--critical-load", "Threads_running=200", "--tries",
			"create_triggers:200:1,copy_rows:10000:1", "--max-lag", "1", "--set-vars", "wait_timeout=600,lock_wait_timeout=1",
			"--alter", "drop column c", "--execute", "-h", "rw.hostname", "-P", "1234", "--defaults-file", "defaults-file.cnf",
			"--progress", ptOscProgress, "--exit-at", "copy", "--save-state", stateFile, "--nocheck-alter", "D=db,t=t"}},
	// options that specify custom pt-osc flags
	{"defaults-file.cnf", "/log/path/", false, &migration.Migration{Id: 7, DdlStatement: "alter table    t1 drop column c",
		Database: "db", Table: "t", Status: 3, Host: "rw.hostname", Port: 1234, StateFile: stateFile, RunType: migration.LONG_RUN,
		CustomOptions: map[string]string{"max_threads_running": "321", "max_replication_lag": "4"}},
		[]string{"--max-load", "Threads_running=125", "--critical-load", "Threads_running=321", "--tries",
			"create_triggers:200:1,copy_rows:10000:1", "--max-lag", "4", "--set-vars", "wait_timeout=600,lock_wait_timeout=1",
			"--alter", "drop column c", "--execute", "-h", "rw.hostname", "-P", "1234", "--defaults-file", "defaults-file.cnf",
			"--progress", ptOscProgress, "--exit-at", "copy", "--save-state", stateFile, "D=db,t=t"}},
	// options that specify optional custom pt-osc flags
	{"defaults-file.cnf", "/log/path/", false, &migration.Migration{Id: 7, DdlStatement: "alter table    t1 drop column c",
		Database: "db", Table: "t", Status: 3, Host: "rw.hostname", Port: 1234, StateFile: stateFile, RunType: migration.LONG_RUN,
		CustomOptions: map[string]string{"max_threads_running": "321", "max_replication_lag": "4",
			"config_path": "/path/to/file", "recursion_method": "hosts"}},
		[]string{"--config", "/path/to/file", "--alter", "drop column c", "--execute", "-h", "rw.hostname", "-P", "1234", "--defaults-file",
			"defaults-file.cnf", "--progress", ptOscProgress, "--exit-at", "copy", "--save-state", stateFile,
			"--recursion-method", "hosts", "D=db,t=t"}},
	// options for an unexpected step
	{"", "", false, &migration.Migration{Id: 7, Status: 2}, []string{}},
}

func TestGeneratePtOscCommand(t *testing.T) {
	for _, tt := range generatePtOscCommandTests {
		currentRunner := initRunner(stubRestClient{}, tt.logDir, tt.defaultsFile, "")

		if tt.stateFileExists {
			tmpState := "tmpstate.txt"
			tt.migration.StateFile = tmpState
			os.Create(tmpState)
			defer os.Remove(tmpState)
		}

		expectedOptions := tt.expectedOptions
		actualOptions := currentRunner.generatePtOscCommand(tt.migration)
		if !reflect.DeepEqual(actualOptions, expectedOptions) {
			t.Errorf("options = %v, want %v", actualOptions, expectedOptions)
		}
	}
}

// test exec-ing pt-online-schema-change
var execPtOscTests = []struct {
	status                int
	logDir                string
	commandPath           string
	commandOptions        []string
	kill                  bool
	diffKillSignal        bool
	expectedCancel        bool
	expectedPayload       map[string]string
	expectedError         error
	expectedAppendPayload []map[string]string
	expectedWritePayload  map[string]string
}{
	// fail to create a log file b/c dir already exists
	{0, "id-f/", "fakecommand", nil, false, false, false, nil, ErrPtOscExec, nil, nil},
	// fail to create a log file b/c can't make dir
	{0, "tmp/", "fakecommand", nil, false, false, false, nil, ErrPtOscExec, nil, nil},
	// fail to exec due to command not existing
	{0, "", "fakecommand", nil, false, false, false, nil, ErrPtOscExec, nil, nil},
	// execute with an error in stderr
	{0, "", "/bin/sh", []string{"runme"}, false, false, false, nil, migration.ErrPtOscUnexpectedStderr, []map[string]string{
		map[string]string{"migration_id": "7", "file_type": "0", "contents": "stderr: something\n"}}, nil},
	// execute without errors for a killed migration not on the runMigration step
	{0, "", "sleep", []string{"5"}, true, false, false, nil, nil, nil, nil},
	// execute without errors for a killed migration (that received SIGKILL) on the runMigration step
	{3, "", "sleep", []string{"5"}, true, false, true, nil, nil, nil, nil},
	// execute without errors for a killed migration (that received some other signal than SIGKILL) on the runMigration step
	{3, "", "sleep", []string{"5"}, true, true, false, nil, ErrUnexpectedExit, nil, nil},
	// execute without an error for a migration not on the runMigration step
	{0, "", "sleep", []string{"0"}, false, false, false, nil, nil, nil, nil},
	// execute without an error for a migration on the runMigration step
	{3, "", "sleep", []string{"0"}, false, false, false, map[string]string{"id": "7", "copy_percentage": "100"}, nil, nil, nil},
	// execute with output
	{0, "", "/bin/sh", []string{"testscript"}, false, false, false, nil, nil, []map[string]string{
		map[string]string{"migration_id": "7", "file_type": "0", "contents": "stdout: test 1\n"},
		map[string]string{"migration_id": "7", "file_type": "0", "contents": "stdout: test 2\n"},
		map[string]string{"migration_id": "7", "file_type": "0", "contents": "stdout: test 3\n"},
	}, map[string]string{"migration_id": "7", "file_type": "1", "contents": "test 3\n"}},
}

func TestExecPtOsc(t *testing.T) {
	// create an unwriteable file so that we can test what happens
	// if there is an error creating a log file.
	_ = os.MkdirAll("id-f/id-7", 0777)
	defer os.RemoveAll("id-f")
	unwriteableFileName := "id-f/id-7/ptosc-output.log"
	unwriteableFile, _ := os.Create(unwriteableFileName)
	_ = unwriteableFile.Chmod(0444)
	unwriteableFile.Close()

	// make the test bash script
	testScriptName := "testscript"
	testScript, _ := os.Create(testScriptName)
	defer os.Remove(testScriptName)
	testScript.Chmod(0777)
	testScript.WriteString("touch ./id-7/statefile.txt; for i in {1..3}; do echo \"test $i\" | tee ./id-7/statefile.txt; sleep 2; done")
	testScript.Close()

	// write a bash script that can be exec-ed and will print to stderr,
	// but will exit with status 0. kinda ghetto, but it works
	stderrPrinterFileName := "runme"
	stderrPrinterFile, _ := os.Create(stderrPrinterFileName)
	defer os.Remove(stderrPrinterFileName)
	_, _ = stderrPrinterFile.WriteString("echo something 1>&2")
	_ = stderrPrinterFile.Chmod(0777)
	stderrPrinterFile.Close()

	for _, tt := range execPtOscTests {
		os.RemoveAll(tt.logDir + "id-7")
		payloadReceived = nil
		appendPayload = nil
		writePayload = nil
		currentRunner := initRunner(stubRestClient{}, tt.logDir, "", tt.commandPath)
		mig := &migration.Migration{Id: 7, Status: tt.status, FilesDir: "id-7/", StateFile: "id-7/statefile.txt", LogFile: "id-7/ptosc-output.log"}

		// specify the exact options we want
		commandGenerator := func(*migration.Migration) []string {
			return tt.commandOptions
		}

		// maybe override kill signal
		originalKillSignal := ptOscKillSignal
		if tt.diffKillSignal {
			ptOscKillSignal = syscall.SIGHUP
		}

		// kill the process if specified in the test arguments. sleeping is
		// kind of a hack, but it works! if we don't run the kill in a goroutine,
		// we can't kill the exec process b/c running the exec blocks on Wait()
		if tt.kill {
			CleanUp = func(*migration.Migration) error {
				return nil
			}
			go func() {
				time.Sleep(2 * time.Second)
				_ = killPtOscProcess(mig)
			}()
		}

		// setup channel for receiving the copy % complete of the migration
		var copyPercentChan chan int
		if tt.expectedPayload != nil || mig.Status == migration.RunMigrationStatus {
			copyPercentChan = make(chan int)
		}

		actualCanceled, actualError := currentRunner.execPtOsc(mig, commandGenerator, copyPercentChan, true)

		// cleanup the pt-osc log file...hard coded for now
		_ = os.Remove(tt.logDir + "id-7/ptosc-output.log")
		// revert to the original ptosc kill signal
		ptOscKillSignal = originalKillSignal

		expectedCanceled := tt.expectedCancel
		if actualCanceled != expectedCanceled {
			t.Errorf("canceled = %v, want %v", actualCanceled, expectedCanceled)
		}

		expectedError := tt.expectedError
		if actualError != expectedError {
			t.Errorf("error = %v, want %v", actualError, expectedError)
		}

		expectedPayload := tt.expectedPayload
		actualPayload := payloadReceived
		if !reflect.DeepEqual(actualPayload, expectedPayload) {
			t.Errorf("payload = %v, want %v", actualPayload, expectedPayload)
		}

		expectedAppendPayload := tt.expectedAppendPayload
		actualAppendPayload := appendPayload
		if !reflect.DeepEqual(actualAppendPayload, expectedAppendPayload) {
			t.Errorf("append payload = %v, want %v", actualAppendPayload, expectedAppendPayload)
		}

		expectedWritePayload := tt.expectedWritePayload
		actualWritePayload := writePayload
		if !reflect.DeepEqual(actualWritePayload, expectedWritePayload) {
			t.Errorf("write payload = %v, want %v", actualWritePayload, expectedWritePayload)
		}

		if tt.logDir == "" {
			os.RemoveAll("id-7")
		} else {
			os.Remove(tt.logDir)
		}
	}
}

// test updating the copy percentage of a migration
func TestUpdateMigrationCopyPercentage(t *testing.T) {
	payloadReceived = nil
	copyPercentChan := make(chan int, 1)
	migration := &migration.Migration{Id: 7}
	copyPercentage := 38
	currentRunner := initRunner(stubRestClient{nextStep: 1}, "", "", "")
	var waitGroup sync.WaitGroup

	copyPercentChan <- copyPercentage
	close(copyPercentChan)
	fileSyncWaitGroup.Add(1)
	waitGroup.Add(1)
	currentRunner.updateMigrationCopyPercentage(migration, copyPercentChan, &waitGroup)
	fileSyncWaitGroup.Wait()
	waitGroup.Wait()

	expectedPayload := map[string]string{"id": "7", "copy_percentage": "38"}
	actualPayload := payloadReceived
	if !reflect.DeepEqual(actualPayload, expectedPayload) {
		t.Errorf("actual = %v, want %v", actualPayload, expectedPayload)
	}
}
