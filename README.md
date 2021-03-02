# Vagrant RKE2 (Kubernetes)
Sets up a multi-node RKE2 Kubernetes environment in Vagrant, complete with Rancher. All nodes run CentOS 8.

The cluster consists of:
- 1 master
- 2 workers

Features:
- CNI: Canal
- Ingress: ingress-nginx

Additionally sets up:
- Rancher 2.5 via helm

# Setup
```
vagrant up
```

Once all of the servers have been setup, SSH into the master:
```
vagrant ssh master-1
```

Obtain the token from `/var/lib/rancher/rke2/server/node-token`, which we will use to configure on each worker.

Then, SSH into each worker and configure `etc/rancher/rke2/config.yaml` with the token from above.
```
vagrant ssh worker-1
```


# TODO
- Look into automating worker joining during provisioning process, via NFS 

# Troubleshooting
## DNS
You can use dnsutils to ping pods from node to node.
```
kubectl apply -f https://k8s.io/examples/admin/dns/dnsutils.yaml
kubectl exec -i -t dnsutils -- nslookup kubernetes.default
```

# References
- https://www.jeffgeerling.com/blog/2019/debugging-networking-issues-multi-node-kubernetes-on-virtualbox

## RKE2
- https://docs.rke2.io/install/quickstart/
- https://docs.rke2.io/install/install_options/server_config/
- https://docs.rke2.io/install/install_options/agent_config/
- https://github.com/rancher/rke2

## Rancher
- https://rancher.com/docs/rancher/v2.x/en/installation/install-rancher-on-k8s/#2-add-the-helm-chart-repository
