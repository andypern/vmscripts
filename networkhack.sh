#!/bin/bash

# for use on VM's that were cloned from 'cent6.4-master', first on a new host you have to 'dhclient eth2', to get an IP
# then scp this file in place and run

MAC=`ifconfig -a|grep HW|awk {'print $5'}`

CFG1=/etc/sysconfig/networking/devices/ifcfg-eth0
CFG2=/etc/sysconfig/network-scripts/ifcfg-eth0

sed -i.bak "s/^HWADDR/#OLD_HWADDR/" $CFG1
echo "HWADDR=${MAC}" >> $CFG1

rm -f ${CFG2}

cp ${CFG1} ${CFG2}

system-config-network

echo "now you need to reboot twice...here I'll do one for you"
sleep 5
reboot


