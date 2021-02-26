#!/bin/bash

# test from outside the cluster; adjust the IPs as needed
array=( 192.168.20.101 192.168.20.201 192.168.20.202 ); for i in "${array[@]}"
do
        curl -H "Host: echo1.example.com" $i;
        curl -H "Host: echo2.example.com" $i;
done
