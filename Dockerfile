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
########## Conjur configuration   ########################################
########## Nothing should be changed below this point ####################
##########################################################################

# Directory conjur-image-config should be created before the build
# It should have following contents:

# 1) Files describing Conjur endpoint: .conjurrc and *.pem
# They are generated with "conjur init -f ./.conjurrc" within the directory
# See details at http://developer.conjur.net/reference/tools/init.html

# 2) File describing variables to be provided to the CMD: .conjurenv 
# Should be designed manually according to the application needs
# See details at http://developer.conjur.net/reference/tools/conjurenv#Format.of.environment.configuration

ADD ./conjur-image-config /etc/conjur

# explicit setting for future launches of 'conjur env' to find .conjurrc within container FS
ENV CONJURRC /etc/conjur/.conjurrc

# Simple wrapper to perform authentication and launch "conjur env"
# File is delivered along with this Dockerfile 
ADD conjur.sh /conjur.sh

# Wrapper launches "conjur env" with whatever CMD provided (by default CMD from original image)
# NOTE: double-quotes are important! (see http://stackoverflow.com/questions/20436586/my-docker-container-will-run-a-command-from-within-the-container-but-not-with-e )
ENTRYPOINT ["/conjur.sh"]

