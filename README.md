# Status

This is draft version of Readme, which needs more automation of steps described

# Prerequisites

1. Environment with Docker installed ( hint for vagrant users: you may use attached `Vagrantfile`)
2. Access to Conjur appliance 
3. Conjur CLI installed in your working environment (it may be installed in separate environment, but you will need files from there)
4. Dedicated mysql server (hint: it can be launched by `docker run -d --name 'mysqldemo' -t tutum/mysql`, and password can be discovered by `docker logs mysqldemo` )

# Preparation 

## Prepare metadata used by Docker builder

1. If you never logged into Conjur appliance before, perform `conjur init`
2. Copy your `.conjurrc` file into `example/` directory 
3. Copy your certificate file (one listed as 'cert_file' in .conjurrc) into `example/` directory as `conjur-demo.pem`
4. Edit file `example/.conjurenv` to match hostname and port of your Mysql server

## Store secrets in Conjur 

Log into Conjur, and store your Mysql password here, create appropriate permissions:

```
    conjur variable create demo/docker/mysql/password 
    conjur variable values add demo/docker/mysql/password <MYSQL PASSWORD>UN 
    conjur layer create demo/docker/containers/wordpress 
    conjur resource permit variable:demo/docker/mysql/password layer:demo/docker/containers/wordpress execute
```

## Build docker image 

Now you can build local docker image from attached Dockerfile which will serve as a prototype for future containers. 

```
    docker build -t dockerdemo ./ 
```

# Runtime

## Create identity for a new container

This part could be managed in different ways, but goal is to have directory `conjur/` with authentication information for new container

Create new host and add it to the layer

```bash
    conjur host create container-1.docker.demo.conjur   # note api_key here
    conjur layer hosts add demo/docker/containers/wordpress container-1.docker.demo.conjur  # now this identity is allowed to read credentials
```

Generate `.netrc` file with credentials for new container:

```bash
    cp ~/.conjurrc ~/.conjurrc.backup   
    echo "netrc_path: $PWD/conjur/.netrc" >> ~/.conjurrc
    mkdir conjur/
    conjur authn:login -u host/container-1.docker.demo.conjur -p <api key recorded before>
    cp ~/.conjurrc.backup ~/.conjurrc
```

    
Now in your `conjur/` directory you have file with authentication info for new container. It should be mounted in runtime.

## Launch new container 

Assuming that directory `$PWD/conjur` is available, run docker container from the image created before, mounting directory with host identity on-the-fly

```
    docker run -d -P --name 'wordpress' -v $PWD/conjur:/conjur dockerdemo
```

You're all set. Inspect logs of just launched container:

```
    => Trying to connect to MySQL/MariaDB using:
    ========================================================================
      Database Host Address:  <mysql host as defined in example/.conjurenv>
      Database Port number:   <mysql port as defined in example/.conjurenv>
      Database Name:          wordpress
      Database Username:      admin
      Database Password:      <mysql password obtained from Conjur>
    ========================================================================
    => Creating database wordpress
    => Done!
    ... <other wordpress output skipped> ...
```
