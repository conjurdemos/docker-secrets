# Overview

This demo shows how to run Wordpress in a Docker container, with secrets (in this case, the MySQL database password) externalized in Conjur.

It works like this:

1. Launch a Docker container running MySQL. We obtain the MySQL IP address and admin password from the Docker log.
1. Store the MySQL admin password in a Conjur [variable](https://developer.conjur.net/reference/services/directory/variable).
1. Launch Wordpress in Docker, with MySQL connection host, port, and admin password obtained via the process environment.
1. Wordpress is running! Secrets are completely externalized and never stored on the hard drive. 
1. Conjur audit records shows all MySQL admin password events.

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

First, inspect the environment of the container, to see that it contains the expected variables:

```
$ docker run -e DB_HOST=$mysql_ip -e DB_PORT=3306 --env-file $secrets_file tutum/wordpress-stackable env
HOME=/
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOSTNAME=22e31c23d6a0
DB_PASS=vvPFUNzxj9MM
DB_HOST=172.17.0.2
DB_PORT=3306
DB_NAME=wordpress
DB_USER=admin
```

Now run the Conjur-ized Wordpress container, providing secrets through the environment file: 

```
$ docker run -d -P --name wordpress -e DB_HOST=$mysql_ip -e DB_PORT=3306 --env-file $secrets_file tutum/wordpress-stackable
```

You're all set. Inspect logs of just launched container:

```
$ docker logs wordpress
=> Trying to connect to MySQL/MariaDB using:
========================================================================
  Database Host Address:  172.17.0.2
  Database Port number:   3306
  Database Name:          wordpress
  Database Username:      admin
  Database Password:      vvPFUNzxj9MM
========================================================================
=> Creating database wordpress
=> Done!
... <other wordpress output skipped> ...
```

Cleanup the secrets file:

```
$ rm $secrets_file
```

# Password audit

Conjur shows the complete record of creation and usage of the password:

```
$ conjur audit resource --short variable:demo/docker/$ns/mysql/password
[2014-06-16 16:58:36 UTC] demo:user:alice created resource demo:variable:demo/docker/vaza00/mysql/password owned by demo:user:alice
[2014-06-16 17:53:41 UTC] demo:user:alice checked that they can execute demo:variable:demo/docker/vaza00/mysql/password (true)
```

If the MySQL password had been changed by another user, or used from another location, the audit record would report it.

# Wordpress host identity

If a service or application needs to interact with Conjur itself, it must be provided with its own identity to do so. Creating a Wordpress host identity also demonstrates better fine-grained authorization, as well as separation of duties between the roles which can update the password and those which can fetch it.

The following commands create a Conjur [Host](http://developer.conjur.net/reference/services/directory/host) record for the Wordpress container. The host information is stored in a *wordpress* sub-directory.


```
$ mkdir wordpress
$ conjur host create demo/docker/$ns/wordpress | tee wordpress/host.json
{
  "id": "demo/docker/$ns/wordpress",
  …
  "api_key": "3347e103h8ghze21dxv3b2y19vm6sq93ev3mw7bn13q47f883kxjhaa"
}
$ cat << CONJURRC > wordpress/.conjurrc
netrc_path: ./.netrc
CONJURRC
```

Once the host is created, we give it permission to `execute` (fetch) the variable:

```
$ conjur resource permit variable:demo/docker/$ns/mysql/password host:demo/docker/$ns/wordpress execute
```

Next, we change to the *wordpress* directory and login as the host.

```
$ cd wordpress
$ host_id=`cat host.json | jsonfield id`
$ host_api_key=`cat host.json | jsonfield api_key`
$ conjur authn login -u host/$host_id -p $host_api_key
Logged in
$ conjur authn whoami
{"account":"demo","username":"host/demo/docker/vaza00/wordpress"}
```

Verify that the secrets are available:

```
$ conjur env check
db_pass: available
```

And now we can run Wordpress using the same command sequence as above. In this case, we are running as the very permissions-limited `wordpress` role, rathan than using our own role.

```
$ secrets_file=`conjur env template /vagrant/wordpress-secrets.erb`
$ docker run -d -P --name wordpress -e DB_HOST=$mysql_ip -e DB_PORT=3306 --env-file $secrets_file tutum/wordpress-stackable
$ docker logs wordpress
=> Trying to connect to MySQL/MariaDB using:
========================================================================
      Database Host Address:  172.17.0.2
      Database Port number:   3306
      Database Name:          wordpress
      Database Username:      admin
      Database Password:      Cn1T6PlSR8Dq
========================================================================
=> Skipped creation of database wordpress – it already exists.
… etc
```

## Audit the admin password

The audit record for the MySQL password shows that the Wordpress host is accessing the password directly.

```
$ conjur audit resource --short variable:demo/docker/$ns/mysql/password
[2014-06-16 16:59:41 UTC] demo:user:alice permitted demo:host:demo/docker/vaza00/wordpress to execute demo:variable:demo/docker/vaza00/mysql/password (grant option: false)
[2014-06-16 18:45:33 UTC] demo:host:demo/docker/vaza00/wordpress checked that they can execute demo:variable:demo/docker/vaza00/mysql/password (true)
[2014-06-16 18:46:37 UTC] demo:host:demo/docker/vaza00/wordpress checked that they can execute demo:variable:demo/docker/vaza00/mysql/password (true)
```

# Conjur-ized Docker container

In the previous case, the Docker server was acting as the Docker host, and passing the Wordpress environment variables through the `docker run` command.

It's also possible to let the Docker container *itself* assume the Conjur host identity, and fetch the secrets itself.

We'll start by updating our *wordpress* configuration to have a `.conjurrc` file with full connection and security info:


```
$ cd wordpress
$ conjur init -f ./.conjurrc
Enter the hostname (and optional port) of your Conjur endpoint: ec2-54-83-34-173.compute-1.amazonaws.com

SHA1 Fingerprint=EC:E3:BD:2E:61:74:43:31:5C:37:4A:A6:BF:E2:51:CB:19:E2:46:4C

Please verify this certificate on the appliance using command:
                openssl x509 -fingerprint -noout -in ~conjur/etc/ssl/conjur.pem

Trust this certificate (yes/no): yes
Wrote certificate to ./conjur-demo.pem
File ./.conjurrc exists. Overwrite (yes/no): yes
Wrote configuration to ./.conjurrc
```

Next, we'll create a secrets config which contains the host, port, and MySQL password:

```
$ cat << ENV > .conjurenv
db_host: "$mysql_ip"
db_port: "3306"
db_pass: !var demo/docker/$ns/mysql/password
ENV
```

With this information, we build a custome Docker container. This container starts with Wordpress, and layers on the following:

* Conjur command-line interface (CLI)
* `.conjurrc` Conjur server configuration
* `.conjurenv` secrets configuration
* A startup script which logs into Conjur, fetches secrets, and runs Wordpress

Let's go:


```
$ cp /vagrant/Dockerfile .
$ cp /vagrant/conjur.sh .
$ docker build -t conjur-wordpress ./
```

With the custom container built, we run it with the `CONJUR_HOST_ID` and `COJNUR_API_KEY` environment variables. These are used by the container to login to Conjur and fetch the secrets:

```
$ docker run -d -P --name conjur-wordpress -e CONJUR_HOST_ID=$host_id -e CONJUR_API_KEY=$host_api_key conjur-wordpress
f8fe8fa0991f59d693920b4405f04b1d887dae6269a0d797aa1b0ac83317f097
$ docker logs conjur-wordpress
Logged in
=> Trying to connect to MySQL/MariaDB using:
========================================================================
      Database Host Address:  172.17.0.2
      Database Port number:   3306
      Database Name:          wordpress
      Database Username:      admin
      Database Password:      vvPFUNzxj9MM
========================================================================
=> Skipped creation of database wordpress – it already exists.
/usr/lib/python2.7/dist-packages/supervisor/options.py:295: UserWarning: Supervisord is running as root and it is searching for its configuration file in default locations (including its current working directory); you probably want to specify a "-c" argument specifying an absolute path to a configuration file for improved security.
  'Supervisord is running as root and it is searching '
2014-06-16 19:56:04,600 CRIT Supervisor running as root (no user in config file)
2014-06-16 19:56:04,601 WARN Included extra file "/etc/supervisor/conf.d/supervisord-apache2.conf" during parsing
2014-06-16 19:56:04,624 INFO RPC interface 'supervisor' initialized
2014-06-16 19:56:04,624 CRIT Server 'unix_http_server' running without any HTTP authentication checking
2014-06-16 19:56:04,624 INFO supervisord started with pid 14
```

When we check the password audit, we can see again that the password is being retrieved by the `wordpress` host:

```
$ conjur audit resource --short variable:demo/docker/$ns/mysql/password
[2014-06-16 19:54:12 UTC] demo:host:demo/docker/vaza00/wordpress checked that they can execute demo:variable:demo/docker/vaza00/mysql/password (true)
```

