#!/bin/bash

#########config##########
#put hosts in here, comma separated, make sure they are resolvable in DNS
#also , put in groups file format for clustershell
#

MYHOSTS="hdp-nfs-1 hdp-nfs-2 hdp-nfs-3"
CLUSHGROUPS="all: hdp-nfs-[1-3]"
DISKS="sdb sdc"



######end config########



IP=`hostname -i`

yum install -y wget
cd /tmp

wget http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm


rpm -Uvh epel-release-6-8.noarch.rpm

yum install -y clustershell


ssh-keygen -t rsa 



for i in $MYHOSTS
	do ssh-copy-id -i /root/.ssh/id_rsa.pub root@${i}
done


echo $CLUSHGROUPS > /etc/clustershell/groups

clush -a 'yum install -y java-1.6.0-openjdk.x86_64' 

clush -a 'yum install -y ntp.x86_64 ntpdate' 


#set the time:
clush -a 'service ntpdate start'
sleep 10
clush -a 'service ntpdate stop'

clush -a 'service ntpd start'


clush -a 'chkconfig ntpd on'


clush -a 'setenforce 0'



#
#this is to make an fdisk.txt
#


FDISK="n p 1 a 1 t 83 w"

for i in $FDISK
	do echo $i >> /tmp/fdisk.txt
done

clush -a -c /tmp/fdisk.txt

#now to format the disks
clush -a 'yum install -y xfsprogs'

for disk in $DISKS
	do clush -a "cat /tmp/fdisk.txt | fdisk /dev/${disk}; mkfs.xfs /dev/${disk}1"
	echo "done with $disk"
done


# now make the 'grid' directories for HDP to use

for disk in $DISKS
	do clush -a "mkdir -p /grid/$disk"
done

clush -a "chmod -R 777 /grid"

# make an fstab

for disk in $DISKS
	do clush -a "echo "/dev/${disk}1 /grid/${disk} xfs defaults,noatime 0 0" >> /etc/fstab"
done


# mount new mounts

clush -a "mount -a"


clush -a "chmod -R 777 /grid"



wget http://public-repo-1.hortonworks.com/ambari/centos6/1.x/updates/1.4.3.38/ambari.repo

cp ambari.repo /etc/yum.repos.d/

#
#this seems to be required:
# 1) /etc/hosts: 192.168.6.136 hdp-nfs-1.localdomain hdp-nfs-1
# 2) /etc/resolv.conf : search localdomain
#						domain localdomain
#otherwise ambari pukes on install.

#echo "127.0.0.1    localhost" > /etc/hosts
# also, the there's an hdfs-site.xml param that can be changed to disable auth for datanode access.  

#clush -a -c /etc/hosts

yum install -y ambari-server

ambari-server setup   

ambari-server start

cat /root/.ssh/id_rsa

echo "use the key above for your private key"

echo "Login to http://${IP}:8080   , admin/admin"

#next/next/next� paste id_rsa (private key) from node-1.  you might get a warning about ntpd not running�no big deal since ntpdate is running.
#next/next/next: take defaults for now.

#also, you need to make sure to set this in the HDFS advanced section (winds up in hdfs-site.xml) : 
#     <name>dfs.datanode.du.reserved</name>
   # <value>107374182</value>
    
  #this is for vm's where there isn't a lot of space per disk, the default is 1GB, which may be too high (above value is ~100MB)
    



