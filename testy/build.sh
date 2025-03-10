#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Clean
jpm clean
rm -fr testy.tar testy.oci testy.bundle

# Build the binary
jpm build

# Build the docker image & export it
docker build -t testy .
docker image save testy -o testy.tar

# Uncompress & untar it, then convert it to a bundle
mkdir testy.oci
tar -xf testy.tar -C testy.oci
umoci unpack --image=testy.oci testy.bundle
