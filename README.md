# Overview

This demo shows how to run Wordpress in a Docker container, with secrets (in this case, the MySQL database password) externalized in Conjur.

It works like this:

1. Launch a Docker container running MySQL. We obtain the MySQL IP address and admin password from the Docker log.
1. Store the MySQL admin password in a Conjur [variable](https://developer.conjur.net/reference/services/directory/variable).
1. Launch Wordpress in a Docker, MySQL connection information via the process environment. It will fetch the MySQL admin password, and provide this along with the MySQL IP address and port to Wordpress via the process environment.
1. Wordpress is running! Secrets are completely externalized and never stored on the hard drive. 
1. Conjur activity audit shows all MySQL admin password events.

As a follow-on example, Wordpress can be configured to use its own Conjur identity. This step adds additional detail to the Conjur audit log, and enables additional access-control features.

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
$ docker run -d --name mysql -t tutum/mysql
```

### Inspect MySQL

MySQL is running in Docker now. We will obtain the admin password and the IP address so that we can provide them to the Wordpress server.

Discover the `admin` password by checking the Docker container log, and store it in a shell variable:

``` 
$ docker logs mysql | grep "\-p"
mysql -uadmin -pvvPFUNzxj9MM -h<host> -P<port>
$ mysql_password=vvPFUNzxj9MM
```

Obtain and store the MySQL IP address in a similar fashion:

```
$ docker inspect mysql | grep IPAddress
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

## Enumerate the secrets and configuration used by Wordpress

Create a `.conjurenv` file which describes the secrets and other configuration values needed by Wordpress:

```
$ cat << ENV > .conjurenv
db_host: "$mysql_ip"
db_port: 3306
db_pass: !var demo/docker/$ns/mysql/password
ENV
```

# Run Wordpress

Use Conjur to load the secrets used by Wordpress into a temp file:

```
$ secrets_file=`conjur env template /vagrant/wordpress-secrets.erb`
```

Note that this secrets file is in the memory-mapped folder `/dev/shm`, it's not a physical file:

```
$ echo $secrets_file
/dev/shm/conjur20140616-18625-134abai.saved
```

Run the Conjur-ized Wordpress container, providing Host ID and API key as parameters 

```
$ docker run -d -P --name 'wordpress' --env-file $secrets_file conjur-wordpress
```

Note: The container will refuse to start if identity parameters are not provided.

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

Cleanup the secrets file:

```
$ rm $secrets_file
```
