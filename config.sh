#!/bin/sh

#Install dependencies
apt install -y make gcc wget unzip curl
 
#Download Source
FILE=master.zip
if [ ! -f "$FILE" ]; then
	wget https://github.com/projectceladon/kernel-modules-cic/archive/master.zip
	unzip $FILE
fi
 
#TODO Ugly checking... improve
if ! lsmod | grep ashmem; then
	#Make kernel modules
	cd kernel-modules-cic-master
	make -C ashmem -j `nproc`
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

if [ ! -d /dev/binderfs ]; then
	mkdir -p /dev/binderfs
	mount -t binder binder /dev/binderfs
fi

 
#Get official Docker GPG key
if ! hash docker 2> /dev/null; then
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

	#Add Docker repo to apt resources and update package database
	add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable edge"
	apt-get update

	#This step can be used to check all previous steps worked
	apt-cache policy docker-ce

	#Install Docker
	apt-get install -y docker-ce
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

#Replacing ./aic install functions
WORK_DIR="$(pwd)/workdir"
APP_DIR="$WORK_DIR/app/installed"
CPU_DIR="$(pwd)/workdir/cpu/"

mkdir -p $WORK_DIR
mkdir -p $APP_DIR
mkdir -p $CPU_DIR

