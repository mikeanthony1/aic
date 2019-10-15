Recommended to execute on clean native install of Ubuntu 18.04/19.04

```
#Dependencies
sudo su
cd
apt install -y git

#Download source
git clone https://github.com/mikeanthony1/aic.git
cd aic

#Configure OS 
#Install ashmem/binder kernel modules
#Install Docker
#This only needs to be run once
./config.sh

#Configure x11 to accept connection from AIC
xhost +

#Start up
docker-compose up

#Bring down
docker-compose down
```

Running subsequent times (after reboot)

```
#Run these commands to initialize x11 and binder
mkdir -p /dev/binderfs
mount -t binder binder /dev/binderfs
xhost +

#Start up
docker-compose up

#Bring down
docker-compose down
```
