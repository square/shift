// Pick up and run migration jobs.
package runner

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"math/rand"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/square/shift/runner/pkg/migration"
	"github.com/square/shift/runner/pkg/rest"

	"github.com/square/shift/runner/Godeps/_workspace/src/github.com/golang/glog"
	yaml "github.com/square/shift/runner/Godeps/_workspace/src/gopkg.in/yaml.v2"
)

const (
	// how often pt-osc should print out copy % during copy step
	ptOscProgress = "time,5"
	SIGKILLSignal = "killed"

	LOG_FILE_TYPE   = "0"
	STATE_FILE_TYPE = "1"
)

var (
	statusesToRun = []int{migration.PrepMigrationStatus, migration.RunMigrationStatus,
		migration.RenameTablesStatus, migration.CancelStatus, migration.PauseStatus}

	// track pt-osc execs, which may need to be canceled/killed
	runningMigrations           = map[int]int{} // {id: pid}
	runningMigMutex             = &sync.Mutex{}
	ptOscKillSignal             = syscall.SIGKILL
	canPickupMigrations         = false
	unstageMigrationMutex       = &sync.Mutex{}
	fileSyncWaitGroup           sync.WaitGroup
	unstagedMigrationsWaitGroup sync.WaitGroup

	// runner methods
	failMigration            = (*runner).failMigration
	prepMigrationStep        = (*runner).prepMigrationStep
	runMigrationStep         = (*runner).runMigrationStep
	runMigrationDirect       = (*runner).runMigrationDirect
	runMigrationDirectDrop   = (*runner).runMigrationDirectDrop
	runMigrationPtOsc        = (*runner).runMigrationPtOsc
	renameTablesStep         = (*runner).renameTablesStep
	pauseMigrationStep       = (*runner).pauseMigrationStep
	unstageRunnableMigration = (*runner).unstageRunnableMigration
	execPtOsc                = (*runner).execPtOsc
	killMigration            = (*runner).killMigration
	killPtOsc                = killPtOscProcess
	killPtOscById            = killPtOscProcessById

	// migration methods
	SetupDbClient       = (*migration.Migration).SetupDbClient
	CollectTableStats   = (*migration.Migration).CollectTableStats
	ValidateFinalInsert = (*migration.Migration).ValidateFinalInsert
	DryRunCreatesNew    = (*migration.Migration).DryRunCreatesNew
	DropTriggers        = (*migration.Migration).DropTriggers
	DirectDrop          = (*migration.Migration).DirectDrop
	SwapOscTables       = (*migration.Migration).SwapOscTables
	MoveToPendingDrops  = (*migration.Migration).MoveToPendingDrops
	CleanUp             = (*migration.Migration).CleanUp
	RunWriteQuery       = (*migration.Migration).RunWriteQuery

	// define errors
	ErrInvalidMigration = errors.New("runner: invalid migration")
	ErrNotRunning       = errors.New("runner: can't pause or cancel migration that's not running on this host")
	ErrFiles            = errors.New("runner: error creating and retrieving files")
	ErrPtOscExec        = errors.New("runner: error exec-ing pt-osc")
	ErrPtOscKill        = errors.New("runner: error killing pt-osc")
	ErrPtOscCleanUp     = errors.New("runner: error cleaning up after pt-osc (the process was killed though)")
	ErrGeneral          = errors.New("runner: there was an error with the runner")
	ErrUnexpectedExit   = errors.New("runner: pt-osc died for an unexpected reason")
	ErrUnkownStatus     = errors.New("runner: unkown status on the migration")
)

type runner struct {
	RestClient        rest.RestClient
	RestApi           string `yaml:"rest_api"`
	RestCert          string `yaml:"rest_cert"`
	RestKey           string `yaml:"rest_key"`
	MysqlUser         string `yaml:"mysql_user"`
	MysqlPassword     string `yaml:"mysql_password"`
	MysqlCert         string `yaml:"mysql_cert"`
	MysqlKey          string `yaml:"mysql_key"`
	MysqlRootCA       string `yaml:"mysql_rootCA"`
	MysqlDefaultsFile string `yaml:"mysql_defaults_file"`
	LogDir            string `yaml:"log_dir"`
	PendingDropsDb    string `yaml:"pending_drops_db"`
	PtOscPath         string `yaml:"pt_osc_path"`
	HostOverride      string `yaml:"host_override"`
	PortOverride      int    `yaml:"port_override"`
	DatabaseOverride  string `yaml:"database_override"`
	Hostname          string
	LogSyncInterval   int    `yaml:"log_sync_interval"`
	StateSyncInterval int    `yaml:"state_sync_interval"`
	StopFilePath      string `yaml:"stop_file_path"`
}

type TableStats struct {
	tableRows string
	tableSize string
	indexSize string
}

func intInArray(a int, list []int) bool {
	for _, b := range list {
		if b == a {
			return true
		}
	}
	return false
}

// maybeReplaceHostname replaces "%hostname%" in a string with os.Hostname.
// This is primarily used to insert the hostname into file paths that are
// specified in confing files.
func maybeReplaceHostname(a string) string {
	hostnameRegex := regexp.MustCompile("%hostname%")

	hostname, err := os.Hostname()
	if err != nil {
		return a
	}

	return hostnameRegex.ReplaceAllString(a, hostname)
}

func newRunner(configFile string) (*runner, error) {
	runner := &runner{}

	// load up config file into runner struct
	if _, err := os.Stat(configFile); !os.IsNotExist(err) {
		data, err := ioutil.ReadFile(configFile)
		if err != nil {
			return nil, err
		}
		err = yaml.Unmarshal([]byte(os.ExpandEnv(string(data))), &runner)
		if err != nil {
			glog.Infoln(err.Error())
			return nil, err
		}
	}

	_, err := os.Stat(runner.MysqlDefaultsFile)
	if !os.IsExist(err) {
		mysqlCntContent := fmt.Sprintf(
			"[client]\n"+
				"user=%v\npassword=%v", runner.MysqlUser, runner.MysqlPassword)

		if runner.MysqlCert != "" {
			mysqlCntContent = mysqlCntContent + "\n" +
				fmt.Sprintf("ssl=1\n"+
					"ssl-cert=%v\n"+
					"ssl-key=%v\n"+
					"ssl-ca=%v", runner.MysqlCert, runner.MysqlKey, runner.MysqlRootCA)
		}

		mysqlCnfData := []byte(mysqlCntContent)
		err := ioutil.WriteFile(runner.MysqlDefaultsFile, mysqlCnfData, 0644)
		if err != nil {
			return nil, err
		}
	}

	restClient, err := rest.New(runner.RestApi, maybeReplaceHostname(runner.RestCert),
		maybeReplaceHostname(runner.RestKey))
	if err != nil {
		return nil, err
	}

	runner.Hostname, err = os.Hostname()
	if err != nil {
		return nil, err
	}

	runner.RestClient = restClient

	return runner, nil
}

// collect and unstage new migrations, and pass them through the job channel.
// loop every 10-20 seconds.
func (runner *runner) sendRunnableMigrationsToProcessor(jobChannel chan *migration.Migration) {
	for {
		unstageMigrationMutex.Lock()
		if canPickupMigrations {
			newMigrations := runner.getRunnableMigrations()
			for i := range newMigrations {
				// Pass each new, unstaged migration through the job channel.
				unstagedMigrationsWaitGroup.Add(1)
				jobChannel <- newMigrations[i]
			}
		}
		unstageMigrationMutex.Unlock()

		// random sleep time to help load balance
		time.Sleep(time.Duration(rand.Intn(10)+10) * time.Second)
	}
}

// watchForStopFile watches for the existence of a stop file. Will kill and offer up migrations if found
// loop every 1 seconds
func (runner *runner) watchForStopFile() {
	for {
		if _, err := os.Stat(runner.StopFilePath); err == nil {
			glog.Infof("Stop file found (%s), killing...", runner.StopFilePath)
			unstageMigrationMutex.Lock()
			canPickupMigrations = false
			unstagedMigrationsWaitGroup.Wait()
			unstageMigrationMutex.Unlock()
			runner.killAndOfferMigrations()
		} else {
			canPickupMigrations = true
		}
		time.Sleep(1 * time.Second)
	}
}

// Kills the ptosc job and sends migration through api to be picked up by other hosts
func (runner *runner) killAndOfferMigrations() {
	if len(runningMigrations) > 0 {
		killedMigrations := killAllPtOscProcesses()

		glog.Infof("Done killing, waiting for file sync gorountines to finish")

		fileSyncWaitGroup.Wait() // wait for all file syncing goroutines to finish

		glog.Infof("All file syncing gorountines are finished, proceeding...")

		for _, migrationId := range killedMigrations {
			glog.Infof("Offering migration mig_id=%v", migrationId)
			urlParams := map[string]string{"id": strconv.Itoa(migrationId)}
			_, err := runner.RestClient.Offer(urlParams)
			if err != nil {
				glog.Error(err)
			}
		}

		glog.Infof("Offered all killed migrations")
	}
}

// getRunnableMigrations queries the shift api to get new/updated migrations.
func (runner *runner) getRunnableMigrations() []*migration.Migration {
	newMigrations := []*migration.Migration{}

	// Get all of the staged migrations
	glog.Info("Getting staged migrations.")
	stagedMigrations, err := runner.RestClient.Staged()
	if err != nil {
		glog.Errorf("Failed to get staged migrations (error: %s)", err.Error())
		return newMigrations
	}
	if len(stagedMigrations) == 0 {
		glog.Info("No new staged migrations.")
	}

	// For each staged migration, try to unstage it.
	for i := range stagedMigrations {
		newMigration, err := unstageRunnableMigration(runner, stagedMigrations[i])
		if err != nil {
			glog.Errorf(err.Error())
			continue
		}
		if newMigration != nil {
			newMigrations = append(newMigrations, newMigration)
		}
	}
	return newMigrations
}

// unstageRunnableMigration tries to unstage ("claim") migrations that are runnable
func (runner *runner) unstageRunnableMigration(currentMigration rest.RestResponseItem) (*migration.Migration, error) {
	migrationStatusField, ok := currentMigration["status"].(float64)
	if ok == false {
		glog.Errorf("Failed to get migration status for the following migration: %v", currentMigration)
		return nil, ErrInvalidMigration
	}
	migrationStatus := int(migrationStatusField)

	// Manually define the statuses to run
	if intInArray(migrationStatus, statusesToRun) {
		glog.Infof("Status = %d is in the list of statuses to run, so continuing.", migrationStatus)
		migrationIdFieldFloat, ok := currentMigration["id"].(float64)
		if ok == false {
			glog.Errorf("Failed to get migration id for the "+
				"following migration: %v", currentMigration)
			return nil, ErrInvalidMigration
		}
		migrationIdField := int(migrationIdFieldFloat)

		// check if the migration is already pinned to a particular host
		pinnedHostname := currentMigration["run_host"]
		if pinnedHostname != nil {
			pinnedHostname = pinnedHostname.(string)
			if pinnedHostname != runner.Hostname {
				glog.Errorf("mig_id=%d: migration already pinned to %s. Skipping.",
					migrationIdField, pinnedHostname)
				return nil, ErrNotRunning
			}
		}

		customOptions := make(map[string]string)
		if val, ok := currentMigration["custom_options"]; ok && val != nil {
			json.Unmarshal([]byte(currentMigration["custom_options"].(string)), &customOptions)
		}

		// log and statefiles are stored in log directory. ex for mig with id 7: /path/to/logs/statefile-id-7.txt
		filesDir := runner.LogDir + "id-" + strconv.Itoa(int(migrationIdField)) + "/"
		stateFile := filesDir + "statefile.txt"
		logFile := filesDir + "ptosc-output.log"

		mig := &migration.Migration{
			Id:             migrationIdField,
			Status:         migrationStatus,
			Host:           currentMigration["host"].(string),
			Port:           int(currentMigration["port"].(float64)),
			Database:       currentMigration["database"].(string),
			Table:          currentMigration["table"].(string),
			DdlStatement:   currentMigration["ddl_statement"].(string),
			FinalInsert:    currentMigration["final_insert"].(string),
			FilesDir:       filesDir,
			StateFile:      stateFile,
			LogFile:        logFile,
			PendingDropsDb: runner.PendingDropsDb,
			CustomOptions:  customOptions,
		}

		// some extra fields when we're not killing a migration
		if (migrationStatus != migration.CancelStatus) && (migrationStatus != migration.PauseStatus) {
			mig.RunType = int(currentMigration["runtype"].(float64))
			mig.Mode = int(currentMigration["mode"].(float64))
			mig.Action = int(currentMigration["action"].(float64))
		}

		// allow setting overrides for the host and db from config file.
		// this is useful for safe testing in a staging environment
		if runner.HostOverride != "" {
			mig.Host = runner.HostOverride
		}
		if runner.PortOverride != 0 {
			mig.Port = runner.PortOverride
		}
		if runner.DatabaseOverride != "" {
			mig.Database = runner.DatabaseOverride
		}

		// if pending_drops database isn't defined, set it to be the same
		// database that the migration is on.
		if mig.PendingDropsDb == "" {
			mig.PendingDropsDb = mig.Database
		}

		// only claim the migration if we successfully unstage it
		urlParams := map[string]string{"id": strconv.Itoa(mig.Id)}
		_, err := runner.RestClient.Unstage(urlParams)
		if err != nil {
			return nil, err
		}

		glog.Infof("mig_id=%d: Successfully unstaged.", mig.Id)
		return mig, nil
	}
	glog.Infof("Status = %d is not in the list of statuses to run, so skipping.", migrationStatus)
	return nil, nil
}

// failMigration reports a failed migration to the shift database/ui.
func (runner *runner) failMigration(migration *migration.Migration, errorMsg string) {
	glog.Errorf("mig_id=%d: %s.", migration.Id, errorMsg)
	urlParams := map[string]string{
		"id":            strconv.Itoa(migration.Id),
		"error_message": errorMsg,
	}
	_, err := runner.RestClient.Fail(urlParams)
	if err != nil {
		glog.Errorf("mig_id=%d: %s.", migration.Id, err)
		return
	}
	glog.Infof("mig_id=%d: Successfully failed migration.", migration.Id)
	return
}

// processMigration takes migrations from the job channel and decides
// what to do with them (ex: run them, kill them, etc.).
func (runner *runner) processMigration(currentMigration *migration.Migration) {
	glog.Infof("mig_id=%d: Picked up migration from the job channel. Processing.", currentMigration.Id)

	if currentMigration.Status != migration.RunMigrationStatus {
		// excludes RunMigrationStatus because we want to .Done those after
		// we start PtOsc
		defer unstagedMigrationsWaitGroup.Done()
	}

	// setup a database client for the migration
	err := SetupDbClient(currentMigration, runner.MysqlUser, runner.MysqlPassword,
		maybeReplaceHostname(runner.MysqlCert), maybeReplaceHostname(runner.MysqlKey),
		maybeReplaceHostname(runner.MysqlRootCA), currentMigration.Port)
	if err != nil {
		failMigration(runner, currentMigration, err.Error())
		return
	}
	if currentMigration.DbClient != nil {
		defer currentMigration.DbClient.Close()
	}

	switch currentMigration.Status {
	case migration.PrepMigrationStatus:
		err = prepMigrationStep(runner, currentMigration)
	case migration.RunMigrationStatus:
		err = runMigrationStep(runner, currentMigration)
	case migration.RenameTablesStatus:
		err = renameTablesStep(runner, currentMigration)
	case migration.PauseStatus:
		err = pauseMigrationStep(runner, currentMigration)
	case migration.CancelStatus:
		err = killMigration(runner, currentMigration)
	default:
		err = ErrUnkownStatus
	}

	if err != nil {
		failMigration(runner, currentMigration, err.Error())
	}
}

// prepMigrationStep collects the table stats for a migration, sends them
// to the shift api, and moves the migration to the next step.
func (runner *runner) prepMigrationStep(currentMigration *migration.Migration) error {
	// validate the final insert statement.
	if currentMigration.FinalInsert != "" {
		err := ValidateFinalInsert(currentMigration)
		if err != nil {
			return err
		}
	}

	// only do a dry-run if the ddl should be run with pt-osc
	if currentMigration.RunType != migration.SHORT_RUN {
		// run a dry-run of pt-osc and make sure there were no errors.
		// this will also validate the ddl statement.
		var copyPercentChan chan int
		_, err := execPtOsc(runner, currentMigration, runner.generatePtOscCommand, copyPercentChan, true)
		if err != nil {
			return err
		}
	}

	var urlParams map[string]string
	migrationId := strconv.Itoa(currentMigration.Id)
	// if the migration is creating a new table/view, verify it doesn't
	// already exist and then create/drop it to validate the ddl.
	// if the migration is not creating a new table/view, just collect
	// table stats.
	if currentMigration.Action == migration.CREATE_ACTION {
		err := DryRunCreatesNew(currentMigration)
		if err != nil {
			return err
		}
	} else {
		tableStatsStart, err := CollectTableStats(currentMigration)
		if err != nil {
			return err
		}

		// send the table stats to the api
		urlParams = map[string]string{
			"id":               migrationId,
			"table_rows_start": tableStatsStart.TableRows,
			"table_size_start": tableStatsStart.TableSize,
			"index_size_start": tableStatsStart.IndexSize,
		}
		_, err = runner.RestClient.Update(urlParams)
		if err != nil {
			return err
		}
	}

	// move the migration to the next step
	urlParams = map[string]string{"id": migrationId}
	_, err := runner.RestClient.NextStep(urlParams)
	if err != nil {
		return err
	}
	return nil
}

// runMigrationStep actually runs a migration. Based on the ddl statement, it
// either runs it directly against the database, or with the ptosc tool
func (runner *runner) runMigrationStep(currentMigration *migration.Migration) (err error) {
	if currentMigration.RunType == migration.SHORT_RUN {
		defer unstagedMigrationsWaitGroup.Done()
		if currentMigration.Action == migration.DROP_ACTION {
			return runMigrationDirectDrop(runner, currentMigration)
		} else {
			return runMigrationDirect(runner, currentMigration)
		}
	} else {
		return runMigrationPtOsc(runner, currentMigration)
	}
}

// runMigrationDirect runs a migration query directly against the database.
// It then does all the remaining steps to fully complete the migration.
func (runner *runner) runMigrationDirect(currentMigration *migration.Migration) (err error) {
	// run the migration directly against the database
	err = RunWriteQuery(currentMigration, currentMigration.DdlStatement)
	if err != nil {
		return
	}

	// run the final insert
	if currentMigration.FinalInsert != "" {
		err = RunWriteQuery(currentMigration, currentMigration.FinalInsert)
		if err != nil {
			return
		}
	}

	// complete the migration
	urlParams := map[string]string{"id": strconv.Itoa(currentMigration.Id)}
	_, err = runner.RestClient.Complete(urlParams)
	if err != nil {
		return
	}
	return
}

// runMigrationDirectDrop runs a DROP or RENAME query directly against the database.
// It then does all the remaining steps to fully complete the migration.
func (runner *runner) runMigrationDirectDrop(currentMigration *migration.Migration) (err error) {
	// drop triggers that reference the table
	err = DropTriggers(currentMigration, currentMigration.Table)
	if err != nil {
		return
	}

	// views can't be renamed to a different database. if the mig is for a view,
	// drop it. if the mig is for a table, move it to _pending_drops
	if currentMigration.Mode == migration.VIEW_MODE {
		err = DirectDrop(currentMigration)
		if err != nil {
			return
		}
	} else {
		// rename old table to the pending_drops database instead of actually
		// dropping it
		pdTable := migration.TimestampedTable(currentMigration.Table)
		err = MoveToPendingDrops(currentMigration, currentMigration.Table, pdTable)
		if err != nil {
			return
		}
	}

	// run the final insert
	if currentMigration.FinalInsert != "" {
		err = RunWriteQuery(currentMigration, currentMigration.FinalInsert)
		if err != nil {
			return
		}
	}

	// complete the migration
	urlParams := map[string]string{"id": strconv.Itoa(currentMigration.Id)}
	_, err = runner.RestClient.Complete(urlParams)
	if err != nil {
		return
	}
	return
}

// runMigrationPtOsc runs the pt-osc tool for the main copy step and
// moves the migration to the next step if there were no problems.
func (runner *runner) runMigrationPtOsc(currentMigration *migration.Migration) (err error) {
	// pin the migration to this host
	migrationId := strconv.Itoa(currentMigration.Id)
	urlParams := map[string]string{
		"id":       migrationId,
		"run_host": runner.Hostname,
	}
	_, err = runner.RestClient.Update(urlParams)
	if err != nil {
		unstagedMigrationsWaitGroup.Done()
		return
	}

	defer runner.RestClient.UnpinRunHost(map[string]string{"id": migrationId})

	copyPercentChan := make(chan int)
	canceled, err := execPtOsc(runner, currentMigration, runner.generatePtOscCommand, copyPercentChan, false)
	if err != nil {
		// if pt-osc ran into an error, move the migration to the "error" step instead
		// of failing it. from the "error" step we will have the ability to try and
		// resume the migration, or clean it up
		urlParams := map[string]string{
			"id":            strconv.Itoa(currentMigration.Id),
			"error_message": err.Error(),
		}
		_, err = runner.RestClient.Error(urlParams)
		if err != nil {
			return
		}
		return nil
	}

	// move it to the next step if it wasn't canceled
	if !canceled {
		urlParams := map[string]string{"id": strconv.Itoa(currentMigration.Id)}
		_, err = runner.RestClient.NextStep(urlParams)
		if err != nil {
			return
		}
	}
	return
}

// renameTablesStep collects the final table stats for a migration, sends them
// to the shift api, and moves the migration to the next step.
func (runner *runner) renameTablesStep(currentMigration *migration.Migration) error {
	// get the lastest state file
	err := runner.createAndRetrieveFiles(currentMigration)
	if err != nil {
		return err
	}

	// the next few steps swap the tables and move the old table to the pending_drops database,
	// where a job will drop the table after a certain amount of time (i.e.,
	// we don't have to worry about it).
	// do the rename
	oldTable, err := SwapOscTables(currentMigration)
	if err != nil {
		return err
	}
	// drop the triggers from the old table
	err = DropTriggers(currentMigration, oldTable)
	if err != nil {
		return err
	}
	// rename old table to pending_drops database.
	// if the pending_drops database is the same as the database for the
	// migration, skip this step.
	if currentMigration.Database != currentMigration.PendingDropsDb {
		err = MoveToPendingDrops(currentMigration, oldTable, oldTable)
		if err != nil {
			return err
		}
	}

	// get the table stats
	tableStatsEnd, err := CollectTableStats(currentMigration)
	if err != nil {
		return err
	}

	// send the table stats to the api
	urlParams := map[string]string{
		"id":             strconv.Itoa(currentMigration.Id),
		"table_rows_end": tableStatsEnd.TableRows,
		"table_size_end": tableStatsEnd.TableSize,
		"index_size_end": tableStatsEnd.IndexSize,
	}
	_, err = runner.RestClient.Update(urlParams)
	if err != nil {
		return err
	}

	// run the final insert
	if currentMigration.FinalInsert != "" {
		err = RunWriteQuery(currentMigration, currentMigration.FinalInsert)
		if err != nil {
			return err
		}
	}

	// complete the migration
	urlParams = map[string]string{"id": strconv.Itoa(currentMigration.Id)}
	_, err = runner.RestClient.Complete(urlParams)
	return err
}

// killPtOscProcess sends a SIGKILL to pt-osc if it is running
func killPtOscProcess(currentMigration *migration.Migration) error {
	runningMigMutex.Lock()
	defer runningMigMutex.Unlock()
	// kill pt-osc if it's running on this host
	if _, exists := runningMigrations[currentMigration.Id]; exists {
		err := killPtOscProcessById(currentMigration.Id)
		if err != nil {
			return err
		}

		delete(runningMigrations, currentMigration.Id)
	} else {
		glog.Infof("mig_id=%d: can't kill because it's not running.", currentMigration.Id)
	}

	return nil
}

// killAllPtOscProcesses sends a SIGKILL to all pt-osc proccess associated
// with running migrations, and returns a list of migration ids of killed processes
func killAllPtOscProcesses() []int {
	killedMigrations := make([]int, 0)
	runningMigMutex.Lock()
	defer runningMigMutex.Unlock()
	for migrationId, _ := range runningMigrations {
		err := killPtOscById(migrationId)
		delete(runningMigrations, migrationId)
		if err != nil {
			glog.Error(err)
			continue
		}
		killedMigrations = append(killedMigrations, migrationId)
	}
	return killedMigrations
}

// killPtOscProcess sends a SIGKILL to the pt-osc process associated
// with the migrationId, does not lock runningMigMutex
func killPtOscProcessById(migrationId int) error {
	pid := runningMigrations[migrationId]
	glog.Infof("mig_id=%d: killing (pid = %d).", migrationId, pid)
	err := syscall.Kill(pid, ptOscKillSignal)
	if err != nil {
		glog.Errorf("mig_id=%d: error killing pt-osc (error: %s)", migrationId, err)
		return ErrPtOscKill
	}

	delete(runningMigrations, migrationId)
	return nil
}

// pauseMigration kills pt-osc if it's running on this host, and bumps the status
// of the migration
func (runner *runner) pauseMigrationStep(currentMigration *migration.Migration) error {
	err := killPtOsc(currentMigration)
	if err != nil {
		return err
	}

	runner.postStateFile(currentMigration)

	// move the migration to the next step
	urlParams := map[string]string{"id": strconv.Itoa(currentMigration.Id)}
	_, err = runner.RestClient.NextStep(urlParams)
	if err != nil {
		return err
	}
	return nil
}

// killMigration kills pt-osc and cleans up after a migration
func (runner *runner) killMigration(currentMigration *migration.Migration) error {
	err := killPtOsc(currentMigration)
	if err != nil {
		return err
	}

	err = runner.createAndRetrieveFiles(currentMigration)
	if err != nil {
		return err
	}

	// we want to clean up the migration (drop triggers, shadow table, etc.) regardless of
	// whether or not the migration is running on this host (or running at all)
	glog.Infof("mig_id=%d: cleaning up.", currentMigration.Id)
	err = CleanUp(currentMigration)
	if err != nil {
		glog.Errorf("mig_id=%d: error cleaning up (error: %s)", currentMigration.Id, err)
		return ErrPtOscCleanUp
	}

	return nil
}

// setupLogWriter configures a writer pointed at the pt-osc log file we want
func setupLogWriter(logFilePath string) (*os.File, *bufio.Writer, error) {
	var logFile *os.File
	if _, err := os.Stat(logFilePath); err == nil {
		logFile, err = os.OpenFile(logFilePath, os.O_APPEND|os.O_WRONLY, 0600)
		if err != nil {
			return nil, nil, ErrGeneral
		}
	} else {
		logFile, err = os.Create(logFilePath)
	}
	return logFile, bufio.NewWriter(logFile), nil
}

// function type for writing to a writer
type writeToWriter func(*bufio.Writer, string, time.Time) error

// writeToPtOscLog takes log lines it receives from a channel and passes them
// to a function that will write them
// Also writes to a buffer which is POSTed to append_to_file when a new log line appears
// after LogSyncInterval seconds
func (runner *runner) writeToPtOscLog(ptOscLogWriter *bufio.Writer, ptOscLogChan chan string, writerFunc writeToWriter, migrationId int, waitGroup *sync.WaitGroup) {
	defer fileSyncWaitGroup.Done()
	defer waitGroup.Done()
	var buffer bytes.Buffer
	lastPostTime := time.Unix(0, 0)
	for line := range ptOscLogChan {
		currentTime := time.Now().Local()
		formattedLine := "[" + currentTime.Format("2006-01-02 15:04:05") + "] " + line
		err := writerFunc(ptOscLogWriter, formattedLine, currentTime)
		if err != nil {
			glog.Errorf("Error flushing pt-osc log file (error: %s)", err)
		}
		_, err = buffer.WriteString(formattedLine + "\n")
		if err != nil {
			glog.Errorf("Error writing to log buffer (error: %s)", err)
		}

		if int(currentTime.Sub(lastPostTime)/time.Second) >= runner.LogSyncInterval && buffer.Len() > 0 {
			err = runner.postLogToFileApi(&buffer, migrationId)
			if err == nil {
				lastPostTime = currentTime
			}
		}
	}
	glog.Infof("Stopped syncing log file")
	runner.postLogToFileApi(&buffer, migrationId)
}

// postLogToFileApi POSTs the lines in buffer to append_to_file as a log file then clears the buffer
func (runner *runner) postLogToFileApi(buffer *bytes.Buffer, migrationId int) error {
	if buffer.Len() == 0 {
		return nil
	}
	urlParams := make(map[string]string)
	urlParams["migration_id"] = strconv.Itoa(migrationId)
	urlParams["file_type"] = LOG_FILE_TYPE
	urlParams["contents"] = buffer.String()
	_, err := runner.RestClient.AppendToFile(urlParams)
	if err != nil {
		glog.Errorf("Error POSTing to append_to_file endpoint (error: %s)", err)
		return err
	}
	buffer.Reset()
	glog.Infof("Sent log lines to append_to_file endpoint")
	return nil
}

// writeLineToPtOscLog writes a single line to a log file
func writeLineToPtOscLog(ptOscLogWriter *bufio.Writer, logMsg string, currentTime time.Time) error {
	glog.Infof("pt-osc output: %s", logMsg)
	fmt.Fprintln(ptOscLogWriter, logMsg)
	return ptOscLogWriter.Flush()
}

// syncStateFile periodically reads a migration's statefile and sends it to the api
func (runner *runner) syncStateFile(migration *migration.Migration, quit chan string, waitGroup *sync.WaitGroup) {
	defer fileSyncWaitGroup.Done()
	defer waitGroup.Done()
	lastPostTime := time.Unix(0, 0)
	for {
		currentTime := time.Now().Local()
		select {
		case <-quit:
			glog.Infof("Stopped syncing state file")
			runner.postStateFile(migration)
			return
		default:
			if int(currentTime.Sub(lastPostTime)/time.Second) >= runner.StateSyncInterval {
				lastPostTime = currentTime
				runner.postStateFile(migration)
			}
			time.Sleep(1 * time.Second)
		}
	}
}

func (runner *runner) postStateFile(migration *migration.Migration) {
	data, err := migration.ReadStateFile()
	if err != nil {
		glog.Warningf("Could not read state file (%s)", err)
	} else {
		urlParams := make(map[string]string)
		urlParams["migration_id"] = strconv.Itoa(migration.Id)
		urlParams["file_type"] = STATE_FILE_TYPE
		urlParams["contents"] = string(data[:])

		_, err = runner.RestClient.WriteFile(urlParams)
		if err != nil {
			glog.Errorf("Error POSTing to write_file endpoint (error: %s)", err)
		} else {
			glog.Infof("Sent state file to write_file endpoint")
		}
	}
}

// function type for generating exec command options
type commandOptionGenerator func(*migration.Migration) (commandOptions []string)

// generatePtOscCommand generates the options for running the pt-osc command.
// there are different options for different steps
func (runner *runner) generatePtOscCommand(currentMigration *migration.Migration) (commandOptions []string) {
	// turn "Alter table t1 add column...." into "add column..."
	alterPrefixRegex := regexp.MustCompile("^(?i)(ALTER\\s+TABLE\\s+.*?\\s+)")
	alterStatement := alterPrefixRegex.ReplaceAllLiteralString(currentMigration.DdlStatement, "")

	// set options that don't exist with the defaults
	var customOptions map[string]string
	defaultOptions := map[string]string{
		"max_threads_running": "200",
		"max_replication_lag": "1",
		"config_path":         "",
		"recursion_method":    "",
	}
	if currentMigration.CustomOptions == nil {
		customOptions = defaultOptions
	} else {
		customOptions = currentMigration.CustomOptions
		for k, v := range defaultOptions {
			if _, ok := customOptions[k]; !ok {
				customOptions[k] = v
			}
		}
	}

	dsn := fmt.Sprintf("D=%s,t=%s", currentMigration.Database, currentMigration.Table)
	commandOptions = make([]string, 0)

	if currentMigration.Status == migration.PrepMigrationStatus {
		commandOptions = append(commandOptions, "--alter", alterStatement, "--dry-run",
			"-h", currentMigration.Host, "-P", strconv.Itoa(currentMigration.Port),
			"--defaults-file", runner.MysqlDefaultsFile, dsn)
	} else if currentMigration.Status == migration.RunMigrationStatus {
		// specify config file if it is defined. Options specified via command line will overwrite
		// ones specified in the config file
		if len(customOptions["config_path"]) > 0 {
			commandOptions = append(commandOptions, "--config", customOptions["config_path"])
		} else {
			commandOptions = append(commandOptions,
				"--max-load", "Threads_running=125",
				"--critical-load", "Threads_running="+customOptions["max_threads_running"],
				"--tries", "create_triggers:200:1,copy_rows:10000:1",
				"--max-lag", customOptions["max_replication_lag"],
				"--set-vars", "wait_timeout=600,lock_wait_timeout=1")
		}

		commandOptions = append(commandOptions, "--alter", alterStatement, "--execute",
			"-h", currentMigration.Host, "-P", strconv.Itoa(currentMigration.Port),
			"--defaults-file", runner.MysqlDefaultsFile, "--progress", ptOscProgress, "--exit-at", "copy",
			"--save-state", currentMigration.StateFile)

		// if the statefile already exists, we must be resuming the migration. load
		// up the previous state
		if _, err := os.Stat(currentMigration.StateFile); err == nil {
			commandOptions = append(commandOptions, "--load-state", currentMigration.StateFile)
		}

		if currentMigration.RunType == migration.NOCHECKALTER_RUN {
			commandOptions = append(commandOptions, "--nocheck-alter")
		}

		if len(customOptions["recursion_method"]) > 0 {
			commandOptions = append(commandOptions, "--recursion-method", customOptions["recursion_method"])
		}

		commandOptions = append(commandOptions, dsn)
	}
	return
}

// createAndRetrieveFiles attempts to create a migration's state file,
// if it does not exist, and retrieve the latest version from the api
func (runner *runner) createAndRetrieveFiles(currentMigration *migration.Migration) error {
	if _, err := os.Stat(currentMigration.FilesDir); err != nil {
		if os.IsNotExist(err) {
			err := os.Mkdir(currentMigration.FilesDir, 0777)
			if err != nil {
				glog.Errorf("mig_id=%d: error creating pt-osc log directory '%s' (error: %s)", currentMigration.Id, currentMigration.FilesDir, err)
				return ErrFiles
			}
		} else {
			glog.Errorf("mig_id=%d: error stat-ing pt-osc log directory '%s' (error: %s)", currentMigration.Id, currentMigration.FilesDir, err)
			return ErrFiles
		}
	}

	// try to retrieve a statefile from the api
	urlParams := map[string]string{
		"migration_id": strconv.Itoa(currentMigration.Id),
		"file_type":    STATE_FILE_TYPE,
	}
	stateFile, restErr := runner.RestClient.GetFile(urlParams)
	if restErr == nil && stateFile["contents"] != nil && len(stateFile["contents"].(string)) > 0 {
		err := currentMigration.WriteStateFile([]byte(stateFile["contents"].(string)))
		if err != nil {
			glog.Errorf("mig_id=%d: error writing to statefile '%s' (error: %s)", currentMigration.Id, currentMigration.StateFile, err)
			return ErrFiles
		}
	}
	return nil
}

// execPtOsc shells out and uses pt-osc to actually run a migration.
func (runner *runner) execPtOsc(currentMigration *migration.Migration,
	ptOscOptionGenerator commandOptionGenerator, copyPercentChan chan int, unstageDone bool) (bool, error) {

	// unstageDone = whether or not unstagedMigrationsWaitGroup has already had .Done() called on it
	defer func() {
		if !unstageDone {
			unstagedMigrationsWaitGroup.Done()
		}
	}()
	canceled := false

	var fileRoutineWaitGroup sync.WaitGroup

	err := runner.createAndRetrieveFiles(currentMigration)
	if err != nil {
		return canceled, err
	}

	ptOscLogFile, ptOscLogWriter, err := setupLogWriter(currentMigration.LogFile)
	if err != nil {
		glog.Errorf("mig_id=%d: error creating pt-osc log file '%s' (error: %s)", currentMigration.Id, currentMigration.LogFile, err)
		return canceled, ErrPtOscExec
	}
	defer ptOscLogFile.Close()

	// generate the pt-osc command to run
	commandOptions := ptOscOptionGenerator(currentMigration)
	glog.Infof("mig_id=%d: Running %s %v", currentMigration.Id, runner.PtOscPath, strings.Join(commandOptions, " "))
	cmd := exec.Command(runner.PtOscPath, commandOptions...)

	// capture stdout and stderr of the command
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		glog.Errorf("mig_id=%d: error getting stdout pipe for pt-osc exec (error: %s)", currentMigration.Id, err)
		return canceled, ErrPtOscExec
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		glog.Errorf("mig_id=%d: error getting stderr pipe for pt-osc exec (error: %s)", currentMigration.Id, err)
		return canceled, ErrPtOscExec
	}

	// start the pt-osc comand
	if err := cmd.Start(); err != nil {
		glog.Errorf("mig_id=%d: error starting pt-osc exec (error: %s)", currentMigration.Id, err)
		return canceled, ErrPtOscExec
	}

	// setup a channel and goroutine for logging output of stdout/stderr
	ptOscLogChan := make(chan string)
	fileRoutineWaitGroup.Add(1)
	fileSyncWaitGroup.Add(1)
	go runner.writeToPtOscLog(ptOscLogWriter, ptOscLogChan, writeLineToPtOscLog, currentMigration.Id, &fileRoutineWaitGroup)

	// setup a goroutine for sending statefiles to the api
	ptOscStateFileChan := make(chan string)
	fileRoutineWaitGroup.Add(1)
	fileSyncWaitGroup.Add(1)
	go runner.syncStateFile(currentMigration, ptOscStateFileChan, &fileRoutineWaitGroup)

	// setup goroutines for watching stdout/stderr of the command
	stdoutErrChan := make(chan error)
	stderrErrChan := make(chan error)
	go currentMigration.WatchMigrationStdout(stdout, stdoutErrChan, ptOscLogChan)
	if currentMigration.Status == migration.RunMigrationStatus {
		// setup a goroutine to continually update the % copied of the migration
		fileRoutineWaitGroup.Add(1)
		fileSyncWaitGroup.Add(1)
		go runner.updateMigrationCopyPercentage(currentMigration, copyPercentChan, &fileRoutineWaitGroup)
		go currentMigration.WatchMigrationCopyStderr(stderr, copyPercentChan, stderrErrChan, ptOscLogChan)
	} else {
		go currentMigration.WatchMigrationStderr(stderr, stderrErrChan, ptOscLogChan)
	}

	// save the pid of the pt-osc process
	currentMigration.Pid = cmd.Process.Pid
	glog.Infof("mig_id=%d: pt-osc pid for status %d is %d.", currentMigration.Id, currentMigration.Status, currentMigration.Pid)

	// add the migration id and pid to the running migration map
	runningMigMutex.Lock()
	runningMigrations[currentMigration.Id] = currentMigration.Pid
	runningMigMutex.Unlock()
	if !unstageDone {
		unstageDone = true
		unstagedMigrationsWaitGroup.Done()
	}

	// wait for both stdout and stderr error channels to receive a signal
	stdoutErr := <-stdoutErrChan
	stderrErr := <-stderrErrChan
	close(ptOscLogChan)
	close(ptOscStateFileChan)

	// remove the migration id from the running migration map
	runningMigMutex.Lock()
	delete(runningMigrations, currentMigration.Id)
	runningMigMutex.Unlock()

	// get the exit status of the command. if it was sent a SIGKILL (most likely
	// by another goroutine) we want to know because we will treat it differently
	failed := false
	if err := cmd.Wait(); err != nil {
		if exiterr, ok := err.(*exec.ExitError); ok {
			if status, ok := exiterr.Sys().(syscall.WaitStatus); ok {
				exitSignal := status.Signal().String()
				glog.Infof("mig_id=%d: exit signal was %s.", currentMigration.Id, exitSignal)
				if (exitSignal == SIGKILLSignal) && (currentMigration.Status == migration.RunMigrationStatus) {
					// was killed
					glog.Infof("mig_id=%d: migration must have been canceled", currentMigration.Id)
					canceled = true
				} else if currentMigration.Status == migration.RunMigrationStatus {
					// died for an unexpected reason
					glog.Infof("mig_id=%d: migration died for an unexpected reason", currentMigration.Id)
					failed = true
				}
			}
		}
	} else {
		if (stderrErr == nil) && (currentMigration.Status == migration.RunMigrationStatus) {
			// wasn't killed. copy completed 100%
			glog.Infof("mig_id=%d: updating migration with copy percentage of 100", currentMigration.Id)
			copyPercentChan <- 100
		}
	}

	if copyPercentChan != nil {
		glog.Infof("Closing copy percent channel")
		close(copyPercentChan)
	}

	fileRoutineWaitGroup.Wait() // wait for go routines to finish

	// favor returning error from unexpected failure, then error from stderr,
	// and lastly error from stdout
	if failed {
		return canceled, ErrUnexpectedExit
	} else if stderrErr != nil {
		return canceled, stderrErr
	} else if stdoutErr != nil {
		return canceled, stdoutErr
	}

	return canceled, nil
}

// updateMigrationCopyPercentage watches a channel for a running migration and
// sends the copy percentage completed (from the channel) to the shift api
func (runner *runner) updateMigrationCopyPercentage(currentMigration *migration.Migration, copyPercentChan chan int, waitGroup *sync.WaitGroup) {
	defer fileSyncWaitGroup.Done()
	defer waitGroup.Done()
	migrationId := strconv.Itoa(currentMigration.Id)
	for copyPercentage := range copyPercentChan {
		// send the table stats to the api
		urlParams := map[string]string{
			"id":              migrationId,
			"copy_percentage": strconv.Itoa(copyPercentage),
		}
		_, err := runner.RestClient.Update(urlParams)
		if err != nil {
			glog.Errorf("mig_id=%d: error updating copy percentage (error: %s). Continuing anyway", migrationId, err)
		}
	}
}

func Start(configFile string) error {
	migrationRunner, err := newRunner(configFile)
	if err != nil {
		glog.Errorf("Error creating migration runner (error: %s).", err)
		return err
	}

	jobChannel := make(chan *migration.Migration)

	go migrationRunner.watchForStopFile()

	go migrationRunner.sendRunnableMigrationsToProcessor(jobChannel)

	for job := range jobChannel {
		go migrationRunner.processMigration(job)
	}

	return nil
}
