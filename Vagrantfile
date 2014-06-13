require 'vagrant-vbguest'
Vagrant.configure("2") do |config|
  config.vm.box = "trusty64"
  config.vm.box_url = "https://cloud-images.ubuntu.com/vagrant/trusty/current/trusty-server-cloudimg-amd64-vagrant-disk1.box"

  config.ssh.forward_agent = true
  
  config.vm.provision "shell", path: "setup.sh"

  config.vm.synced_folder '.', '/vagrant'

  config.vm.provision :docker do |d|
    d.pull_images "tutum/mysql", "tutum/wordpress-stackable"  
  end

  # This seems to be necessary for networking to work on jon's machine
  config.vm.provider "virtualbox" do |v|
    v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    v.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
  end
end
