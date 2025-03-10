#!/bin/sh

jpm clean
jpm build
cp build/phoenix /usr/local/bin/
service phoenix-public restart
service phoenix-master restart
service phoenix-minion restart
