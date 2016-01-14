// Package rest facilitates interaction with the shift REST api.
package rest

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
)

var (
	// define errors
	ErrStaged        = errors.New("rest: error getting staged migrations")
	ErrUnstage       = errors.New("rest: error unstaging migration")
	ErrUnstageStolen = errors.New("rest: another runner picked up the migration before we could unstage it")
	ErrNextStep      = errors.New("rest: error moving migration to next step")
	ErrUpdate        = errors.New("rest: error updating migration")
	ErrComplete      = errors.New("rest: error completing migration")
	ErrCancel        = errors.New("rest: error canceling migration")
	ErrFail          = errors.New("rest: error failing migration")
	ErrError         = errors.New("rest: error error-ing out migration")
)

// restClient contains the http client used to talk to the REST api,
// as well as the endpoint where the api is located.
type restClient struct {
	Client *http.Client
	api    string
}

type RestResponseItem map[string]interface{}
type RestResponseItems []RestResponseItem

// New initializes a new restClient based on parameters that are
// passed to it.
func New(api, cert, key string) (*restClient, error) {
	restClient := new(restClient)

	restClient.api = api

	//Create HTTP client
	var client *http.Client
	useSsl := strings.HasPrefix(api, "https://")
	if useSsl == true {
		sslCert, err := tls.LoadX509KeyPair(cert, key)
		if err != nil {
			return restClient, err
		}

		tlsConfig := &tls.Config{
			Certificates:       []tls.Certificate{sslCert},
			InsecureSkipVerify: true,
		}

		transport := &http.Transport{
			TLSClientConfig: tlsConfig,
		}

		client = &http.Client{Transport: transport}
	} else {
		client = &http.Client{}
	}
	restClient.Client = client

	return restClient, nil
}

// get makes an http "GET" request with restClient.
func (restClient *restClient) get(resource string) (RestResponseItems, error) {
	client := restClient.Client
	api := restClient.api
	url := api + resource

	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	// Parse the response into JSON
	decoder := json.NewDecoder(resp.Body)
	var response RestResponseItems
	if err = decoder.Decode(&response); err != nil {
		return nil, err
	}
	return response, nil
}

// post makes an http "POST" request with restClient.
func (restClient *restClient) post(resource string, urlParams map[string]string) (RestResponseItem, error) {
	client := restClient.Client
	api := restClient.api
	url := api + resource

	data, err := json.Marshal(urlParams)
	if err != nil {
		return nil, err
	}

	resp, err := client.Post(url, "application/json", bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	// Parse the response into JSON
	decoder := json.NewDecoder(resp.Body)
	var response map[string]interface{}
	if err = decoder.Decode(&response); err != nil {
		return nil, err
	}
	return response, nil
}

// put makes an http "PUT" request with restClient.
func (restClient *restClient) put(resource string, urlParams map[string]string) (RestResponseItem, error) {
	client := restClient.Client
	api := restClient.api

	// Take id out of the url params map and put it into the url (required for PUT requests in rails)
	id, ok := urlParams["id"]
	if ok == false {
		return nil, errors.New("PUT request requires 'id' in url params.")
	}
	delete(urlParams, "id")
	url := api + resource + "/" + id

	data, err := json.Marshal(urlParams)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest("PUT", url, bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	req.Header.Add("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	// Parse the response into JSON
	decoder := json.NewDecoder(resp.Body)
	var response map[string]interface{}
	if err = decoder.Decode(&response); err != nil {
		return nil, err
	}
	return response, nil
}

// Staged gets an array of staged migrations.
func (restClient *restClient) Staged() (RestResponseItems, error) {
	resource := "migrations/staged"
	response, err := restClient.get(resource)
	if err != nil {
		return response, ErrStaged
	}
	return response, nil
}

// Unstage unstages a migration.
func (restClient *restClient) Unstage(params map[string]string) (RestResponseItem, error) {
	resource := "migrations/unstage"
	response, err := restClient.post(resource, params)
	if err != nil {
		return nil, ErrUnstage
	}
	if _, ok := response["id"]; ok {
		return response, nil
	} else {
		return nil, ErrUnstageStolen
	}
}

// NextStep moves a migration to the next step.
func (restClient *restClient) NextStep(params map[string]string) (RestResponseItem, error) {
	resource := "migrations/next_step"
	response, err := restClient.post(resource, params)
	if err != nil {
		return nil, ErrNextStep
	}
	return response, nil
}

// Update updates fields of a migration.
func (restClient *restClient) Update(params map[string]string) (RestResponseItem, error) {
	resource := "migrations"
	response, err := restClient.put(resource, params)
	if err != nil {
		return nil, ErrUpdate
	}
	return response, nil
}

// Complete completes a migration.
func (restClient *restClient) Complete(params map[string]string) (RestResponseItem, error) {
	resource := "migrations/complete"
	response, err := restClient.post(resource, params)
	if err != nil {
		return nil, ErrComplete
	}
	return response, nil
}

// Cancel cancels a migration.
func (restClient *restClient) Cancel(params map[string]string) (RestResponseItem, error) {
	resource := "migrations/cancel"
	response, err := restClient.post(resource, params)
	if err != nil {
		return nil, ErrCancel
	}
	return response, nil
}

// Fail updates a failed migration with an error message.
func (restClient *restClient) Fail(params map[string]string) (RestResponseItem, error) {
	resource := "migrations/fail"
	response, err := restClient.post(resource, params)
	if err != nil {
		return nil, ErrFail
	}
	return response, nil
}

// Error errors out a migration.
func (restClient *restClient) Error(params map[string]string) (RestResponseItem, error) {
	resource := "migrations/error"
	response, err := restClient.post(resource, params)
	if err != nil {
		return nil, ErrError
	}
	return response, nil
}
