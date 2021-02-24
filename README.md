# K8S

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
