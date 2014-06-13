#!/bin/bash

MISSING_VARIABLES=""
for variable in CONJUR_HOST_ID CONJUR_API_KEY ; do
  if [ -z $(printenv $variable) ] ; then
    MISSING_VARIABLES=$MISSING_VARIABLES" $variable"
  fi
done 

if [ ! -z "$MISSING_VARIABLES" ] ; then 
  echo "ERROR: following variables must be provided during container launch: $MISSING_VARIABLES"
  exit 1
fi

conjur authn login -u host/$CONJUR_HOST_ID -p $CONJUR_API_KEY
conjur env run -c /etc/conjur/.conjurenv -- $*
