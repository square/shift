// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.
package testUtils

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"math/big"
	"net"
	"os"
	"strings"
	"time"
)

// Generate a self-signed X.509 certificate for a TLS server. Outputs to
// 'cert.pem' and 'key.pem' and will overwrite existing files.
func GenerateCert(host, validFrom *string, validFor *time.Duration, isCA *bool, rsaBits *int) (certName, keyName string) {
	if len(*host) == 0 {
		log.Fatalf("Host can't be empty")
	}

	priv, err := rsa.GenerateKey(rand.Reader, *rsaBits)
	if err != nil {
		log.Fatalf("failed to generate private key: %s", err)
	}

	var notBefore time.Time
	if len(*validFrom) == 0 {
		notBefore = time.Now()
	} else {
		notBefore, err = time.Parse("Jan 2 15:04:05 2006", *validFrom)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to parse creation date: %s\n", err)
			os.Exit(1)
		}
	}

	notAfter := notBefore.Add(*validFor)

	serialNumberLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serialNumber, err := rand.Int(rand.Reader, serialNumberLimit)
	if err != nil {
		log.Fatalf("failed to generate serial number: %s", err)
	}

	template := x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			Organization: []string{"Acme Co"},
		},
		NotBefore: notBefore,
		NotAfter:  notAfter,

		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}

	hosts := strings.Split(*host, ",")
	for _, h := range hosts {
		if ip := net.ParseIP(h); ip != nil {
			template.IPAddresses = append(template.IPAddresses, ip)
		} else {
			template.DNSNames = append(template.DNSNames, h)
		}
	}

	if *isCA {
		template.IsCA = true
		template.KeyUsage |= x509.KeyUsageCertSign
	}

	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	if err != nil {
		log.Fatalf("Failed to create certificate: %s", err)
	}

	certOut, err := ioutil.TempFile(os.TempDir(), "cert")
	if err != nil {
		log.Fatalf("failed to open cert.pem for writing: %s", err)
	}
	pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: derBytes})
	certOut.Close()

	keyOut, err := ioutil.TempFile(os.TempDir(), "key")
	if err != nil {
		log.Print("failed to open key.pem for writing:", err)
		return
	}
	err = os.Chmod(keyOut.Name(), 0600)
	if err != nil {
		log.Print("failed to chmod key.pem to 0600:", err)
		return
	}

	pem.Encode(keyOut, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(priv)})
	keyOut.Close()

	return certOut.Name(), keyOut.Name()
}

var (
	TestQueryCol   = map[string][]string{}
	FailQuery      int
	ErrQueryFailed = errors.New("query failed")
)

// stub a database client
type StubDbClient struct {
	Host   string
	UseTls bool
}

func (StubDbClient *StubDbClient) QueryReturnColumnDict(query string, args ...interface{}) (map[string][]string, error) {
	if FailQuery == 1 {
		return nil, ErrQueryFailed
	}
	return TestQueryCol, nil
}

func (StubDbClient *StubDbClient) QueryMapFirstColumnToRow(query string, args ...interface{}) (map[string][]string, error) {
	if FailQuery == 1 {
		return nil, ErrQueryFailed
	}
	return TestQueryCol, nil
}

func (StubDbClient *StubDbClient) QueryInsertUpdate(query string, args ...interface{}) error {
	if FailQuery == 1 {
		return ErrQueryFailed
	}
	return nil
}

func (StubDbClient *StubDbClient) ValidateInsertStatement(query string, args ...interface{}) error {
	if FailQuery == 1 {
		return ErrQueryFailed
	}
	return nil
}

func (StubDbClient *StubDbClient) Log(interface{}) {}

func (StubDbClient *StubDbClient) Close() {}
