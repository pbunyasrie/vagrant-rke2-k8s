# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box_check_update = false
  config.vm.provider 'virtualbox' do |vb|
   vb.customize ["guestproperty", "set", :id, "/VirtualBox/GuestAdd/VBoxService/--timesync-set-threshold", 1000]
   vb.customize ["modifyvm", :id, "--cpuexecutioncap", "50"]
  end  
  config.vm.synced_folder ".", "/vagrant", type: "rsync"

  $num_masters = 1
  $num_workers = 1
  $kube_subnet_start = "172.17.8"
  $pod_subnet = "172.22.143.0/24"

  # curl https://discovery.etcd.io/new?size=3
  $control_plane_endpoint = "#{$kube_subnet_start}.101"

  (1..$num_masters).each do |i|
    config.vm.define "master-#{i}" do |master|
      master.vm.box = "centos/8"
      master.vm.hostname = "master-#{i}"
      ip = "#{$kube_subnet_start}.#{i+100}"
      master.vm.network "private_network", ip: ip
      master.vm.provider "virtualbox" do |vb|
        vb.memory = "2048"
        vb.cpus = 2
        vb.name = "master-#{i}"
      end
      master.vm.provision "shell", path: "setup.sh", args: [i, ip, $kube_subnet_start, $pod_subnet, $control_plane_endpoint, $num_masters, $num_workers, "master"]
    end
  end

  (1..$num_workers).each do |i|
    config.vm.define "worker-#{i}" do |worker|
      worker.vm.box = "centos/8"
      worker.vm.hostname = "worker-#{i}"
      ip = "#{$kube_subnet_start}.#{i+200}"
      worker.vm.network "private_network", ip: ip
      worker.vm.provider "virtualbox" do |vb|
        vb.memory = "2048"
        vb.cpus = 2
        vb.name = "worker-#{i}"
      end
      worker.vm.provision "shell", path: "setup.sh", args: [i, ip, $kube_subnet_start, $pod_subnet, $control_plane_endpoint, $num_masters, $num_workers, "node"]
    end
  end

end
