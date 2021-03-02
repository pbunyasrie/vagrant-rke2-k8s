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
  $num_workers = 2
  $kube_subnet_start = "192.168.20"

  # curl https://discovery.etcd.io/new?size=3
  $control_plane_endpoint = "#{$kube_subnet_start}.101"

  (1..$num_masters).each do |i|
    config.vm.define "master-#{i}" do |master|
      master.vm.box = "centos/8"
      master.vm.hostname = "master-#{i}"
      ip = "#{$kube_subnet_start}.#{i+100}"
      master.vm.network "private_network", ip: ip
      if (i == 1) then master.vm.network "forwarded_port", guest: 6443, host: 6443 end
      master.vm.provider "virtualbox" do |vb|
        vb.memory = "4096"
        vb.cpus = 2
        vb.name = "master-#{i}"
      end
      master.vm.provision "shell", path: "setup-rke2.sh", args: [i, ip, "master"]
      #master.vm.provision "shell", path: "setup-vanilla.sh", args: [i, ip, $kube_subnet_start, $pod_subnet, $control_plane_endpoint, $num_masters, $num_workers, "master"]
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
      worker.vm.provision "shell", path: "setup-rke2.sh", args: [i, ip, "node"]
      #worker.vm.provision "shell", path: "setup-vanilla.sh", args: [i, ip, $kube_subnet_start, $pod_subnet, $control_plane_endpoint, $num_masters, $num_workers, "node"]
    end
  end

end
