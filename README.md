# Overview

This demo shows how to run Wordpress in a Docker container, with secrets (in this case, the MySQL database password) externalized in Conjur.

It works like this:

1. Build a Docker container to run Wordpress. This container will start with a base Wordpress container, and onto that we will add [conjur init](https://developer.conjur.net/reference/tools/init.html) configuration.
1. Launch a Docker container running MySQL. We obtain the MySQL IP address and admin password from the Docker log.
1. Store the MySQL admin password in a Conjur [variable](https://developer.conjur.net/reference/services/directory/variable).
1. Create a [host](https://developer.conjur.net/reference/services/directory/host) record for the Wordpress container, and give it permission to read the MySQL password variable.
1. Launch our Conjur-ized Wordpress container, providing it the host identity. It will fetch the MySQL admin password, and provide this along with the MySQL IP address and port to Wordpress via the process environment.
1. Wordpress is running! Secrets are completely externalized and never stored on the hard drive. 
1. Conjur activity audit shows all MySQL admin password events.


# Prerequisites

To run this demo, you need the following:

1. A working [Docker](https://docker.com). If you have Vagrant, you can use the included Vagrantfile to create one.
1. A Conjur server and command-line client. See [developer.conjur.net](http://developer.conjur.net/setup) for installation and setup instructions.

# General preparation

## Vagrant up (optional)

Bring up the Docker environment. If you have Docker on your machine, you can use it as is. Otherwise, bring it up using Vagrant and login:

```
$ vagrant up
$ vagrant ssh
```

## Initialize Conjur

In order to manage secret, permissions and host identity for this demo, Conjur CLI setup is required.

### conjur init

```
$ conjur init
Enter the hostname (and optional port) of your Conjur endpoint: conjur

SHA1 Fingerprint=EC:E3:BD:2E:61:74:43:31:5C:37:4A:A6:BF:E2:51:CB:19:E2:46:4C

Please verify this certificate on the appliance using command:
                openssl x509 -fingerprint -noout -in ~conjur/etc/ssl/conjur.pem

Trust this certificate (yes/no): yes
Wrote certificate to /home/vagrant/conjur-demo.pem
Wrote configuration to /home/vagrant/.conjurrc
```

### conjur authn login

```
$ conjur authn login
Enter your username to log into Conjur: alice
Please enter your password (it will not be echoed): 
Logged in
```

### create namespace for demo assets

Although this is not mandatory for succcessful accomplishment of the demo, it make sense to use namespace to separate demo assets from anything else in your Conjur server.

Command below generates random unique six-chars ID.

```
$ ns=`conjur id create` 
```

## Launch MySQL

Run the MySQL container:

```
$ docker run -d --name 'mysqldemo' -t tutum/mysql
```

### Inspect MySQL

Find out the admin password by checking the mysqldemo container log:

``` 
$ docker logs mysqldemo | grep "\-p"
mysql -uadmin -pvvPFUNzxj9MM -h<host> -P<port>
$ mysql_password=vvPFUNzxj9MM
```

Find out the mysql IP address in a similar fashion:

```
$ docker inspect mysqldemo | grep IPAddress
        "IPAddress": "172.17.0.2",
$ mysql_ip="172.17.0.2"
```

## Store the MySQL password

Store the MySQL admin password in a Conjur variable:

```
$ conjur variable create -v $mysql_password demo/docker/$ns/mysql/password
{
  "id": "demo/docker/$ns/mysql/password",
  …
  "version_count": 1
}
```

## Create the Wordpress host identity in Conjur

Create the Wordpress host, store it's ID and API key:

```
$ conjur host create demo/docker/$ns/wordpress | tee host.json
{
  "id": "demo/docker/$ns/wordpress",
  …
  "api_key": "3347e103h8ghze21dxv3b2y19vm6sq93ev3mw7bn13q47f883kxjhaa"
}
$ host_id=`cat host.json | jsonfield id`
$ host_api_key=`cat host.json | jsonfield api_key`

```

Give Wordpress permission to `execute` the variable:

```
$ conjur resource permit variable:demo/docker/$ns/mysql/password host:demo/docker/$ns/wordpress execute
```

# Docker image preparation

In order to launch docker-ized application, docker image is required. 

We'll take already existing image with Wordpress, and set up Conjur tools on top of it, storing the result as new local image.

## Prepare Conjur files to be used by image

Create the `.conjurenv` file which will expose secrets and other configuration to Wordpress:

```
$ mkdir conjur
$ cd conjur
$ cat << ENV > .conjurenv
db_host: "$mysql_ip"
db_port: "3306"
db_pass: !var demo/docker/$ns/mysql/password
ENV
```

Create the `conjur.conf` which Wordpress will use:

```
conjur init -f ./conjur.conf
Enter the hostname (and optional port) of your Conjur endpoint: conjur

SHA1 Fingerprint=EC:E3:BD:2E:61:74:43:31:5C:37:4A:A6:BF:E2:51:CB:19:E2:46:4C

Please verify this certificate on the appliance using command:
                openssl x509 -fingerprint -noout -in ~conjur/etc/ssl/conjur.pem

Trust this certificate (yes/no): yes
Wrote certificate to ./conjur-demo.pem
Wrote configuration to ./conjur.conf
```

Return to main working directory

```
cd ../
```

## Build docker image 

Now you can build local docker image from attached Dockerfile which will serve as a prototype for future containers. 

```
$ cp /vagrant/Dockerfile .
$ cp /vagrant/conjur.sh .
$ docker build -t conjur-wordpress ./ 
```

# Runtime


## Launch new container with mounted identity directory 

Run the Conjur-ized Wordpress container, providing Host ID and API key as parameters 

```
docker run -d -P --name 'wordpress' -e CONJUR_HOST_ID=$host_id -e CONJUR_API_KEY=$host_api_key conjur-wordpress
```
    Container will refuse to start if identity parameters are not provided

You're all set. Inspect logs of just launched container:

```
    => Trying to connect to MySQL/MariaDB using:
    ========================================================================
      Database Host Address:  <mysql host as defined in .conjurenv>
      Database Port number:   <mysql port as defined in .conjurenv>
      Database Name:          wordpress
      Database Username:      admin
      Database Password:      <mysql password obtained from Conjur>
    ========================================================================
    => Creating database wordpress
    => Done!
    ... <other wordpress output skipped> ...
```
