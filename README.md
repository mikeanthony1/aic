Recommended to execute on clean native install of Ubuntu 18.04/19.04
```
#Go to sudo
sudo su
 
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
 
reboot
```

Install Docker 
```
#Go to sudo
sudo su

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

#Check that Docker is running
systemctl status docker

#If it's not working in the above step, try the below steps that start and enable Docker
systemctl start docker
systemctl enable docker
```

Download source using git clone
```
#Dependencies
sudo su
apt install -y git

#Download source
git clone https://github.com/mikeanthony1/aic.git

#Download Android containers 
./aic install

#Start Android containers
./aic start
```
