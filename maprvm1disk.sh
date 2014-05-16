#!/usr/bin/bash

#assumes open-jdk is already installed, iptables disabled, and all hosts are resolvable somehow.

# this is a little manual, oh well.

#
#TODO : get mysql connector setup for hive metastore.
#

######config section..edit me######

CLUSTERNAME="shark"
#MAPRVERSION="3.0.2"
MAPRVERSION="3.0.3"
CENTOS_VERSION="6"
REPO_URL="192.168.6.1/package.mapr.com"
#REPO_URL="packages.mapr.com"


# MYHOSTS="mapr31-1 mapr31-2 mapr31-3"
# CLDBHOSTS="mapr31-1"
# ZK_HOSTS="mapr31-1"
# HIVE_HOST="mapr31-1"


MYHOSTS="shark-1 shark-2 shark-3"
CLDBHOSTS="shark-1"
ZK_HOSTS="shark-1,shark-2,shark-3"
HIVE_HOST="shark-1"

# CLUSHGROUPS_ALL="all: mapr31-[1-3]"
# CLUSHGROUPS_JT="jt: mapr31-1"
# CLUSHGROUPS_CLDB="cldb: mapr31-1"
# CLUSHGROUPS_ZK="zk: mapr31-1"
# CLUSHGROUPS_HIVE="hive: ${HIVE_HOST}"


CLUSHGROUPS_ALL="all: shark-[1-3]"
CLUSHGROUPS_JT="jt: shark-[3]"
CLUSHGROUPS_CLDB="cldb: shark-[1]"
CLUSHGROUPS_ZK="zk: shark-[1-3]"
CLUSHGROUPS_HIVE="hive: ${HIVE_HOST}"

DISKS="sdb sdc"

RAM_MIN=2430584



#####end config##########





set -x


install_prereqs () {
	
	yum clean all
	yum install -y wget
	
	
	cd /tmp
	
	if [ $CENTOS_VERSION = 6 ]
		then 
		wget http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
		rpm -Uvh epel-release-6-8.noarch.rpm
		EPEL_RPM="epel-release-6-8.noarch.rpm"
	elif [ $CENTOS_VERSION = 5 ]
		then
		wget http://dl.fedoraproject.org/pub/epel/5/x86_64/epel-release-5-4.noarch.rpm
		rpm -Uvh epel-release-5-4.noarch.rpm
		EPEL_RPM="epel-release-5-4.noarch.rpm"
	fi


	yum install -y clustershell
	
	
	ssh-keygen -t rsa 
	
	
	
	for i in $MYHOSTS
		do ssh-copy-id -i /root/.ssh/id_rsa.pub root@${i}
		scp -r /root/.ssh root@${i}:/root
	done
	
	
	
	echo $CLUSHGROUPS_ALL > /etc/clustershell/groups
	echo $CLUSHGROUPS_JT >> /etc/clustershell/groups
	echo $CLUSHGROUPS_CLDB >> /etc/clustershell/groups
	echo $CLUSHGROUPS_ZK >> /etc/clustershell/groups
	echo $CLUSHGROUPS_HIVE >> /etc/clustershell/groups
	
	#
	#check to see if all nodes have enough RAM
	#
	
	for HOST in $MYHOSTS
		do MEM=`ssh ${HOST} "free|grep Mem|egrep -o 'Mem:\s+[0-9]+'|egrep -o '[0-9]+'"`
		if [ ${MEM} -lt $RAM_MIN ]
			then echo "$HOST only has $MEM RAM, exiting"
			exit 1
		fi
	done
	
	
	
	clush -a 'setenforce 0'
	
	echo "[maprtech]" > /etc/yum.repos.d/maprtech.repo

	echo "name=MapR Technologies" >> /etc/yum.repos.d/maprtech.repo
	echo "baseurl=http://${REPO_URL}/releases/v${MAPRVERSION}/redhat/" >> /etc/yum.repos.d/maprtech.repo
	echo "enabled=1" >> /etc/yum.repos.d/maprtech.repo
	echo "gpgcheck=0" >> /etc/yum.repos.d/maprtech.repo
	echo "protect=1" >> /etc/yum.repos.d/maprtech.repo
	echo "" >> /etc/yum.repos.d/maprtech.repo
	
	echo "[maprecosystem]" >> /etc/yum.repos.d/maprtech.repo
	echo "name=MapR Technologies" >> /etc/yum.repos.d/maprtech.repo
	echo "baseurl=http://${REPO_URL}/releases/ecosystem/redhat/" >> /etc/yum.repos.d/maprtech.repo
	echo "enabled=1" >> /etc/yum.repos.d/maprtech.repo
	echo "gpgcheck=0" >> /etc/yum.repos.d/maprtech.repo
	echo "protect=1" >> /etc/yum.repos.d/maprtech.repo
	
	
	
	#copy to all nodes
	clush -a -c /etc/yum.repos.d/maprtech.repo
	
	# # TODO: dvd repo
	 clush -a "mkdir -p /media/cdrom"
	 clush -a "mount /dev/sr0 /media/cdrom"
	
	#This was something I started doing trying to make sure the DVD was really there..but for now we'll
	# just assume that it is and mark that repo as enabled. 
	 #DVDMINSIZE=3000000000
	# 
	 #for HOST in $MYHOSTS
	#	 do let ${HOST}_DVDSIZE=`ssh ${HOST} "du -bs /media/cdrom/Packages|awk {'print $1'}"`
	#	 if [ ${HOST}_${DVDSIZE} -gt $DVDMINSIZE ]
	#		 then clush -a 'sed -i "s/enabled=0/enabled=1/g" /etc/yum.repos.d/CentOS-Media.repo'
	#	fi
	#	done
	# 
	# 
	
	clush -a 'sed -i "s/enabled=0/enabled=1/g" /etc/yum.repos.d/CentOS-Media.repo'
	
	# get EPEL on other nodes
	clush -a -c /tmp/${EPEL_RPM}
	clush -a "rpm -Uvh /tmp/${EPEL_RPM}"
	
	#fix /etc/hosts
	echo "127.0.0.1       localhost.localdomain  localhost" > /etc/hosts
	clush -a -c /etc/hosts
	
	#setup mapR user
	clush -a 'useradd mapr'
	clush -a 'echo "mapr" | passwd --stdin mapr'
	
	#sudos
	echo "mapr ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
	clush -a -c /etc/sudoers
	#ssh keys for this user.
	
	su -l mapr -c 'ssh-keygen -t rsa'
	
	
	for i in $MYHOSTS
		do scp /home/mapr/.ssh/id_rsa.pub root@${i}:/home/mapr/.ssh/authorized_keys
		ssh $i "chown mapr /home/mapr/.ssh/authorized_keys"
		scp -r /home/mapr/.ssh root@${i}:/home/mapr
		ssh $i "chown -R mapr /home/mapr/.ssh"
	done
	
	
	
}


install_packages () {
	#lsof..is handy, plus we'll need mysql
	clush -a "yum clean all"
	clush -a "yum install -y --disablerepo=base,updates python-pip python-setuptools lsof mysql bind-utils ntp"
	clush -a "chkconfig ntpd on;service ntpd start"
	# fix java
	#clush -a "yum erase -y java-1.6.0-openjdk.x86_64"
	# clush -a "yum install --disablerepo=base,updates -y java-1.6.0-openjdk.x86_64"
	clush -a "yum install --disablerepo=base,updates -y java-1.7.0-openjdk-devel.x86_64"
	#all hosts
	clush -a "yum install -y nfs-utils"
	clush -a "yum install --disablerepo=base,updates -y mapr-fileserver mapr-tasktracker mapr-nfs mapr-webserver mapr-hive mapr-metrics mapr-pig"
	# cldb
	clush -g cldb "yum install -y mapr-cldb"
	#jt
	clush -g jt "yum install -y mapr-jobtracker"
	#zk
	clush -g zk "yum install -y mapr-zookeeper"
	# mysql server for hiveserver
	clush -g hive "yum install --disablerepo=base,updates -y mysql-server"
	clush -g hive "chkconfig --levels 235 mysqld on"
	clush -g hive "service mysqld start"
	# throw metrics on same host as hiveserver
	clush -g hive "yum install -y mapr-hivemetastore mapr-hiveserver2"
	
	
	
	
	if [ $MAPRVERSION = 3.0.* ]
		then
		echo "export JAVA_HOME=/usr/lib/jvm/java-1.7.0-openjdk.x86_64" >> /opt/mapr/conf/env.sh
	clush -a -c /opt/mapr/conf/env.sh
		else
		#on 3.1	, we don't need java stuff, but we need to hack configure.sh
		sed -i 's/memNeeded=4096/memNeeded=2800/' /opt/mapr/server/configure.sh
		clush -a -c /opt/mapr/server/configure.sh 
	fi

	clush -a "ls /opt/mapr/roles"
	
}


config_mapr () {
	
	clush -a "/opt/mapr/server/configure.sh -C ${CLDBHOSTS} -Z ${ZK_HOSTS} -N ${CLUSTERNAME} -M7"
	

	#clush -a "/opt/mapr/server/configure.sh -C ${CLDBHOSTS} -Z ${ZK_HOSTS} -N ${CLUSTERNAME}"
	rm -f /tmp/disks.txt
	for disk in $DISKS
		do echo "/dev/${disk}" >> /tmp/disks.txt
	done
	clush -a -c /tmp/disks.txt
	
	clush -a "/opt/mapr/server/disksetup -F /tmp/disks.txt"
	
	# this is for VMs
	# need to strip trailing configuration tag before inserting some stuff.
	sed -i -r "s/<\/configuration>//" /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml
	
	
	echo "<!--edit for vms..-->" >> /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml
	echo "<property><name>mapreduce.tasktracker.reserved.physicalmemory.mb</name>" >> /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml
	echo "<value>2048</value>" >> /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml
	echo "</property>" >> /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml
	echo "</configuration>" >> /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml
	clush -a -c /opt/mapr/hadoop/hadoop-0.20.2/conf/mapred-site.xml
	
	#hack for hive
	clush -a "mkdir -p /opt/mapr/hive/hive-0.12/logs"
	clush -a "mkdir -p /opt/mapr/hive/hive-0.12/pids"
	clush -a "chown -R mapr /opt/mapr/hive/hive-0.12/*"
	
	
	
	
	echo "if all went well, everything is installed.  If need be, you may need to modify some warden.conf parameters for VMs"
	echo "you'll also need to perform steps to get metrics and hive metastore talking to mysqld"
}

start_services () {
	
	clush -a "service rpcbind start"
	
	clush -f 1 -g zk "service mapr-zookeeper start;sleep 5"	
	clush -f 1 -g zk "service mapr-zookeeper qstatus;sleep 2"	
	echo "sleeping for 60 secs for zookeepers to settle"
	sleep 60;
	clush -g cldb "service mapr-warden start;sleep 60"
	#check for cldb running
	clush -g cldb "maprcli node cldbmaster"
	

	
}


license () {

		#put license in
	
	cd /tmp
	wget http://192.168.6.1/90DayDemoLicense-M7.txt
	maprcli license add -is_file true -license /tmp/90DayDemoLicense-M7.txt
	
	
	#setup NFS localhost mount

	clush -a 'mkdir -p /mapr'
	echo "localhost:/mapr /mapr soft,intr,nolock" > /opt/mapr/conf/mapr_fstab
	clush -a -c /opt/mapr/conf/mapr_fstab
	
	#restart warden to take the license.
	
	
	#now run warden on the rest
	clush -a "service mapr-warden restart"
	sleep 60
	#clush -a "service rpcbind start"
	sleep 10
	


}
nuke_it () {
	clush -a "yum erase -y mapr-*"
	clush -a "yum erase -y mysql"
	clush -a "rm -rf /var/lib/mysql"
	clush -a "rm -rf /opt/mapr"
	clush -a "userdel -f mapr"
	clush -a "rm -rf /home/mapr"
	clush -a "killall -9 mfs"	
	clush -a "killall -9 java"
}

config_metrics () {
	#TODO : this assumes you are running this entire script on $HIVE_HOST, perhaps use the host directive..or clush.
	mysql -u root -e "SET PASSWORD for 'root'@'localhost' = PASSWORD('mapr');"
	mysql -u root --password=mapr -e  "SET PASSWORD for 'root'@'127.0.0.1' = PASSWORD('mapr');"
	mysql -u root --password=mapr -e "SET PASSWORD for 'root'@'${HIVE_HOST}' = PASSWORD('mapr');"
	mysql -u root --password=mapr -e "DROP USER ''@'localhost';"
	mysql -u root --password=mapr -e "DROP USER ''@'${HIVE_HOST}';"
	mysql -u root --password=mapr -e "CREATE USER 'root'@'%' IDENTIFIED BY 'mapr';"
	mysql -u root --password=mapr -e "CREATE DATABASE metrics;"
	mysql -u root --password=mapr -e "GRANT ALL PRIVILEGES ON `metrics`.* TO 'root'@'%' WITH GRANT OPTION;"
	
	#grants
	mysql -u root --password=mapr -e "GRANT ALL ON *.* TO 'root'@'%';"
	
	#dump useful stuff to screen
	mysql -u root --password=mapr -e "select user,host,password from mysql.user;"
	
	mysql -u root --password=mapr -e "show grants;"
	
	mysql -h ${HIVE_HOST} -u root --password=mapr -e "show grants;"
	
	ldconfig
	
	mysql -u root --password=mapr -vvv < /opt/mapr/bin/setup.sql > /opt/mapr/logs/setup_sql_results.txt
	tail -n 5 /opt/mapr/logs/setup_sql_results.txt
	
	clush -a "/opt/mapr/server/configure.sh  -R -d ${HIVE_HOST}:3306 -du root -dp mapr -ds metrics"
	sleep 10;
	
	# this file needs fixing up 
	
	clush -a -c /opt/mapr/conf/hibernate.cfg.xml
	sleep 10;
	#restart hoststats on all nodes
	
}

config_hive () {
	# first, figure out what HIVE rev we have:
	HIVE_REV=`ls -l /usr/bin/hive |awk {'print $11'}|egrep -o 'hive-0\.[0-9]{2}'`
	MYHIVE_HOME=/opt/mapr/hive/${HIVE_REV}
	echo "export HIVE_HOME=${MYHIVE_HOME}" >> /opt/mapr/conf/env.sh
	clush -a -c /opt/mapr/conf/env.sh
	
	#grab the JDBC connector so HIVE can talk to mysql
	
	cd /tmp
	curl -L 'http://www.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.18.tar.gz/from/http://mysql.he.net/|http://mysql.he.net/' | tar xz
	cp mysql-connector-java-5.1.18/mysql-connector-java-5.1.18-bin.jar ${MYHIVE_HOME}/lib
	
	chmod 755 ${MYHIVE_HOME}/lib/mysql*jar
	
	# grab the template hive-site.xml
	rm -f hive-site.xml
	wget http://192.168.6.1/config/hive-site.xml
	
	#fix variables for hosts
	sed -i -r "s/ZK_REPLACEME/${ZK_HOSTS}/g" hive-site.xml
	sed -i -r "s/MYSQL_REPLACEME/${HIVE_HOST}/g" hive-site.xml
	
	cp -f /tmp/hive-site.xml ${MYHIVE_HOME}/conf/hive-site.xml
	
	clush -a -c ${MYHIVE_HOME}/conf/hive-site.xml
	
	
	# restart the service..again this assumes we are running directly on the host running this
	sleep 30;
	
	maprcli node services -name hivemeta -action restart -nodes `hostname -f`
	
	# wait 30 seconds..then tail the log to make sure nothing ugly shows up
	sleep 30;
	tail -n 5 ${MYHIVE_HOME}/logs/*metastore*.out
	#check to see if the port is open
	lsof -i:9083
	
	
	# now restart hiveserver2
	maprcli node services -name hs2 -action restart -nodes `hostname -f`
	sleep 60
	lsof -i:10000
	
	#test connection w/ beeline
	/usr/bin/hive --service beeline -u jdbc:hive2://${HIVE_HOST}:10000 -n mapr -p mapr -d org.apache.hive.jdbc.HiveDriver -e "show tables;"

	
}

nuke_it
install_prereqs
install_packages
config_mapr
config_metrics
start_services
config_hive
#license


