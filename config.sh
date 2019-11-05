#!/bin/sh

#Install dependencies
sudo apt install -y curl adb
 
#Get official Docker GPG key
if ! hash docker 2> /dev/null; then
	sudo apt-get install apt-transport-https ca-certificates curl
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
	sudo apt-get update
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io
	sudo usermod -aG docker $USER
else
	echo "Skipping Docker Install"
fi

