#!/bin/sh

#binder setup
mkdir -p /dev/binderfs
mount -t binder binder /dev/binderfs

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

docker-compose up -d

echo "aic started!"
echo "It safe to press CTRL+C at any time to stop following logs"
sleep 1
docker-compose logs -f

