#!/bin/bash

if [ ! -r /etc/conjur/identity/.netrc ] ; then
  echo "ERROR: You must mount directory /etc/conjur/identity"
  exit 1
fi

conjur env run -c /etc/conjur/.conjurenv -- $*
