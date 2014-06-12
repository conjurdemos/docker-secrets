#!/bin/bash

if [ ! -r /conjur/.netrc ] ; then
  echo "ERROR: Please, mount directory /conjur with .netrc in it"
  exit 1
fi

conjur env run -c /.conjurenv -- $*
