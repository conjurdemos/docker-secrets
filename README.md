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

For the purposes of this demo, we use Vagrant to bring up a Docker environment. This step doesn't have anything to do with the Docker functionality of the demo per se, it's just an easy way to get Docker going. 

If you already have Docker running on your machine, you can skip this section.

If you don't, run these commands to bring up Docker using Vagrant, and login to the new VM:

```
$ vagrant up
$ vagrant ssh
```

## Initialize Conjur

We will manage Conjur secrets, permissions, and identity through the [Conjur CLI](http://developer.conjur.net/setup/client_install/cli.html). Use these steps to configure the CLI and log yourself in.

### conjur init

Configure and secure the connection to Conjur:

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

Log yourself in:

```
$ conjur authn login
Enter your username to log into Conjur: alice
Please enter your password (it will not be echoed): 
Logged in
```

### create namespace for demo assets

Using a namespace keeps the resources and permissions that you create for this demo separate from anything else in your Conjur server.

This command generates and stores a unique six-character ID:

```
$ ns=`conjur id create` 
```

## Launch MySQL

With the setup steps complete, we can now begin setting up our demo system. The first service is a MySQL server running in a Docker container.

Bring up MySQL using the following command:

```
$ docker run -d --name 'mysqldemo' -t tutum/mysql
```

### Inspect MySQL

MySQL is running in Docker now. We will obtain the admin password and the IP address so that we can provide them to the Wordpress server.

Discover the `admin` password by checking the Docker container log, and store it in a shell variable:

``` 
$ docker logs mysqldemo | grep "\-p"
mysql -uadmin -pvvPFUNzxj9MM -h<host> -P<port>
$ mysql_password=vvPFUNzxj9MM
```

Obtain and store the MySQL IP address in a similar fashion:

```
$ docker inspect mysqldemo | grep IPAddress
        "IPAddress": "172.17.0.2",
$ mysql_ip="172.17.0.2"
```

## Store the MySQL password

The MySQL `admin` password will be stored in a Conjur [Variable](http://developer.conjur.net/reference/services/directory/variable), which is a secure, access controlled service for storing and distributing secrets.

Load the admin password into a Conjur variable like this:

```
$ conjur variable create -v $mysql_password demo/docker/$ns/mysql/password
{
  "id": "demo/docker/$ns/mysql/password",
  …
  "version_count": 1
}
```

## Create the Wordpress host identity in Conjur

When we launch Wordpress in a later step, it will be provided with the MySQL `admin` password that we just stored in Conjur. In order to get access to the password, the Wordpress container must have a Conjur identity, and its identity must be granted permission to fetch the password.

The following command creates a Conjur [Host](http://developer.conjur.net/reference/services/directory/host) record for the Wordpress container, and stores its id and API key in shell variables:

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

With the identity created, we can give Wordpress permission to `execute` (fetch) the variable:

```
$ conjur resource permit variable:demo/docker/$ns/mysql/password host:demo/docker/$ns/wordpress execute
```

# Docker image preparation

As we've discussed, we are going to run Wordpress in a Docker container. To do this, we'll need a Docker image.

We will start an existing Wordpress image and layer the Conjur tools and static configuration on top of it, then store the result as new local image.

Just to be clear, the following information will be "baked in" to the image:

* Wordpress code
* Conjur command-line tools
* `conjur init` configuration, to enable the CLI to make a secure connection to Conjur
* A [conjur env](http://developer.conjur.net/reference/tools/conjurenv) .conjurenv file, which describes (but does not contain) the secrets needed by Wordpress

And the following are *not* built into the image, but obtained by the container at runtime:

* Conjur host identity
* MySQL admin password

## Prepare Conjur files to be used by image

Create the `.conjurenv` file which describes the secrets and other configuration needed by Wordpress:

```
$ mkdir conjur
$ cd conjur
$ cat << ENV > .conjurenv
db_host: "$mysql_ip"
db_port: "3306"
db_pass: !var demo/docker/$ns/mysql/password
ENV
```

Create the `conjur.conf` which Wordpress will use to connect to Conjur

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


## Launch new container with host credentials as runtime options

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

## Inspect audit trail in Conjur

In audit trail (omit `-s` switch to observe full details) we see how permissions were granted, and than how host accessed the variable

$ conjur audit resource -s variable:demo/docker/$ns/mysql/password 
[2014-06-13 16:57:31 UTC] demo:user:admin created resource demo:variable:demo/docker/vas900/mysql/password owned by demo:user:admin
[2014-06-13 16:57:50 UTC] demo:user:admin checked that they can execute demo:variable:demo/docker/vas900/mysql/password (true)
[2014-06-13 17:00:31 UTC] demo:user:admin permitted demo:host:demo/docker/vas900/wordpress to execute demo:variable:demo/docker/vas900/mysql/password (grant option: false)
[2014-06-13 17:10:55 UTC] demo:host:demo/docker/vas900/wordpress checked that they can execute demo:variable:demo/docker/vas900/mysql/password (true)
$ conjur audit role -s host:demo/docker/$ns/wordpress
[2014-06-13 16:58:25 UTC] demo:user:admin created role demo:host:demo/docker/vas900/wordpress
[2014-06-13 16:58:25 UTC] demo:user:admin permitted demo:host:demo/docker/vas900/wordpress to read demo:host:demo/docker/vas900/wordpress (grant option: false)
[2014-06-13 17:00:31 UTC] demo:user:admin permitted demo:host:demo/docker/vas900/wordpress to execute demo:variable:demo/docker/vas900/mysql/password (grant option: false)
[2014-06-13 17:10:55 UTC] demo:host:demo/docker/vas900/wordpress checked that they can execute demo:variable:demo/docker/vas900/mysql/password (true)

