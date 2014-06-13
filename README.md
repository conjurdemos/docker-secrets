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

# Preparation

## Vagrant up (optional)

Bring up the Docker environment. If you have Docker on your machine, you can use it as is. Otherwise, bring it up using Vagrant and login:

```
$ vagrant up
$ vagrant ssh
```

## Initialize Conjur

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


## Launch MySQL

Run the MySQL container:

```
$ docker run -d --name 'mysqldemo' -t tutum/mysql
```

## Inspect MySQL

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
$ conjur variable create -v $mysql_password demo/docker/mysql/password
{
  "id": "demo/docker/mysql/password",
  …
  "version_count": 1
}
```

## Create the Wordpress host

Create the Wordpress host:

```
$ conjur host create demo/docker/wordpress | tee host.json
{
  "id": "demo/docker/wordpress",
  …
  "api_key": "3347e103h8ghze21dxv3b2y19vm6sq93ev3mw7bn13q47f883kxjhaa"
}
$ host_id=`cat host.json | jsonfield id`
$ host_api_key=`cat host.json | jsonfield api_key`

```

Give Wordpress permission to `execute` the variable:

```
$ conjur resource permit variable:demo/docker/mysql/password host:demo/docker/wordpress execute
```

## Build the Wordpress container


Create the `.conjurenv` file which will expose secrets and other configuration to Wordpress:

```
$ mkdir conjur
$ cd conjur
$ cat << ENV > .conjurenv
db_host: "$mysql_ip"
db_port: "3306"
db_pass: !var demo/docker/mysql/password
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

Use a local netrc:

```
echo 'netrc_path: ./.netrc' >> conjur.conf
```

Login to conig/

```
$ CONJURRC=./conjur.conf conjur authn login -u host/$host_id -p $host_api_key
```


## Build docker image 

Now you can build local docker image from attached Dockerfile which will serve as a prototype for future containers. 

```
$ cp /vagrant/Dockerfile .
$ cp /vagrant/conjur.sh .
$ docker build -t conjur-wordpress ./ 
```

# Runtime

## Launch new container 

Run the Conjur-ized Wordpress container, mounting the directory which contains the Conjur endpoint config and the host identity:

```
docker run -d -P --name 'wordpress' -v $PWD/conjur:/etc/conjur conjur-wordpress
```

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
