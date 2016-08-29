package main

import (
	"crypto/tls"
	"crypto/x509"
	"flag"
        "fmt"
	"io"
	//// "io/ioutil"
	"os"
	"log"
	"net/http"
)

var (
	url          = flag.String("url", "https://127.0.0.1:8081/", "The https url to get.")
        output       = flag.String("o", "", "The output file name.")
)

func main() {
	flag.Parse()
        if *output == "" {
               panic("Specify the output file name: -o <filename>")
        }
        fmt.Printf("%s -> %s\n", *url, *output)

	certPool, err := x509.SystemCertPool()
        if err != nil {
                panic(err)
        }

	// Setup HTTPS client
	tlsConfig := &tls.Config{
		RootCAs:      certPool,
                MinVersion:               tls.VersionTLS10,
	}
	tlsConfig.BuildNameToCertificate()
	transport := &http.Transport{TLSClientConfig: tlsConfig}
	client := &http.Client{Transport: transport}

	// Do GET something
	// resp, err := client.PostForm(*url, nil)
	resp, err := client.Get(*url)
	if err != nil {
		log.Fatal(err)
	}
	defer resp.Body.Close()

	// Dump response
	f, err := os.Create(*output)
	if err != nil {
		panic(err)
	}
	l, err := io.Copy(f, resp.Body)
	if err != nil {
		panic(err)
	}
	fmt.Printf("Wrote: %d\n", l)
}
