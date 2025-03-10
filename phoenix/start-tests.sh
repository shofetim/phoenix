#!/bin/sh

find . -name '*.janet' | entr  -c -r jpm test
