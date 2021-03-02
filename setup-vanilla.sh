#!/usr/bin/env bash

# This is for a vanilla setup of K8S. Not recommended.

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

KUBERNETES_VERSION=1.20.0 # an older version is required to run Rancher
DOCKER_VERSION=19.03.15-3.el8

declare -a ip_list=()
get_ip_list () {

        for i in $(seq 101 $num_masters); do
                list+=(192.160.20.$i)
        done

        for i in $(seq 201 $num_workers); do
                list+=(192.160.20.$i)
        done

        ip_list="$(printf ",\"%s\"" "${list[@]}" | cut -c2- | sed -e 's/\"/\\\"/g')"
        #ip_list=$( IFS=$'\n'; echo "${list[*]}" )

}
get_ip_list

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
#KUBELET_EXTRA_ARGS=--cgroup-driver=systemd
KUBELET_EXTRA_ARGS=--cgroup-driver=systemd --node-ip=$THIS_IP
EOF

dnf -y update --nobest && dnf -y upgrade --nobest

dnf install -y wget curl conntrack-tools vim net-tools telnet tcpdump bind-utils kmod nmap-ncat python3 git
ln -s /bin/python3 /bin/python

# The packages below are just for monitoring
dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y
dnf install htop -y


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
	# see https://stackoverflow.com/questions/61214151/inter-pods-communication-with-dns-name-not-working-in-kubernetes
	firewall-cmd --add-masquerade --permanent
fi
# worker nodes
firewall-cmd --permanent --add-port=30000-32767/tcp # NodePort services, used by all
# both control plane and worker nodes
firewall-cmd --permanent --add-port=10250/tcp # kubelet API; used by self, control plane
firewall-cmd --permanent --add-port=179/tcp # BGP (Calico)


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
echo "export PATH=$HOME/.gloo/bin:/usr/local/bin:/usr/local/sbin:$PATH" >> ~/.bashrc
export PATH=$HOME/.gloo/bin:/usr/local/bin:/usr/local/sbin:$PATH

# INITIAL MASTER SETUP ONLY
if [[ $THIS_NUM -eq 1 && $NODE_TYPE == "master" ]]
then
	# kubeadm init --help for more information
	kubeadm init --apiserver-cert-extra-sans $THIS_IP --apiserver-advertise-address $THIS_IP --control-plane-endpoint $CONTROL_PLANE_ENDPOINT --upload-certs --pod-network-cidr $POD_SUBNET | tee /root/kubeadm-init.out #<-- Match the IP range from the Calico config file

	mkdir -p $HOME/.kube
	sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
	sudo chown $(id -u):$(id -g) $HOME/.kube/config

	# untaint the node so that we can schedule pods
	#kubectl taint nodes master-1 node.kubernetes.io/not-ready:NoSchedule-
	kubectl taint nodes --all node.kubernetes.io/not-ready-
	kubectl taint node master-1 node-role.kubernetes.io/master:NoSchedule
	kubectl describe node | grep -i taint

	# Setup Canal
	# see https://docs.projectcalico.org/getting-started/kubernetes/self-managed-onprem/onpremises#install-calico-with-kubernetes-api-datastore-50-nodes-or-less
	export CNI_PLUGIN=calico
	wget https://docs.projectcalico.org/archive/v3.18/manifests/calico.yaml
	#wget https://docs.projectcalico.org/v3.18/manifests/${CNI_PLUGIN}.yaml
	sed -i "s/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/g" ${CNI_PLUGIN}.yaml
	sed -i "s/#   value: \"192.168.0.0\/16\"/  value: \"${POD_SUBNET/\//\\/}\"/g" ${CNI_PLUGIN}.yaml
	kubectl apply -f ${CNI_PLUGIN}.yaml

	#sed 's/canal_iface: ""/canal_iface: "eth1"/' -i ${CNI_PLUGIN}.yaml

	# Make sure the CNI_PLUGIN uses the correct network interface
	sleep 10
	kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD=interface=eth1
	# Delete the calico-node pods for the changes to take effect
	for pod in $(kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers=true | awk '{print $1}'); do kubectl delete pod -n kube-system $pod; done

	# And the DNS too
	for pod in $(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers=true | awk '{print $1}'); do kubectl delete pod -n kube-system $pod; done

	# Install kubectl calicoctl plugin
	cd /usr/local/bin
	curl -o kubectl-calico -L  https://github.com/projectcalico/calicoctl/releases/download/v3.18.0/calicoctl
	chmod +x kubectl-calico
	# kubectl calico -h

	# Install Helm
	echo "Install helm"
	wget https://get.helm.sh/helm-v3.5.2-linux-amd64.tar.gz
	tar -zxvf helm-v3.5.2-linux-amd64.tar.gz
	mv linux-amd64/helm /usr/local/bin/helm
	helm repo add stable https://charts.helm.sh/stable
	helm repo update

	# Keep showing status until everything is running
	until [[ $( kubectl get pods --field-selector=status.phase!=Running --all-namespaces 2>&1 ) == "No resources found" ]]
	do 
	    kubectl get pods --field-selector=status.phase!=Running --all-namespaces
	    sleep 10
	done
	kubectl taint nodes $(hostname) node.kubernetes.io/not-ready:NoSchedule
	kubectl taint nodes $(hostname) node-role.kubernetes.io/master:NoSchedule-


	# Install ingress-nginx
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.34.1/deploy/static/provider/baremetal/deploy.yaml # https://github.com/kubernetes/ingress-nginx/tree/master/deploy/static/provider/baremetal
	
	# see https://github.com/kubernetes/ingress-nginx/issues/5401
  # https://stackoverflow.com/questions/44519980/assign-external-ip-to-a-kubernetes-service
  # https://www.digitalocean.com/community/tutorials/how-to-set-up-an-nginx-ingress-with-cert-manager-on-digitalocean-kubernetes
  # https://github.com/kubernetes/ingress-nginx/issues/6655
	# there is some kind of bug? This needs to be deleted, see github issues above
	kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission
	
	# https://github.com/ansilh/kubernetes-the-hardway-virtualbox/blob/master/18.Ingress-Controller-using-NGINX.md/
	
	# The externalIPs list needs to be updated whenever new nodes are added
	# kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"externalIPs":["192.168.20.101", "192.168.20.201", "192.168.20.202"]}}'
	echo kubectl patch svc ingress-nginx-controller -n ingress-nginx -p "{\"spec\":{\"externalIPs\":[${ip_list}]}}"
	kubectl patch svc ingress-nginx-controller -n ingress-nginx -p "{\"spec\":{\"externalIPs\":[${ip_list}]}}"
	#kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"NodePort"}}'

	# Install Rancher
	helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
	kubectl create namespace cattle-system
	helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=rancher.my.org
	# Wait for Rancher to be rolled out
	kubectl -n cattle-system rollout status deploy/rancher

	# note: service replicas need to be 2 for some reason
	# setup 'echo1' service
	kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: echo1
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: echo1
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo1
spec:
  selector:
    matchLabels:
      app: echo1
  replicas: 2
  template:
    metadata:
      labels:
        app: echo1
    spec:
      containers:
      - name: echo1
        image: strm/helloworld-http 
        ports:
        - containerPort: 80
EOF

	# echo2
	kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: echo2
spec:
  ports:
  - port: 80
    targetPort: 5678
  selector:
    app: echo2
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo2
spec:
  selector:
    matchLabels:
      app: echo2
  replicas: 2
  template:
    metadata:
      labels:
        app: echo2
    spec:
      containers:
      - name: echo2
        image: hashicorp/http-echo
        args:
        - "-text=echo2"
        ports:
        - containerPort: 5678
EOF   
        
	# echo_ingress
	kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: echo-ingress
  annotations:
    # use the shared ingress-nginx
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - host: echo1.example.com
    http:
      paths:
      - backend:
          serviceName: echo1
          servicePort: 80
  - host: echo2.example.com
    http:
      paths:
      - backend:
          serviceName: echo2
          servicePort: 80
EOF

	# Deploy dashboard
	#kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0/aio/deploy/recommended.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended.yaml

	# Install metrics server
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	# kubectl -n kube-system edit deploy metrics-server`
	# add to args:	
        # - --kubelet-insecure-tls
	# edit:
        # - --kubelet-preferred-address-types=InternalIP
	# add below dnsPolicy:
	# hostNetwork: true
fi
echo "Finished provisioning $(hostname)!"
if [[ $THIS_NUM -eq 1 && $NODE_TYPE == "master" ]]
then
	echo "View join tokens at /root/kubeadm-init.out on $(hostname)"
fi
