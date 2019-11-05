Recommended to execute on clean native install of Ubuntu 18.04/19.04

```
#Dependencies
sudo apt install -y git

#Download source
git clone https://github.com/mikeanthony1/aic.git
cd aic

#Install Docker
#This only needs to be run once
./config.sh

#Download Android containers 
./aic.sh install

#Start Android containers
./aic.sh start
```
