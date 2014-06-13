# Arbitrary base image can be used, this is just for demo purposes
FROM tutum/wordpress-stackable

##########################################################################
########## Conjur client install  ########################################
########## update if parent image is not based on Debian/Ubuntu ##########
##########################################################################

RUN apt-get update
RUN apt-get -y -y install make ruby2.0 ruby2.0-dev ruby-json
RUN gem install conjur-cli

##########################################################################
########## Conjur configuration (example files used) #####################
########## update them for production, but keep target names #############
##########################################################################

# Files describing Conjur endpoint
# They should be generated with "conjur init" locally before the build
# See details at http://developer.conjur.net/reference/tools/init.html

# File describing variables to be retrieved, 
# See details at http://developer.conjur.net/reference/tools/conjurenv#Format.of.environment.configuration

ADD ./conjur /etc/conjur

##########################################################################
################# Nothing should be changed below this point #############
##########################################################################

# Fix .conjurrc to find certificate in predefined location within container FS instead of local path(whatever it was)
#RUN sed -i -e 's/cert_file: .*//' /etc/.conjurrc
#RUN echo "cert_file: /conjur.pem" >> /etc/.conjurrc

# File .netrc with authentication data for container identity should be managed by host OS outside of Docker
# Directory '/conjur' with '.netrc' file is expected to be mounted in runtime
# Fix below adjusts .conjurrc to look for identity file in mounted directory
#RUN echo "netrc_path: /conjur/.netrc" >> /.conjurrc

# explicit setting for future launches of 'conjur env' to find .conjurrc within container FS
ENV CONJURRC /etc/conjur/conjur.conf

# Simple wrapper to check presence of /conjur/.netrc (directory /conjur is expected to be mounted during container run)
ADD conjur.sh /conjur.sh

# check presence of .netrc and launch "conjur env" with whatever CMD provided (by default CMD from original image)
# NOTE: double-quotes are important! (see http://stackoverflow.com/questions/20436586/my-docker-container-will-run-a-command-from-within-the-container-but-not-with-e )
ENTRYPOINT ["/conjur.sh"]

