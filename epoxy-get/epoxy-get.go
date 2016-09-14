package main

import (
	"crypto/tls"
	// "crypto/x509"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"text/template"
)

var (
	url    = flag.String("url", "https://127.0.0.1:8081/", "The https url to get.")
	output = flag.String("o", "", "The output file name.")
)

type KernelSource struct {
	Vmlinuz   string // Source file.
	Initramfs string // NextbootEnabled indicates whether ePoxy returns the NextbootScriptName or DefaultScriptName.
	Kargs     string
}

type FallbackSource struct {
	Source  string // Source file.
	Extract string // Command to extract source file.
}

type Nextboot struct {
	Kernel    *KernelSource
	Fallback  *FallbackSource
	Command   string
	SessionId string
}

func (n *Nextboot) String() string {
	// Errors only occur for non-UTF8 characters in strings.
	// AddHostInformation checks that strings are valid utf8.
	b, _ := json.MarshalIndent(n, "", "    ")
	return string(b)
}

func tmp(name string) *os.File {
	t, err := ioutil.TempFile("", name)
	if err != nil {
		log.Fatal(err)
	}
	return t
}

func Load(input string) (*Nextboot, error) {
	b, err := ioutil.ReadFile(input)
	if err != nil {
		return nil, err
	}
	n := &Nextboot{}
	err = json.Unmarshal(b, n)
	if err != nil {
		return nil, err
	}
	return n, nil
}

func Download(client *http.Client, url, output string) error {
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// Dump response
	f, err := os.Create(output)
	if err != nil {
		return err
	}
	l, err := io.Copy(f, resp.Body)
	if l != resp.ContentLength {
		return fmt.Errorf("Expected ContentLength(%d) actually read(%d)", resp.ContentLength, l)
	}
	fmt.Printf("Wrote: %d\n", l)
	return nil
}

func main() {
	flag.Parse()
	// if *output == "" {
	//      log.Fatal("Specify the output file name: -o <filename>")
	// }
	// fmt.Printf("%s -> %s\n", *url, *output)

	// certPool, err := x509.SystemCertPool()
	// if err != nil {
	//     log.Fatal(err)
	// }

	// Setup HTTPS client
	tlsConfig := &tls.Config{
		// RootCAs:      certPool,
		MinVersion: tls.VersionTLS10,
	}
	tlsConfig.BuildNameToCertificate()
	transport := &http.Transport{TLSClientConfig: tlsConfig}
	client := &http.Client{Transport: transport}

	t := tmp("nextboot")
	fmt.Printf("%s -> %s\n", *url, t.Name())
	err := Download(client, *url, t.Name())
	if err != nil {
		log.Fatal(err)
	}
	n, err := Load(*output)
	if err != nil {
		log.Fatal(err)
	}

	k := KernelSource{
		Kargs: n.Kernel.Kargs,
	}
	t = tmp("vmlinuz")
	k.Vmlinuz = t.Name()
	err = Download(client, n.Kernel.Vmlinuz, t.Name())
	if err != nil {
		log.Fatal(err)
	}

	t = tmp("initramfs")
	k.Initramfs = t.Name()
	// TODO(change variable):
	err = Download(client, n.Kernel.Vmlinuz, t.Name())
	if err != nil {
		log.Fatal(err)
	}

	var b bytes.Buffer
	fmt.Printf("%s\n", n.String())
	tmpl, err := template.New("name").Parse(n.Command)
	if err != nil {
		log.Fatal(err)
	}
	err = tmpl.Execute(&b, k)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("b: %s\n", string(b.Bytes()))
}
