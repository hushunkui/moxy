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
	log.Printf("Downloading: %s\n", output)
	l, err := io.Copy(f, resp.Body)
	if l != resp.ContentLength {
		return fmt.Errorf("Expected ContentLength(%d) actually read(%d)", resp.ContentLength, l)
	}
	log.Printf("Wrote: %d bytes\n", l)
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

	// Download and parse the nextboot configuration.
	nextboot := tmp("nextboot")
	log.Printf("%s -> %s\n", *url, nextboot.Name())
	err := Download(client, *url, nextboot.Name())
	if err != nil {
		log.Fatal(err)
	}
	// defer os.Remove(nextboot.Name())

        // Load the configuration.
	n, err := Load(nextboot.Name())
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("%s\n", n.String())

	// Download the vmlinuz and initramfs images.
	vmlinuz := tmp("vmlinuz")
	err = Download(client, n.Kernel.Vmlinuz, vmlinuz.Name())
	if err != nil {
		log.Fatal(err)
	}
	// defer os.Remove(vmlinuz.Name())

	initramfs := tmp("initramfs")
	err = Download(client, n.Kernel.Initramfs, initramfs.Name())
	if err != nil {
		log.Fatal(err)
	}
	// defer os.Remove(initramfs.Name())

	// Save local temporary file names for evaluating command template.
	k := KernelSource{
	        Vmlinuz: vmlinuz.Name(),
	        Initramfs: initramfs.Name(),
		Kargs: n.Kernel.Kargs,
	}

        // Parse command as a template.
	tmpl, err := template.New("name").Parse(n.Command)
	if err != nil {
		log.Fatal(err)
	}
	var b bytes.Buffer
	err = tmpl.Execute(&b, k)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("b: %s\n", string(b.Bytes()))
}
