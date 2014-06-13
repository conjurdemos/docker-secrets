#!/bin/bash
set -e

curl -o conjur_4.10.1-2_amd64.deb https://s3.amazonaws.com/conjur-releases/omnibus/conjur_4.10.1-2_amd64.deb
sudo dpkg -i conjur_4.10.1-2_amd64.deb

cat << PATH >> ~/.bashrc
export PATH=/opt/conjur/bin:$PATH
PATH
