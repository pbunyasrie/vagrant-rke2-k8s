#!/usr/bin/env bash

THIS_NUM=$1
THIS_IP=$2
NODE_TYPE=$3


dnf -y update --nobest && dnf -y upgrade --nobest

dnf install -y wget curl conntrack-tools vim net-tools telnet tcpdump bind-utils kmod nmap-ncat python3 git

echo 'set host name resolution'
for ((i=1;i<=$MASTERS;i++)); do
    echo ${KUBE_SUBNET}.10$i master-$i
done >> /etc/hosts

for ((i=1;i<=$WORKERS;i++)); do
    echo ${KUBE_SUBNET}.20$i worker-$i
done >> /etc/hosts

echo 'set nameserver'
echo "nameserver 8.8.8.8">/etc/resolv.conf
cat /etc/resolv.conf

# TODO: Setup haproxy for load balancing between masters in dev environment, or use F5 BigIP
# echo "$CONTROL_PLANE_ENDPOINT vagrant-k8s" >> /etc/hosts

cat /etc/hosts

echo 'disable swap'
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab
#sed -i '/swap/d' /etc/fstab

# There is an issue with selinux preventing Rancher (but not RKE2) from successfully deploying, so disable it for now
# see https://github.com/rancher/rancher/issues/26596
echo 'disable selinux'
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux

source <(kubectl completion bash)
echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH=$PATH:/usr/local/bin:/var/lib/rancher/rke2/bin" >> ~/.bashrc
echo "source <(kubectl completion bash)" >> ~/.bashrc
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH=$PATH:/usr/local/bin:/var/lib/rancher/rke2/bin

# Install RKE2
# see https://docs.rke2.io/install/quickstart/
if [[ $NODE_TYPE == "master" ]]; then
  # Configure CNI
  # see https://docs.rke2.io/install/network_options/
  mkdir -p /var/lib/rancher/rke2/server/manifests/
  cat <<EOF >  /var/lib/rancher/rke2/server/manifests//rke2-canal-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-canal
  namespace: kube-system
spec:
  valuesContent: |-
    flannel:
      iface: "eth1"
EOF

  curl -sfL https://get.rke2.io | sh -
  systemctl enable rke2-server.service
  systemctl start rke2-server.service
  cat <<EOF >  /etc/rancher/rke2/config.yaml
advertise-address: "192.168.20.101"
tls-san:
  - "foo.local"
node-label:
  - "foo=bar"
  - "something=amazing"
EOF

	# Keep showing status until everything is running
	until [[ $( kubectl get pods --field-selector=status.phase!=Running --all-namespaces 2>&1 ) == "No resources found" ]]
	do 
	    kubectl get pods --field-selector=status.phase!=Running --all-namespaces
	    sleep 10
	done


  # Ensure that Canal uses the correct network interface if there are multiple interfaces
  sleep 10
  kubectl set env daemonset/rke2-canal -n kube-system IP_AUTODETECTION_METHOD=interface=eth1
  # Delete the calico-node pods for the changes to take effect
	for pod in $(kubectl get pods -n kube-system -l k8s-app=canal --no-headers=true | awk '{print $1}'); do kubectl delete pod -n kube-system $pod; done

	# And the DNS too
	for pod in $(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers=true | awk '{print $1}'); do kubectl delete pod -n kube-system $pod; done


	# Install Helm
	echo "Installing helm..."
	wget https://get.helm.sh/helm-v3.5.2-linux-amd64.tar.gz
	tar -zxvf helm-v3.5.2-linux-amd64.tar.gz
	mv linux-amd64/helm /usr/local/bin/helm
	helm repo add stable https://charts.helm.sh/stable
	helm repo update

  # Install Rancher
  helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
  kubectl create namespace cattle-system

  # Install cert-manager as a dependency
  # Install the CustomResourceDefinition resources separately
  kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.0.4/cert-manager.crds.yaml

  # **Important:**
  # If you are running Kubernetes v1.15 or below, you
  # will need to add the `--validate=false` flag to your
  # kubectl apply command, or else you will receive a
  # validation error relating to the
  # x-kubernetes-preserve-unknown-fields field in
  # cert-manager’s CustomResourceDefinition resources.
  # This is a benign error and occurs due to the way kubectl
  # performs resource validation.

  # Create the namespace for cert-manager
  kubectl create namespace cert-manager

  # Add the Jetstack Helm repository
  helm repo add jetstack https://charts.jetstack.io

  # Update your local Helm chart repository cache
  helm repo update

  # 
  ln -s /etc/rancher/rke2/rke2.yaml /root/.kube/config

  # Install the cert-manager Helm chart
  helm install \
    cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.0.4A

  helm install rancher rancher-stable/rancher \
    --namespace cattle-system \
    --set hostname=rancher.my.org

  # kubectl -n cattle-system rollout status deploy/rancher


else
  curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -
  systemctl enable rke2-agent.service
  mkdir -p /etc/rancher/rke2/
  cat <<EOF >  /etc/rancher/rke2/config.yaml
server: https://<server>:9345
token: <token from server node>
node-ip: ${THIS_IP}
EOF

fi

# Lock package versions
dnf install python3-dnf-plugin-versionlock -y
dnf versionlock rke2*
dnf versionlock list

echo "Finished provisioning $(hostname)!"
if [[ $THIS_NUM -eq 1 && $NODE_TYPE == "master" ]]; then
	echo "View join tokens at /var/lib/rancher/rke2/server/node-token on $(hostname)"
  echo "Run 'journalctl -u rke2-server -f' to view the logs"
elif [[ $THIS_NUM -eq 1 && $NODE_TYPE == "master" ]]; then
  echo "vim /etc/rancher/rke2/config.yaml"
  echo "Run 'journalctl -u rke2-server -f' to view the logs"
else
  echo "Edit '/etc/rancher/rke2/config.yaml'"
	echo "View join tokens from the master at '/var/lib/rancher/rke2/server/node-token'"
  echo "Then run 'systemctl start rke2-agent.service'"
  echo "Run 'journalctl -u rke2-agent -f' to view the logs"
fi
