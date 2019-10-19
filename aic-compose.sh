#!/bin/sh

function umount_binderfs() {
    if [[ $(findmnt "/dev/binderfs") ]]; then
        echo "Umount binderfs..."
        find /dev/binderfs/*binder*[0-9] 2> /dev/null | while read line; do
            sudo unlink $line
        done
        sudo umount /dev/binderfs
    fi
}

#binder setup
umount_binderfs
sudo mkdir -p /dev/binderfs
sudo mount -t binder binder /dev/binderfs

#working directories
WORK_DIR="$(pwd)/workdir"
APP_DIR="$WORK_DIR/app/installed"
CPU_DIR="$WORK_DIR/cpu/"
IPC_DIR="$WORK_DIR/ipc/config/input"

mkdir -p $WORK_DIR
mkdir -p $APP_DIR
mkdir -p $CPU_DIR
mkdir -p $IPC_DIR

xhost +

sudo docker-compose up -d

echo "aic started!"
echo "It safe to press CTRL+C at any time to stop following logs"
sleep 1
docker-compose logs -f

