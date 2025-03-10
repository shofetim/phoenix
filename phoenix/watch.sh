#!/bin/sh

find . -name '*.janet' | entr  -c -c ./build-install-restart.sh
