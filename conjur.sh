#!/bin/bash

if [ ! -r /etc/conjur/.netrc ] ; then
  echo "ERROR: You must mount directory /etc/conjur"
  exit 1
fi

conjur env run -c /etc/conjur/.conjurenv -- $*
