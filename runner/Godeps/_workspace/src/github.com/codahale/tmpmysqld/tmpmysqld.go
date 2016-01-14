// Package tmpmysql provides the ability to spin up temporary mysqld instances
// for testing purposes.
package tmpmysql

import (
	"bytes"
	"database/sql"
	"fmt"
	"os/exec"
	"path/filepath"
	"time"

	_ "github.com/square/shift/runner/Godeps/_workspace/src/github.com/go-sql-driver/mysql" // load MySQL driver
	"io/ioutil"
	"os"
	"syscall"
)

// IsMySQLInstalled returns true if the various required components of MySQL are
// available.
//
// tmpmysqld requires mysqld, mysql_install_db, and mysql_config to be on the
// path of the running process.
func IsMySQLInstalled() bool {
	if err := exec.Command("mysqld", "--version").Run(); err == exec.ErrNotFound {
		return false
	}

	if err := exec.Command("mysql_install_db", "--verbose", "--help").Run(); err == exec.ErrNotFound {
		return false
	}

	if err := exec.Command("mysql_config", "--version").Run(); err == exec.ErrNotFound {
		return false
	}

	return true
}

// A MySQLServer is a temporary instance of mysqld.
type MySQLServer struct {
	dataDir string
	mysqld  *exec.Cmd

	DB *sql.DB
}

// NewMySQLServer returns a new mysqld instance running on the given port, with
// the given database created and selected as the current database.
func NewMySQLServer(name string) (*MySQLServer, error) {
	baseDir, err := getBaseDir()
	if err != nil {
		return nil, err
	}

	dataDir, err := ioutil.TempDir(os.TempDir(), "tmpmysql")
	if err != nil {
		return nil, err
	}

	if err := installDB(baseDir, dataDir); err != nil {
		return nil, err
	}

	f, err := ioutil.TempFile(os.TempDir(), "tmpmysqld.sock")
	if err != nil {
		return nil, err
	}
	sockPath := f.Name()
	_ = f.Close()

	mysqld := exec.Command(
		"mysqld",
		"--no-defaults",
		"--skip-networking",
		"--datadir="+dataDir,
		"--socket="+sockPath,
	)

	if err := mysqld.Start(); err != nil {
		return nil, err
	}

	s := MySQLServer{
		mysqld:  mysqld,
		dataDir: dataDir,
	}

	dsn := fmt.Sprintf("root:@unix(%s)/", sockPath)
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		_ = s.Stop()
		return nil, err
	}

	s.DB = db

	// wait until the DB is available
	for db.Ping() != nil {
		time.Sleep(50 * time.Millisecond)
	}

	if _, err := db.Exec("CREATE DATABASE " + name); err != nil {
		_ = s.Stop()
		return nil, err
	}

	if _, err := db.Exec("USE " + name); err != nil {
		_ = s.Stop()
		return nil, err
	}

	return &s, nil
}

// Stop terminates the mysqld instance and deletes the temporary directory which
// contains the database files.
func (s *MySQLServer) Stop() error {
	if s.mysqld == nil {
		panic("already stopped")
	}

	if s.DB != nil { // might not be initialized
		if err := s.DB.Close(); err != nil {
			return err
		}
	}

	if err := s.mysqld.Process.Signal(syscall.SIGTERM); err != nil {
		return err
	}

	if err := s.mysqld.Wait(); err != nil {
		return err
	}

	s.mysqld = nil

	return os.RemoveAll(s.dataDir)
}

func installDB(baseDir, dataDir string) error {
	cmd := exec.Command(
		"mysql_install_db",
		"--no-defaults",
		"--skip-name-resolve",
		"--basedir="+baseDir,
		"--datadir="+dataDir,
	)
	return cmd.Run()
}

func getBaseDir() (string, error) {
	buf := bytes.NewBuffer(nil)
	cmd := exec.Command("mysql_config", "--variable=pkglibdir")
	cmd.Stdout = buf
	if err := cmd.Run(); err != nil {
		return "", err
	}
	return filepath.Abs(buf.String() + "/../")
}
