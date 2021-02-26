# Vagrant Kubernetes
Sets up a vanilla Kubernetes environment using kubeadm:

- 1 master
- 2 workers

All running on CentOS 8.

Additionally sets up:

- calico (CNI)
- ingress-nginx
- helm

# Setup
```
vagrant up
```

Once all of the servers have been setup, SSH into the master:
```
vagrant ssh master-1
```

Obtain the worker join command from `/root/kubeadm-init.out`, which we will run on each worker. Example:
```
$ tail -n2 /root/kubeadm-init.out
kubeadm join 192.168.20.101:6443 --token xx.yyzz \
    --discovery-token-ca-cert-hash sha256:xxyyzz
```

Then, SSH into each worker and run the worker join command from above.
```
vagrant ssh worker-1
```

# Production
Because dnsmasq is used in /etc/resolv.conf in production, the nameserver points to 127.0.0.1. CoreDNS needs to be updated to forward.
```
kubectl -n kube-system edit configmap/coredns
```

Then change
```
forward . /etc/resolv.conf {
```

to

```
forward . <master ip> {
```

# TODO
- Look into automating worker joining during provisioning process, via NFS 
