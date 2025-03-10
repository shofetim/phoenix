#!/bin/sh

jpm clean
jpm build
scp build/phoenix terra:/srv/phoenix.jordanschatz.com/releases/current/
