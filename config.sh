#!/bin/sh

#Install dependencies
echo "Installing any missing commands"
apt install -y make gcc wget unzip curl android-tools-adb android-tools-fastboot > /dev/null 2>&1
 
#Download Source
FILE=master.zip
if [ ! -f "$FILE" ]; then
	wget https://github.com/projectceladon/kernel-modules-cic/archive/master.zip
	unzip $FILE
fi
 
#TODO Ugly checking... improve
if ! lsmod | grep binder_module > /dev/null; then
	#Make kernel modules
	cd kernel-modules-cic-master
	make -C ashmem -j `nproc`

	if cat /etc/issue | grep -q "19.10"; then 
		patch -p1 < ../binder-fix.patch
	fi
	make -C binder -j `nproc`
 
	#Create library destination
	export DESTDIR=/lib/modules/`uname -r`/extra
	mkdir -p $DESTDIR
 
	#Install kernel modules
	make -C ashmem -j `nproc` install
	insmod ashmem/ashmem_module.ko
	make -C binder -j `nproc` install
	depmod
	printf "\nashmem_module\nbinder_module\nbinderfs_module\n" >> /etc/modules
else
	echo "Skipping ashmem/binder installation"
fi

#Install Docker
if ! hash docker 2> /dev/null; then
	#Leaving open for other Linux Distros
	if cat /etc/issue | grep -q "Ubuntu"; then 
		apt install -y docker.io
	else
		echo "This script does not support installing Docker on this Linux Distro"
	fi
else
	echo "Skipping Docker Install"
fi

if ! hash docker-compose 2> /dev/null; then
	#Get Compose Binary
	curl -L "https://github.com/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

	#Set run attribute
	chmod +x /usr/local/bin/docker-compose
else
	echo "Skipping docker-compose install"
fi

