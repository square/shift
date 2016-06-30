package rest

type RestClient interface {
	// Makes a GET request to the shift api at "/staged".
	// Returns result as array of mappings of strings to interfaces
	// where each map in the array represents a migration, and each
	// migration contains keys and values describing all of the fields
	// of a migration.
	Staged() (RestResponseItems, error)

	// Makes a POST request to the shift api at "/unstage".
	// Returns result as map of strings to interfaces, where keys and
	// values describe all of the fields of a migration.
	Unstage(params map[string]string) (RestResponseItem, error)

	// Makes a POST request to the shift api at "/next_step".
	// Returns result as map of strings to interfaces, where keys and
	// values describe all of the fields of a migration.
	NextStep(params map[string]string) (RestResponseItem, error)

	// Makes a PUT request to the shift api at "/{id}".
	// Returns result as map of strings to interfaces, where keys and
	// values describe all of the fields of a migration.
	Update(params map[string]string) (RestResponseItem, error)

	// Makes a POST request to the shift api at "/complete".
	// Returns result as map of strings to interfaces, where keys and
	// values describe all of the fields of a migration.
	Complete(params map[string]string) (RestResponseItem, error)

	// Makes a POST request to the shift api at "/cancel".
	// Returns result as map of strings to interfaces, where keys and
	// values describe all of the fields of a migration.
	Cancel(params map[string]string) (RestResponseItem, error)

	// Makes a POST request to the shift api at "/fail".
	// Returns result as map of strings to interfaces, where keys and
	// values describe all of the fields of a migration.
	Fail(params map[string]string) (RestResponseItem, error)

	// Makes a POST request to the shift api at "/error".
	// Returns result as map of strings to interfaces, where keys and
	// values describe all of the fields of a migration.
	Error(params map[string]string) (RestResponseItem, error)

	// Makes a POST request to the shift api at "/offer".
	// Returns result as map of strings to interfaces, where keys and
	// values describe all of the fields of a migration
	Offer(params map[string]string) (RestResponseItem, error)

	// Makes a POST request to the shift api at "/unpin_run_host".
	// Returns result as map of strings to interfaces, where keys and
	// values describe all of the fields of a migration
	UnpinRunHost(params map[string]string) (RestResponseItem, error)

	// Makes a POST request to the shift api at "/append_to_file".
	// Returns result as map of strings to interfaces, where keys and
	// values describe all of the fields of the file minus the contents
	AppendToFile(params map[string]string) (RestResponseItem, error)

	// Makes a POST request to the shift api at "/write_file".
	// Returns result as map of strings to interfaces, where keys and
	// values describe all of the fields of the file minus the contents
	WriteFile(params map[string]string) (RestResponseItem, error)

	// Makes a GET request to the shift api at "/get_file".
	// Returns result as map of strings to interfaces, where keys and
	// values describe aff of the fields of the file including the contents
	GetFile(params map[string]string) (RestResponseItem, error)
}
