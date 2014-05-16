#!/usr/bin/bash


yum install -y wget

cd /tmp
wget http://192.168.6.1/releases/v3.1.0/redhat/mapr-setup
chmod +x mapr-setup
bash ./mapr-setup

/opt/mapr-installer/bin/install --skip-checks
