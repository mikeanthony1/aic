Recommended to execute on clean native install of Ubuntu 18.04/19.04

```
#Dependencies
sudo su
apt install -y git

#Download source
git clone https://github.com/mikeanthony1/aic.git

#Configure OS 
#Install ashmem/binder kernel modules
#Install Docker
#This only needs to be run once
./config.sh

#kernel module stuff
mkdir -p /dev/binderfs
mount -t binder binder /dev/binderfs

#Download Android containers 
./aic.sh install

#Start Android containers
./aic.sh start
```
