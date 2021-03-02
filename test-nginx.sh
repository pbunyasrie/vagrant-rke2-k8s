#!/bin/bash

# test from outside the cluster; adjust the IPs as needed
array=( 192.168.20.101 192.168.20.201 192.168.20.202 ); for i in "${array[@]}"
do
        curl --connect-timeout 5 -H "Host: echo1.example.com" $i;
        curl --connect-timeout 5 -H "Host: echo2.example.com" $i;
done
