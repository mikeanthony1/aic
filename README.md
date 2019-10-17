Recommended to execute on clean native install of Ubuntu 18.04/19.04

OS Setup
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
#Install docker/docker-compose
./config.sh
```

AIC run commands
```
#Start AIC
#Logs will automatically display on terminal
./aic-compose.sh

#Stop AIC
docker-compose down
```
