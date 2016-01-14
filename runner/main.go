package main

import (
	"flag"
	"log"
	"os"

	"github.com/square/shift/runner/pkg/runner"
)

func main() {
	var configFile string

	// parse optional glog flags
	flag.Parse()

	// get the config file, based on environment
	wd, err := os.Getwd()
	if err != nil {
		log.Fatal(err.Error())
		return
	}
	environment := os.Getenv("ENVIRONMENT")
	switch {
	default:
		configFile = wd + "/config/development-config.yaml"
	case environment == "staging":
		configFile = wd + "/config/staging-config.yaml"
	case environment == "production":
		configFile = wd + "/config/production-config.yaml"
	}

	err = runner.Start(configFile)
	if err != nil {
		log.Fatalf("Error creating migration runner (error: %s).", err)
	}
}
