Vagrant.configure("2") do |config|
  config.vm.box = "trusty64"
  config.vm.box_url = "https://cloud-images.ubuntu.com/vagrant/trusty/current/trusty-server-cloudimg-amd64-vagrant-disk1.box"

  config.ssh.forward_agent = true

  config.vm.provision :docker do |d|
    d.pull_images "ubuntu", "tutum/mysql", "tutum/wordpress-stackable"  
  end
end
