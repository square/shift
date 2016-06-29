package rest

import (
	"encoding/json"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/square/shift/runner/pkg/testutils"
)

var testMigId = "3"

func initMigration() RestResponseItem {
	migration := make(RestResponseItem)
	migration["id"] = testMigId
	migration["status"] = "2"
	migration["staged"] = true
	return migration
}

func initShiftFile() RestResponseItem {
	shiftFile := make(RestResponseItem)
	shiftFile["migration_id"] = testMigId
	shiftFile["file_type"] = "0"
	shiftFile["contents"] = ""
	return shiftFile
}

// when a response doesn't have an "id" field after an unstage, it is considered
// to have been picked up by another runner before we could get a lock ("stolen").
func initMigrationStolen() RestResponseItem {
	migration := make(RestResponseItem)
	migration["status"] = "2"
	migration["staged"] = true
	return migration
}

func initMigrationArray() RestResponseItems {
	migration := make(RestResponseItem)
	migration["id"] = testMigId
	migration["status"] = "2"
	migration["staged"] = true
	var migrationArray []RestResponseItem
	migrationArray = append(migrationArray, migration)
	return migrationArray
}

//launches routine to serve json packages
func initMigrationsJson() {
	_, err := http.Get("http://localhost:12345/api/v1/migrations/staged")
	if err == nil {
		return
	}

	go func() {
		http.HandleFunc("/api/v1/migrations/staged", httpJsonHandlerArray)
		http.HandleFunc("/api/v1/migrations/unstage", httpJsonHandler)
		http.HandleFunc("/api/v1/migrations/fail", httpJsonHandler)
		http.HandleFunc("/api/v1/migrations/error", httpJsonHandler)
		http.HandleFunc("/api/v1/migrations/next_step", httpJsonHandler)
		http.HandleFunc("/api/v1/migrations/complete", httpJsonHandler)
		http.HandleFunc("/api/v1/migrations/cancel", httpJsonHandler)
		http.HandleFunc("/api/v1/migrations/offer", httpJsonHandler)
		http.HandleFunc("/api/v1/migrations/unpin_run_host", httpJsonHandler)
		http.HandleFunc("/api/v1/migrations/"+testMigId, httpJsonHandler)
		http.HandleFunc("/api/v1/migrations/append_to_file", httpJsonHandlerShiftFile)
		http.HandleFunc("/api/v1/migrations/write_file", httpJsonHandlerShiftFile)
		http.HandleFunc("/api/v1/migrations/get_file", httpJsonHandlerShiftFile)
		// stolen migrations
		http.HandleFunc("/api/v1/stolen/migrations/unstage", httpJsonHandlerStolen)
		http.ListenAndServe("localhost:12345", nil)
	}()

	ready := make(chan bool)
	go func() {
		for {
			_, err := http.Get("http://localhost:12345/api/v1/migrations/staged")
			if err == nil {
				ready <- true
				break
			}
		}
	}()
	<-ready
	return
}

// httpJsonHandler setups a handler for exposing a single migration via JSON over HTTP
func httpJsonHandler(w http.ResponseWriter, r *http.Request) {
	migration := initMigration()

	js, err := json.Marshal(migration)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(js)
}

// httpJsonHandlerStolen setups a handler for exposing a single migration via JSON over HTTP
func httpJsonHandlerStolen(w http.ResponseWriter, r *http.Request) {
	migration := initMigrationStolen()

	js, err := json.Marshal(migration)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(js)
}

// httpJsonHandler setups a handler for exposing an array of migrations via JSON over HTTP
func httpJsonHandlerArray(w http.ResponseWriter, r *http.Request) {
	migrationArray := initMigrationArray()

	js, err := json.Marshal(migrationArray)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(js)
}

func httpJsonHandlerShiftFile(w http.ResponseWriter, r *http.Request) {
	shiftFile := initShiftFile()

	js, err := json.Marshal(shiftFile)

	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(js)
}

func TestStagedMigrations(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	response, err := client.Staged()
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedArray := initMigrationArray()
	for k, v := range response[0] {
		actual := v
		expected := expectedArray[0][k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestUnstageMigration(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["id"] = testMigId
	response, err := client.Unstage(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedMigration := initMigration()
	for k, v := range response {
		actual := v
		expected := expectedMigration[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestUnstageMigrationStolen(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/stolen/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["id"] = testMigId
	response, err := client.Unstage(urlParams)
	if err == nil {
		t.Errorf("Expected an error, but didn't get one (migration should have been 'stolen')")
	}

	expectedMigration := initMigrationStolen()
	for k, v := range response {
		actual := v
		expected := expectedMigration[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestNextStepMigration(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["id"] = testMigId
	response, err := client.NextStep(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedMigration := initMigration()
	for k, v := range response {
		actual := v
		expected := expectedMigration[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestUpdateMigration(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["id"] = testMigId
	urlParams["table_size_start"] = "1234"
	response, err := client.Update(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedMigration := initMigration()
	for k, v := range response {
		actual := v
		expected := expectedMigration[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestCompleteMigration(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["id"] = testMigId
	response, err := client.Complete(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedMigration := initMigration()
	for k, v := range response {
		actual := v
		expected := expectedMigration[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestCancelMigration(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["id"] = testMigId
	response, err := client.Cancel(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedMigration := initMigration()
	for k, v := range response {
		actual := v
		expected := expectedMigration[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestFailMigration(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["id"] = testMigId
	urlParams["error"] = "Failed to connect to the database."
	response, err := client.Fail(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedMigration := initMigration()
	for k, v := range response {
		actual := v
		expected := expectedMigration[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestErrorMigration(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["id"] = testMigId
	urlParams["error"] = "Failed to connect to the database."
	response, err := client.Error(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedMigration := initMigration()
	for k, v := range response {
		actual := v
		expected := expectedMigration[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestOfferMigration(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["id"] = testMigId
	response, err := client.Offer(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedMigration := initMigration()
	for k, v := range response {
		actual := v
		expected := expectedMigration[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestUnpinRunHost(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["id"] = testMigId
	response, err := client.UnpinRunHost(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedMigration := initMigration()
	for k, v := range response {
		actual := v
		expected := expectedMigration[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestAppendToFile(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["migration_id"] = testMigId
	urlParams["file_type"] = "0"
	urlParams["contents"] = "test content"
	response, err := client.AppendToFile(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedShiftFile := initShiftFile()
	for k, v := range response {
		actual := v
		expected := expectedShiftFile[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestWriteFile(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["migration_id"] = testMigId
	urlParams["file_type"] = "0"
	urlParams["contents"] = "test content"
	response, err := client.WriteFile(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedShiftFile := initShiftFile()
	for k, v := range response {
		actual := v
		expected := expectedShiftFile[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestGetFile(t *testing.T) {
	initMigrationsJson()

	client, err := New("http://localhost:12345/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}
	urlParams := make(map[string]string)
	urlParams["migration_id"] = testMigId
	urlParams["file_type"] = "1"
	response, err := client.GetFile(urlParams)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedShiftFile := initShiftFile()
	for k, v := range response {
		actual := v
		expected := expectedShiftFile[k]
		if expected != actual {
			t.Errorf("response = %v, want %v", actual, expected)
		}
	}
}

func TestNewClientNoSsl(t *testing.T) {
	client, err := New("http://localhost:3000/api/v1/", "", "")
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedTransport := &http.Transport{}
	var actualTransport *http.Transport
	if client.Client.Transport != nil {
		actualTransport = client.Client.Transport.(*http.Transport)
	} else {
		// Transport is nil, use default transport instead
		actualTransport = http.DefaultTransport.(*http.Transport)
	}

	actualConfig := actualTransport.TLSClientConfig
	expectedConfig := expectedTransport.TLSClientConfig
	if actualConfig != expectedConfig {
		t.Errorf("TLSClientConfig = %v, want %v", actualConfig, expectedConfig)
	}
}

func TestNewClientWithSsl(t *testing.T) {
	// Generate temp cert/key
	hostname, err := os.Hostname()
	if err != nil {
		t.Fatal(err)
	}
	validFrom := ""
	validFor := 365 * 24 * time.Hour
	isCa := true
	rsaBits := 2048
	cert, key := testUtils.GenerateCert(&hostname, &validFrom, &validFor, &isCa, &rsaBits)

	client, err := New("https://localhost:3000/api/v1/", cert, key)
	if err != nil {
		t.Errorf("Unexpected error: %s", err)
	}

	expectedTransport := &http.Transport{}
	var actualTransport *http.Transport
	if client.Client.Transport != nil {
		actualTransport = client.Client.Transport.(*http.Transport)
	} else {
		// Transport is nil, use default transport instead
		actualTransport = http.DefaultTransport.(*http.Transport)
	}

	actualConfig := actualTransport.TLSClientConfig
	expectedConfig := expectedTransport.TLSClientConfig
	if actualConfig == expectedConfig {
		t.Errorf("TLSClientConfig = %v, don't want %v", actualConfig, expectedConfig)
	}

	actualVerify := actualTransport.TLSClientConfig.InsecureSkipVerify
	expectedVerify := true
	if actualVerify != expectedVerify {
		t.Errorf("insecureSkipVerify = %v, want %v", actualVerify, expectedVerify)
	}

	defer os.Remove(cert)
	defer os.Remove(key)
}
