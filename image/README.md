Building images for use with ePoxy.
==


```
./setup_initramfs.sh /build stage2_config
./setup_kernel.sh /build stage2_config
```


Errata
==

* In ubuntu 16.04 the package linux-source-4.4.0-21 fails to build due to:

    https://lkml.org/lkml/2016/7/18/352

* The build of epoxyget from source requires access to the epoxy private repo.
  This can be worked around with ssh agent forwarding, but ultimately will not
  matter b/c the epoxy sources will be open.

## Publish to GCS

    gsutil defacl set public-read gs://epoxy-staging
    gsutil rsync -r mellanox-roms  gs://epoxy-staging/mellanox-roms
    # There appears to be no way to set a default meta data.
    # Public-read objects default to having a 1h cache timeout.
    # This sets it to zero.
    gsutil setmeta -r -h "Cache-Control:private, max-age=0, no-transform" gs://epoxy-staging

## ePoxy logs analysis

View the AppEngine application log thought the [Cloud console Logging
interace][cloud-console] in browser.

[cloud-console]: https://console.cloud.google.com/logs/viewer?project=mlab-staging

Download logs using the `gcloud logging` command:

    gcloud beta logging read 'resource.type="gae_app"
        resource.labels.module_id="boot-api"
        logName="projects/mlab-staging/logs/appengine.googleapis.com%2Fnginx.request"
        "/v1/boot/mlab3.iad1t.measurement-lab.org/stage2.ipxe"'

The form of the query filter can be discovered using the browser interface
throught "Convert to advanced filter" dropdown in the query bar.

## Checking reboot times

    gcloud beta logging read 'resource.type="gae_app"
        resource.labels.module_id="boot-api"
        logName="projects/mlab-staging/logs/appengine.googleapis.com%2Fnginx.request"
        "/v1/boot/mlab3.iad1t.measurement-lab.org/stage2.ipxe"
            AND timestamp >= "2017-02-06T20:14:00Z"' > dates.txt
    cat dates.txt \
        | grep -E 'timestamp:|path:' \
        | tr "'" ' ' \
        | grep timestamp \
        | sort \
        | while read junk ts ; do \
            ts=${ts%%.*}; ts=${ts%%Z} ; date2ts ${ts}; done > ts.txt
    cat ts.txt \
        | awk 'BEGIN {curr=0; prev=0}
            { curr=$1 ; if (prev > 0) { print curr - prev } ; prev=curr  }' \
        | sort > deltas.txt
    echo -e "plot 'deltas.txt' using 1\n pause mouse" | gnuplot
