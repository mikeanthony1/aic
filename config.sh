#!/bin/sh

#Install dependencies
apt install -y make gcc wget unzip
 
#Download Source
wget https://github.com/projectceladon/kernel-modules-cic/archive/master.zip
unzip master.zip
 
#Make kernel modules
cd kernel-modules-cic-master
make -C ashmem -j `nproc`
make -C binder -j `nproc`
 
#Create library destination
export DESTDIR=/lib/modules/`uname -r`/extra
mkdir -p $DESTDIR
 
#Install kernel modules
make -C ashmem -j `nproc` install
make -C binder -j `nproc` install
depmod
printf "\nashmem_module\nbinder_module\nbinderfs_module\n" >> /etc/modules
 
#Get official Docker GPG key
apt install -y curl
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

#Add Docker repo to apt resources and update package database
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable edge"
apt-get update

#This step can be used to check all previous steps worked
apt-cache policy docker-ce

#Install Docker
apt-get install -y docker-ce

