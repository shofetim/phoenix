#!/bin/sh

cd src;
find . -name '*.janet' | entr  -c -c -a -r janet main.janet
