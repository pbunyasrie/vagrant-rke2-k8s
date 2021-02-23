#!/usr/bin/env bash

# REFERENCE: https://www.tecmint.com/install-a-kubernetes-cluster-on-centos-8/
# https://pushpanel.io/2019/install-a-master-kubernetes-cluster-on-centos-8/
# https://kubernetes.io/blog/2019/03/15/kubernetes-setup-using-ansible-and-vagrant/
# https://github.com/rootsongjc/kubernetes-vagrant-centos-cluster

THIS_NUM=$1
THIS_IP=$2
KUBE_SUBNET=$3
POD_SUBNET=$4
CONTROL_PLANE_ENDPOINT=$5 # this should be a DNS name that points to a load balancer
MASTERS=$6
WORKERS=$7
NODE_TYPE=$8

KUBERNETES_VERSION=1.20.4
DOCKER_VERSION=19.03.15-3.el8

# change time zone
#cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
#timedatectl set-timezone Asia/Shanghai

# Setup DNF repos
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF


cat <<EOF > /etc/sysconfig/kubelet
KUBELET_EXTRA_ARGS=--cgroup-driver=systemd
EOF

dnf -y update --nobest && yum -y upgrade --nobest

dnf install -y wget curl conntrack-tools vim net-tools telnet tcpdump bind-utils kmod nmap-ncat

# Install and configure firewall
# See https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
dnf install -y firewalld
systemctl restart firewalld && systemctl enable firewalld
# control plane nodes
if [[ $NODE_TYPE == "master" ]]; then
	firewall-cmd --permanent --add-port=6443/tcp # K8S API server; used by all
	firewall-cmd --permanent --add-port=2379-2380/tcp # etcd server client API; used by kube-apiserver, etcd
	firewall-cmd --permanent --add-port=10251/tcp # kube-scheduler; used by self
	firewall-cmd --permanent --add-port=10252/tcp #kube-controller-manager; used by self
fi
# worker nodes
firewall-cmd --permanent --add-port=30000-32767/tcp # NodePort services, used by all
# both control plane and worker nodes
firewall-cmd --permanent --add-port=10250/tcp # kubelet API; used by self, control plane


firewall-cmd --permanent --add-port=10255/tcp 
firewall-cmd --permanent --add-port=8080/tcp
firewall-cmd --reload
echo "br_netfilter" >> /etc/modules-load.d/br_netfilter.conf
modprobe br_netfilter
echo "net.bridge.bridge-nf-call-ip6tables = 1">> /etc/sysctl.d/01-custom.conf
echo "net.bridge.bridge-nf-call-iptables = 1">> /etc/sysctl.d/01-custom.conf
echo "net.bridge.bridge-nf-call-arptables = 1" >> /etc/sysctl.d/01-custom.conf
sysctl -p /etc/sysctl.d/01-custom.conf

# Other 
echo 'disable selinux'
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux

echo 'enable iptable kernel parameter'
cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward=1
EOF
sysctl -p

echo 'set host name resolution'
for ((i=1;i<=$MASTERS;i++)); do
    echo ${KUBE_SUBNET}.10$i master-$i
done >> /etc/hosts

for ((i=1;i<=$WORKERS;i++)); do
    echo ${KUBE_SUBNET}.20$i worker-$i
done >> /etc/hosts

# TODO: Setup haproxy for load balancing between masters in dev environment (real life would use F5 BigIP)
echo "$CONTROL_PLANE_ENDPOINT vagrant-k8s" >> /etc/hosts

cat /etc/hosts

echo 'set nameserver'
echo "nameserver 8.8.8.8">/etc/resolv.conf
cat /etc/resolv.conf

echo 'disable swap'
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab
#sed -i '/swap/d' /etc/fstab

# Install Docker
#create group if not exists
egrep "^docker" /etc/group >& /dev/null
if [ $? -ne 0 ]
then
  groupadd docker
fi

usermod -aG docker vagrant
rm -rf ~/.docker/
dnf install docker-ce-${DOCKER_VERSION} docker-ce-cli-${DOCKER_VERSION} -y

mkdir -p /etc/docker
# according to https://kubernetes.io/docs/setup/production-environment/container-runtimes/#docker
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF

echo 'enable docker'
systemctl daemon-reload
systemctl enable docker
systemctl start docker

# Install Kubernetes
dnf install iproute-tc kubeadm-${KUBERNETES_VERSION} kubelet-${KUBERNETES_VERSION} kubectl-${KUBERNETES_VERSION} -y
dnf install python3-dnf-plugin-versionlock -y
dnf versionlock kubeadm
dnf versionlock kubelet
dnf versionlock kubectl

#dnf versionlock list
systemctl enable kubelet
systemctl start kubelet

source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> ~/.bashrc
echo "source <(kubeadm completion bash)" >> ~/.bashrc

# INITIAL MASTER SETUP ONLY
if [[ $THIS_NUM -eq 1 && $NODE_TYPE == "master" ]]
then
	# kubeadm init --help for more information
	kubeadm init --apiserver-cert-extra-sans vagrant-k8s --apiserver-advertise-address $THIS_IP --control-plane-endpoint $CONTROL_PLANE_ENDPOINT --upload-certs --pod-network-cidr $POD_SUBNET | tee /tmp/kubeadm-init.out #<-- Match the IP range from the Calico config file

	mkdir -p $HOME/.kube
	sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
	sudo chown $(id -u):$(id -g) $HOME/.kube/config

	# untaint the node so that we can schedule pods
	#kubectl taint nodes master-1 node.kubernetes.io/not-ready:NoSchedule-
	kubectl taint nodes --all node.kubernetes.io/not-ready-
	kubectl describe node | grep -i taint

	# Setup Calico
	# see https://docs.projectcalico.org/getting-started/kubernetes/self-managed-onprem/onpremises#install-calico-with-kubernetes-api-datastore-50-nodes-or-less
	wget https://docs.projectcalico.org/archive/v3.18/manifests/calico.yaml
	sed -i "s/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/g" calico.yaml
	sed -i "s/#   value: \"192.168.0.0\/16\"/  value: \"${POD_SUBNET/\//\/}\"/g" calico.yaml
	kubectl apply -f calico.yaml

	# Install kubectl calicoctl plugin
	cd /usr/local/bin
	curl -o kubectl-calico -L  https://github.com/projectcalico/calicoctl/releases/download/v3.18.0/calicoctl
	chmod +x kubectl-calico
	# kubectl calico -h

	# Keep showing status until everything is running
	until [[ $( kubectl get pods --field-selector=status.phase!=Running --all-namespaces 2>&1 ) == "No resources found" ]]
	do 
	    kubectl get pods --field-selector=status.phase!=Running --all-namespaces
	    sleep 10
	done
	kubectl taint nodes $(hostname) node.kubernetes.io/not-ready:NoSchedule
fi
echo "Finished provisioning $(hostname)!"
if [[ $THIS_NUM -eq 1 && $NODE_TYPE == "master" ]]
then
	echo "View join tokens at /tmp/kubeadm-init.out on $(hostname)"
fi
