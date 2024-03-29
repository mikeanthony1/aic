#!/bin/bash

IMAGE_TAG=latest
DOCKER_HUB_USER=mikeanthony
C_AIC_MANAGER_NAME=aic-manager
C_AIC_ANDROID_NAME=android

if [ ! -z "$DOCKER_HUB_USER" ]; then
    DH_AIC_MANAGER_NAME="${DOCKER_HUB_USER}/${C_AIC_MANAGER_NAME}"
    DH_AIC_ANDROID_NAME="${DOCKER_HUB_USER}/${C_AIC_ANDROID_NAME}"
else
    DH_AIC_MANAGER_NAME="${C_AIC_MANAGER_NAME}"
    DH_AIC_ANDROID_NAME="${C_AIC_ANDROID_NAME}"
fi
if [ ! -z "$IMAGE_TAG" ]; then
    TAG_AIC_MANAGER_IMAGE="$DH_AIC_MANAGER_NAME:$IMAGE_TAG"
    TAG_AIC_ANDROID_IMAGE="$DH_AIC_ANDROID_NAME:$IMAGE_TAG"
else
    TAG_AIC_MANAGER_IMAGE="$DH_AIC_MANAGER_NAME"
    TAG_AIC_ANDROID_IMAGE="$DH_AIC_ANDROID_NAME"
fi  

function check_num {
    case $1 in
        ''|*[!0-9]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

function check_docker {
    if [ ! -x "$(command -v docker)" ]; then
        echo "[AIC] docker not installed, please install it first!"
        exit -1
    fi
}

function check_kernel_header {
    if [ -z "$(ls /dev/binder* 2>/dev/null)" ] && [ ! -d "/lib/modules/$(uname -r)/build" ]; then
        echo "[AIC] Kernel headers not installed, please install it first using below commands:"
        if [ "$OS_TYPE" = "ubuntu" ]; then
            echo "sudo apt install linux-headers-\$(uname -r)"
        else
            echo -e "sudo ros service enable kernel-headers\nsudo ros service up kernel-headers"
        fi
        exit -1
    fi
}

function check_containers {
    if [ -z "$($DOCKER ps -a | awk '{print $NF}' | grep -w $C_AIC_MANAGER_NAME)" ]; then
        echo "[AIC] $C_AIC_MANAGER_NAME container not existed, please re-install aic!"
        exit -1
    fi
    if [ -z "$($DOCKER ps -a | awk '{print $NF}' | grep $C_AIC_ANDROID_NAME)" ]; then
        echo "[AIC] $C_AIC_ANDROID_NAME container does not exist, please re-install aic!"
        exit -1
    fi
}

function parse_ids {
    if [ "${#IDS[@]}" -eq 0 ]; then
        CONTAINERS=($($DOCKER ps -a | awk '{print $NF}' | grep android))
    else
        for id in ${IDS[@]}
        do
            if [ -z "${id##*~*}" ]; then
                IFS='~' read -ra ID_RANGE <<< "$id"
                if [ "${#ID_RANGE[@]}" -ne 2 ] || ! check_num ${ID_RANGE[0]} || ! check_num ${ID_RANGE[1]}; then
                    echo "$USAGE"
                    exit -1
                fi
                for c in $(seq ${ID_RANGE[0]} ${ID_RANGE[1]})
                do
                    CONTAINERS+=(android$c)
                done
            else
                if ! check_num $id; then
                    echo "$USAGE"
                    exit -1
                fi
                CONTAINERS+=(android$id)
            fi
        done
    fi
}

function get_cpu_set()
{
    typeset -i container_id
    container_id=`expr $1`
    platform_type=$2

    if [ "$platform_type" = "nuc" ]; then
        cpu_num_str=`nproc --all`
        cpu_num=`expr $cpu_num_str`

        if [ $cpu_num -le 4 ];then
            interval=$cpu_num
        else
            interval=4
        fi

        loop_len=$(($cpu_num/$interval))
        remainder=$(($container_id%$loop_len))
        cpuset="$(($interval*$remainder))-$(($interval*$remainder+$interval-1))"

    elif [ "$platform_type" = "server" ]; then
        max_core_num=${#process_dict_key[@]}

        if [ $max_core_num -le 2 ];then
            interval=$max_core_num
        else
            interval=2
        fi
        loop_len=$(($max_core_num/$interval))
        remainder=$(($container_id%$loop_len))
        start_index=$(($interval*$remainder))
        end_index=$(($interval*$remainder+$interval-1))
        cpuset="${process_dict[${process_dict_key[$start_index]}]}${process_dict[${process_dict_key[$end_index]}]}"
        cpuset=${cpuset/%,}

    else
        echo "Unknow platform type, exit..."
        exit -1
    fi

    echo $cpuset
}

function process_wait_tips()
{
    INTERVAL=0.2
    TIPS=$1
    TIMEOUT=$2

    echo $TIPS
    iter=0
    while [ $iter -lt $TIMEOUT ]
    do
        for j in '-' '\\' '|' '/'
        do
            echo -ne "\033[1D$j"
            sleep $INTERVAL
        done
        ((iter++))
    done

    echo "Process waiting timeout, exit....."
}

function get_socket_core_process_info()
{
    lscpu -p >> ./tmp_$$
    while read line; do
        if [[ "$line" == "#"* ]];then
            continue;
        fi

        p_id=`echo $line | cut -d "," -f 1`
        c_id=`echo $line | cut -d "," -f 2`
        s_id=`echo $line | cut -d "," -f 3`

        index_key=$s_id-$c_id
        process_dict+=([$index_key]="$p_id,")

    done < ./tmp_$$
    rm ./tmp_$$

    process_dict_key=( $(
        for key in ${!process_dict[@]}
        do
            echo "$key"
        done | sort ) )
}

# Get memory node id of all CPU
function get_all_cpu_mem_node() {
  local newarray
  newarray=($(echo "$@"))

  cut_ret=`lscpu -p | while read line; do  if [[ "$line" == "#"* ]];then continue; else echo $line | cut -d "," -f 4;i=$((i+1)); fi; done`
  for ((i=0;i<$cpu_num;i=i+1))
    do
          newarray[$i]=`echo $cut_ret | cut -d " " -f $((i+1))`
        done
  echo ${newarray[*]}
}

# Get memory node by cpu core id
function get_mem_node_by_cpuid() {

    typeset  mem_node_id

    cpu_ids=$(echo $1 | tr "," "\n")
    for _id in $cpu_ids
      do
        if [ -z $mem_node_id ]; then
          mem_node_id="${cpu_mem_node_arr[$_id]}"
        else
          mem_node_id="${cpu_mem_node_arr[$_id]},$mem_node_id"
        fi
      done

    echo $mem_node_id
}

function create_fake_sys_cpu() {

    # Simply create fake cpu info folder and mount the folder to android container
    fake_cpu_path=$1

    if [ -z "$fake_cpu_path" ]; then
        echo "No fake cpu path specify, useing default path, ./workdir/cpu"
        fake_cpu_path="$(pwd)/workdir/cpu/"
    fi

    if [ ! -d $fake_cpu_path ]; then
        mkdir -p $fake_cpu_path
    fi

    echo "Create fake CPU information for containers under path $fake_cpu_path....."
}

function umount_fuse_folder()
{
    if [[ $(findmnt "$(pwd)/workdir/cpu") ]]; then
        echo "Umount FUSE cpu info folder... "
        sudo umount "$(pwd)/workdir/cpu"
     fi
}

function increase_limits() {
    # Increase iNotify
    sudo su - root -c 'echo "2560" >  /proc/sys/fs/inotify/max_user_instances'
    # Increate pid_max
    sudo su - root -c 'echo "280224" > /proc/sys/kernel/pid_max'
    # Increase PID cgroup pid max
    sudo su - root -c 'echo "600000" > /sys/fs/cgroup/pids/user.slice/user-1000.slice/pids.max'
    # Enable KSM
    sudo su - root -c 'echo "1" > /sys/kernel/mm/ksm/run'
    # Change KSM parameters
    sudo su - root -c 'echo "1000" > /sys/kernel/mm/ksm/sleep_millisecs'
    sudo su - root -c 'echo "1000" > /sys/kernel/mm/ksm/pages_to_scan'
}

function mount_binderfs() {
    if [ ! -d "/dev/binderfs" ]; then
        echo "Create binderfs mount point /dev/binderfs..."
        sudo mkdir -p /dev/binderfs
    fi
    umount_binderfs

    while [ -z "$(grep -e "binderfs_module" /proc/modules)" ]
    do
        echo "[AIC] Waiting for binderfs module installed..."
        sleep 1
    done

    sudo mount -t binder binder /dev/binderfs
}

function umount_binderfs() {
    if [[ $(findmnt -M "/dev/binderfs") ]]; then
        echo "Umount binderfs..."
        find /dev/binderfs/*binder*[0-9] 2> /dev/null | while read line; do
            sudo unlink $line
        done
        sudo umount /dev/binderfs
    fi
}

SYSTEM_IMAGE_MOUNT_OPTIONS=
function get_system_image_mount_options() {
    images=$($DOCKER run --rm -it --entrypoint /bin/sh $TAG_AIC_MANAGER_IMAGE -c '[ -d /images ] && cd /images && ls *.img' | tr -d '\r')
    if [ -n "$images" ]; then
        mountd=$(pwd)/workdir/media
        echo "[AIC] system images: $images"
        for img in $images
        do
            name=$(basename $img .img)
            dest=$mountd/$name
            SYSTEM_IMAGE_MOUNT_OPTIONS="$SYSTEM_IMAGE_MOUNT_OPTIONS -v $dest:/$name:ro"
        done
        echo "[AIC] mount options: $SYSTEM_IMAGE_MOUNT_OPTIONS"
    fi
}

function setup_server_env()
{
    cpu_num=`expr \`nproc --all\``
    for ((i=0;i<$cpu_num;i=i+1))
    do
      cpu_mem_node_arr[i]=0
    done

    process_wait_tips "Collecting socket/core/process/memory node Info, this may take a while" 20 &
    wait_tips_pid=$!
    # Gather all socket/core/process info
    get_socket_core_process_info

    # Gather all memory nodes information
    cpu_mem_node_arg=$(echo ${cpu_mem_node_arr[*]})
    cpu_mem_node_arr=($(get_all_cpu_mem_node $cpu_mem_node_arg))
    kill -s PIPE $wait_tips_pid &

    echo "Generate fake CPU information for containers...."
    if [ -d $WORK_DIR/cpu ]; then
        echo "Delete previous CPU folder!"
        sudo rm -rf $WORK_DIR/cpu
    fi
    create_fake_sys_cpu $WORK_DIR/cpu
}

function install {
    USAGE=$(cat <<- EOM

	Usage: aic install [OPTIONS]

	Load and install Android container images.

	Options:
	  -c, --cts                    Install AIC for CTS test enviroment.
	  -e, --emulated-input         Create and use emulated touch screen as primary input device. It's used
	                               by OpenSTF.
	  -i, --emulated-wifi          Create and use emulated wifi device for network connection.
	  -k, --detect-keyboard        Automaitically detect keyboard input device, this option is invalid
	                               when -m|--manually-input-config is set.
	  -m, --manually-input-config  Don't generate input configre files automatically.
	  -n, --instances int          Number of Android instances to be installed.
	  -p, --work-path string       Absolute path of work directory(relative path is not supported).
	  -a, --app-path string        Absolute path of intalled app directory
	  -d, --display-type string    Specify display type, valid option is 'drm', 'x11', 'wld' and 'none'.
	  -t, --display-density string Specify display density.
	  -u, --update                 Use docker souces in update directory to build and install a new
	                               android image based on android.tar.gz.
	  -l, --platform string        Specify the hardware of platform to run AIC, valid option is 'server' and 'nuc'.
	  -b, --adb-port string        Specify adb port for instance 0.
	  -s, --rr-server string       Specify server address for Remote Rendering.
	  -f, --rr-server-file string  Specify config file of server address for Remote Rendering. It's invalid
	                               to specify -s -f at the same time.
	  -w, --multi-dis-daemon       Start multiple display daemons for every instance. It's only valid when
	                               display-type is 'x11' or 'wld' and instances number large than 1.

	Example:
	  Install 3 android instance and do not automatically generate input config file:
	    ./aic install -m -n 3
	  Install one android instance, automatically generate input config file and specify work path to ~/tmp/workdir:
	    ./aic install -p ~/tmp/workdir
	  Install one android instance, automatically generate input config file and support keyboard input detection.
	    ./aic install -k
	EOM
    )

    WORK_DIR="$(pwd)/workdir"
    APP_DIR="$WORK_DIR/app/installed"
    PLATFORM_HARDWARE="nuc"
    ADB_PORT="5555"
    INSTANCE_NUM="1"

    while [ "$#" -gt 0  ]
    do
        case "$1" in
            -c|--cts)
                CTS_ENV="true"
                EMULATED_WIFI="true"
                shift
                ;;
            -e|--emulated-input)
                EMULATED_INPUT="true"
                shift
                ;;
            -i|--emulated-wifi)
                EMULATED_WIFI="true"
                shift
                ;;
            -k|--detect-keyboard)
                DETECT_KEYBOARD="true"
                shift
                ;;
            -m|--manually-input-config)
                MANUALLY_INPUT_CONFIG="true"
                shift
                ;;
            -n|--instances)
                shift
                if [ "$#" -lt 1 ]; then
                    echo "$USAGE"
                    exit -1
                fi
                INSTANCE_NUM=$1
                if ! check_num $INSTANCE_NUM; then
                    echo "$USAGE"
                    exit -1
                fi
                if [ "$INSTANCE_NUM" -lt 1 ]; then
                    echo "$USAGE"
                    exit -1
                fi
                shift
                ;;
            -p|--work-path)
                shift
                if [ "$#" -lt 1 ]; then
                    echo "$USAGE"
                    exit -1
                fi
                WORK_DIR=$1
                shift
                ;;
            -a|--app-path)
                shift
                if [ "$#" -lt 1 ]; then
                    echo "$USAGE"
                    exit -1
                fi
                APP_DIR=$1
                shift
                ;;
            -d|--display-type)
                shift
                if [ "$#" -lt 1 ]; then
                    echo "$USAGE"
                    exit -1
                fi
                DISPLAY_TYPE=$1
                if [ ! "$DISPLAY_TYPE" = "drm" ] && [ ! "$DISPLAY_TYPE" = "x11" ] && [ ! "$DISPLAY_TYPE" = "wld" ] && [ ! "$DISPLAY_TYPE" = "none" ]; then
                    echo "$USAGE"
                    exit -1
                fi
                shift
                ;;
            -u|--update)
                ANDROID_UPDATE="true"
                shift
                ;;
            -l|--platform)
                shift
                PLATFORM_HARDWARE=$1
                if [ ! "$PLATFORM_HARDWARE" = "server" ] && [ ! "$PLATFORM_HARDWARE" = "nuc" ]; then
                    echo "$USAGE"
                    exit -1
                fi
                 shift
                 ;;
            -b|--adb-port)
                shift
                if [ "$#" -lt 1 ]; then
                    echo "$USAGE"
                    exit -1
                fi
                ADB_PORT=$1
                if ! check_num $ADB_PORT; then
                    echo "$USAGE"
                    exit -1
                fi
                shift
                ;;
            -t|--display-density)
                shift
                if [ "$#" -lt 1 ]; then
                    echo "$USAGE"
                    exit -1
                fi
                DISPLAY_DENSITY=$1
                shift
                ;;
            -s|--rr-server)
                shift
                if [ "$#" -lt 1 ]; then
                    echo "$USAGE"
                    exit -1
                fi
                RR_SERVER=$1
                shift
                ;;
            -f|--rr-server-file)
                shift
                if [ "$#" -lt 1 ]; then
                    echo "$USAGE"
                    exit -1
                fi
                RR_SERVER_FILE=$1
                shift
                ;;
            -w|--multi-dis-daemon)
                MULTIPLE_DISPLAY_DAEMON="true"
                shift
                ;;
            *)
                echo "$USAGE"
                exit -1
                ;;
        esac
    done
    check_docker
    check_kernel_header

    if [ ! -z "$RR_SERVER" ] && [ ! -z "$RR_SERVER_FILE" ]; then
        echo "$USAGE"
        exit -1
    fi
    if [ ! -z "$RR_SERVER_FILE" ] && [ ! -e "$RR_SERVER_FILE" ]; then
        echo "[AIC] Missing RR server config file!"
        exit -1
    fi
    if [ "$EMULATED_INPUT" = "true" ]; then
        MANUALLY_INPUT_CONFIG="true"
        if [ ! -d "$WORK_DIR/ipc/config/input" ]; then
            mkdir -p $WORK_DIR/ipc/config/input
        fi
    fi
    if [ "$MULTIPLE_DISPLAY_DAEMON" = "true" ]; then
        if [ "$INSTANCE_NUM" -lt 2 ]; then
            echo "$USAGE"
            exit -1
        fi
        if [ ! "$DISPLAY_TYPE" = "x11" ] && [ ! "$DISPLAY_TYPE" = "wld" ]; then
            echo "$USAGE"
            exit -1
        fi
    fi

    if [ "$ANDROID_UPDATE" = "true" ]; then
        if [ ! -e "./update/Dockerfile" ] || [ ! -d "./update/root" ]; then
            echo "[AIC] Missing docker sources(./update/Dockerfile or ./update/root) to do android image update!"
            exit -1
        fi
    fi

    # Create workdir and app direcotry first, otherwise Docker may create it with root permission
    if [ ! -e "$WORK_DIR" ]; then
        mkdir -p $WORK_DIR
    fi
    if [ ! -e "$APP_DIR" ]; then
        mkdir -p $APP_DIR
    fi

    # uninstall previous resources
    if [ ! -z "$($DOCKER ps -a | grep -E 'android|aic-manager')" ] || [ ! -z "$($DOCKER images | grep -E 'android|aic-manager')" ]; then
        echo "[AIC] Uninstall existing resources first..."
        uninstall
    fi

    # set up server running environment if needed.
    if [ "$PLATFORM_HARDWARE" = "server" ]; then
        echo "[AIC] Setup running env for server platform..."
        # Init dict and array needed by assign cpu set
        declare -A process_dict
        declare -a process_dict_key
        # Init arry
        declare -a cpu_mem_node_arr
        setup_server_env
    fi

    # install docker network driver
    if [ -z "$($DOCKER network ls | grep android)" ]; then
        echo "[AIC] Create android network driver..."
        $DOCKER network create android --subnet=172.100.0.0/16 --gateway=172.100.0.1 -o "com.docker.network.bridge.name"="br-android" -o "com.docker.network.bridge.enable_icc"="true"
    fi

    # load docker images
    echo "[AIC] Load images..."
    $DOCKER pull $TAG_AIC_MANAGER_IMAGE
    $DOCKER pull $TAG_AIC_ANDROID_IMAGE
    if [ "$ANDROID_UPDATE" = "true" ]; then
        $DOCKER tag $TAG_AIC_ANDROID_IMAGE android_base
        $DOCKER rmi $TAG_AIC_ANDROID_IMAGE
        $DOCKER build -t $TAG_AIC_ANDROID_IMAGE update
    fi

    # create aic-manager container
    AIC_MANAGER_CONTAINER_OPTION="-v /lib/modules:/lib/modules -v /usr/src:/usr/src -v $WORK_DIR/ipc:/ipc -v $WORK_DIR/media:/media:shared -v $HOME:$HOME"
    AIC_MANAGER_CONTAINER_CMDS="-n $INSTANCE_NUM"
    if [ "$EMULATED_WIFI" = "true" ]; then
        AIC_MANAGER_CONTAINER_OPTION="$AIC_MANAGER_CONTAINER_OPTION -v /proc:/hostproc -v /var/run/docker.sock:/var/run/docker.sock"
    fi
    if [ "$MANUALLY_INPUT_CONFIG" = "true" ]; then
        AIC_MANAGER_CONTAINER_CMDS="$AIC_MANAGER_CONTAINER_CMDS -m"
    fi
    if [ "$DETECT_KEYBOARD" = "true" ]; then
        AIC_MANAGER_CONTAINER_CMDS="$AIC_MANAGER_CONTAINER_CMDS -k"
    fi
    if [ "$MULTIPLE_DISPLAY_DAEMON" = "true" ]; then
        AIC_MANAGER_CONTAINER_CMDS="$AIC_MANAGER_CONTAINER_CMDS -w"
    fi
    if [ "$EMULATED_WIFI" = "true" ]; then
        AIC_MANAGER_CONTAINER_CMDS="$AIC_MANAGER_CONTAINER_CMDS -i"
    fi
    if [ ! -z "$DISPLAY_TYPE" ]; then
        if [ "$DISPLAY_TYPE" = "x11" ]; then
            AIC_MANAGER_CONTAINER_CMDS="$AIC_MANAGER_CONTAINER_CMDS -d x11"
            AIC_MANAGER_CONTAINER_OPTION="$AIC_MANAGER_CONTAINER_OPTION -v /tmp/.X11-unix:/tmp/.X11-unix"
        elif [ "$DISPLAY_TYPE" = "wld" ]; then
            AIC_MANAGER_CONTAINER_CMDS="$AIC_MANAGER_CONTAINER_CMDS -d wld"
            AIC_MANAGER_CONTAINER_OPTION="$AIC_MANAGER_CONTAINER_OPTION -v /run/user/$(id -u):/tmp"
        elif [ "$DISPLAY_TYPE" = "drm" ]; then
            AIC_MANAGER_CONTAINER_CMDS="$AIC_MANAGER_CONTAINER_CMDS -d drm"
        fi
    else
        if [ "$OS_TYPE" = "ubuntu" ]; then
            AIC_MANAGER_CONTAINER_CMDS="$AIC_MANAGER_CONTAINER_CMDS -d x11"
            AIC_MANAGER_CONTAINER_OPTION="$AIC_MANAGER_CONTAINER_OPTION -v /tmp/.X11-unix:/tmp/.X11-unix"
        elif [ "$OS_TYPE" = "rancher" ]; then
            AIC_MANAGER_CONTAINER_CMDS="$AIC_MANAGER_CONTAINER_CMDS -d drm"
        fi
    fi
    if [ "$PLATFORM_HARDWARE" = "server" ]; then
       AIC_MANAGER_CONTAINER_OPTION="$AIC_MANAGER_CONTAINER_OPTION --pid host -v $WORK_DIR/cpu:/cpu:rw,rshared"
       AIC_MANAGER_CONTAINER_CMDS="$AIC_MANAGER_CONTAINER_CMDS -l $PLATFORM_HARDWARE"
    fi
    if [ "$CTS_ENV" = "true" ]; then
        AIC_MANAGER_CONTAINER_OPTION="$AIC_MANAGER_CONTAINER_OPTION --restart unless-stopped"
    fi

    echo "[AIC] create aic-manager container..."
    $DOCKER container create --name $C_AIC_MANAGER_NAME --init --net host --privileged=true $AIC_MANAGER_CONTAINER_OPTION $TAG_AIC_MANAGER_IMAGE $AIC_MANAGER_CONTAINER_CMDS

    # create Android containers
    ANDROID_CONTAINER_OPTION="-v $APP_DIR:/oem/app:ro -v $WORK_DIR/ipc:/ipc -v /dev/binderfs:/binderfs:rw -v /dev/bus/usb:/dev/bus/usb"
    get_system_image_mount_options && ANDROID_CONTAINER_OPTION="$ANDROID_CONTAINER_OPTION $SYSTEM_IMAGE_MOUNT_OPTIONS"
    if [ ! -z "$DISPLAY_DENSITY" ]; then
        ANDROID_CONTAINER_CMDS="-t $DISPLAY_DENSITY"
    fi
    if [ ! -z "$RR_SERVER" ]; then
        ANDROID_CONTAINER_CMDS="$ANDROID_CONTAINER_CMDS -s $RR_SERVER"
    fi
    if [ "$EMULATED_INPUT" = "true" ]; then
        ANDROID_CONTAINER_CMDS="$ANDROID_CONTAINER_CMDS -e"
    fi
    if [ "$MULTIPLE_DISPLAY_DAEMON" = "true" ]; then
        ANDROID_CONTAINER_CMDS="$ANDROID_CONTAINER_CMDS -w"
    fi

    echo "[AIC] create android container..."
    ANDROID_CONTAINER_OPTION_BK=$ANDROID_CONTAINER_OPTION
    ANDROID_CONTAINER_CMDS_BK=$ANDROID_CONTAINER_CMDS

    for i in $(seq $(($INSTANCE_NUM - 1)) -1 0)
    do
        MAC=02:42:ac:64:$(printf "%02x" $(($i / 256))):$(printf "%02x" $(($i % 256)))
        IP=172.100.$((($i + 2) / 256)).$((($i + 2) % 256))

        ANDROID_CONTAINER_OPTION="$ANDROID_CONTAINER_OPTION_BK -v $WORK_DIR/data$i:/data"
        ANDROID_CONTAINER_CMDS=$ANDROID_CONTAINER_CMDS_BK

        CPU_SET=$(get_cpu_set $i $PLATFORM_HARDWARE)

        if [ "$PLATFORM_HARDWARE" = "server" ]; then
            ANDROID_CONTAINER_OPTION="$ANDROID_CONTAINER_OPTION -v $WORK_DIR/cpu:/sys/devices/system/cpu"
            ANDROID_CONTAINER_CMDS="$ANDROID_CONTAINER_CMDS -c $CPU_SET -m $(get_mem_node_by_cpuid $CPU_SET)"
        else
            ANDROID_CONTAINER_CMDS="$ANDROID_CONTAINER_CMDS -c $CPU_SET"
        fi

        if [ ! -z "$RR_SERVER_FILE" ] && [ ! -z "$(awk ''NR==$((i+1))'' $RR_SERVER_FILE)" ]; then
            ANDROID_CONTAINER_CMDS="$ANDROID_CONTAINER_CMDS -s $(awk ''NR==$((i+1))'' $RR_SERVER_FILE)"
        fi

        if [ "$EMULATED_WIFI" = "true" ] && [ "$CTS_ENV" != "true" ]; then
            ANDROID_CONTAINER_OPTION="$ANDROID_CONTAINER_OPTION -v $WORK_DIR/ipc/config/wifi/$i:/data/misc/wifi"
        fi
        if [ "$CTS_ENV" = "true" ]; then
            ANDROID_CONTAINER_OPTION="$ANDROID_CONTAINER_OPTION --restart unless-stopped --ulimit memlock=16777216"
        else
            ANDROID_CONTAINER_OPTION="$ANDROID_CONTAINER_OPTION --net android --ip $IP --mac-address $MAC -p $(($ADB_PORT+i)):5555 -v $WORK_DIR/ipc/config/ethernet/$i:/data/misc/ethernet"
        fi

        $DOCKER container create --name android$i --cpuset-cpus=$CPU_SET --privileged=true $ANDROID_CONTAINER_OPTION $TAG_AIC_ANDROID_IMAGE $ANDROID_CONTAINER_CMDS $i
    done
}

function uninstall {
    USAGE=$(cat <<- EOM

	Usage: aic uninstall

	Clean up all Android containers which was installed before.
	EOM
    )

	if [ "$#" -lt 0 ]; then
		echo "$USAGE"
		exit 0
	fi

    check_docker

    # rm containers
    CONTAINERS=$($DOCKER ps -a | awk '{print $NF}' | grep -E 'android|aic-manager')
    if [ ! -z "$CONTAINERS" ]; then
        echo "[AIC] Stop containers..."
        $DOCKER stop -t0 $CONTAINERS
        echo "[AIC] rm containers..."
        $DOCKER rm $CONTAINERS
    fi

    # remove docker network
    if [ ! -z "$($DOCKER network ls | awk '{print $2}' | grep -w android)" ]; then
        echo "[AIC] rm android network driver"
        $DOCKER network rm android
    fi

    # umount FUSE mount point if any
    umount_fuse_folder

    # umount binderfs mount point if any
    umount_binderfs
}

function start {
    USAGE=$(cat <<- EOM

	Usage: aic start [OPTIONS] [ID | ID1 ID2...| ID1~ID2]

	Start Android containers. If there's no ID given, it will start all Android containers.

	Options:
	  -t, --time int               Seconds to wait before start next container.

	Example:
	  Start all android instances:
	    ./aic start
	  Start android instance 0, 1, 5 to 7.
	    ./aic start 0 1 5~7
	  Start all android instances, delay 5s after start one.
	EOM
    )

    IDS=()
    CONTAINERS=()
    while [ "$#" -gt 0  ]
    do
        case "$1" in
            -t|--time)
                shift
                if [ "$#" -lt 1 ]; then
                    echo "$USAGE"
                    exit -1
                fi
                WAIT_TIME=$1
                if ! check_num $WAIT_TIME; then
                    echo "$USAGE"
                    exit -1
                fi
                shift
                ;;
            -h|--help)
                echo "$USAGE"
                exit
                ;;
            *)
                IDS+=($1)
                shift
                ;;
        esac
    done

    check_docker
    check_containers
    parse_ids

    # Detected if fake sys folder is needed or not
    # If detected fake sys folder, it indicates the hardware is server and will increase host kernel limit too.
    for cname in ${CONTAINERS[@]}
    do
        if $DOCKER inspect -f '{{ .Mounts }}' $cname | grep -q "\/sys\/devices\/system\/cpu";then
            echo "Fake CPU sysfs is needed....."
            if [ -d "$(pwd)/workdir/cpu" ];then
                echo "Detected previous created fake CPU folders..."
            else
                echo "Re-generated fake CPU folders..."
                create_fake_sys_cpu "$(pwd)/workdir/cpu" 4
            fi
            FUSE_CPU_INFO="yes"

            echo "Increase host kernel limits..."
            increase_limits

            break
        fi
    done
    # Detected ended
	
    if [ -z "$($DOCKER ps | awk '{print $NF}' | grep -w aic-manager)" ]; then
        if [ "$OS_TYPE" = "ubuntu" ]; then
            export DISPLAY=:0
            xhost +local:$($DOCKER inspect --format='{{ .Config.Hostname }}' aic-manager) > /dev/null 2>&1
        fi
        $DOCKER start aic-manager	
        mount_binderfs
    fi

    EXISTED_CONTAINERS=$($DOCKER ps -a | awk '{print $NF}' | grep android)


    while [ -z "$(ls /dev/ashmem 2>/dev/null)" ]
    do
        echo "[AIC] wait for ashmem driver to be installed..."
        sleep 1
    done

    if [ ! -z $FUSE_CPU_INFO ]; then
        while [ -z "$(ls ./workdir/cpu/cpu* 2> /dev/null)" ]
        do
            echo "[AIC] wait for fake CPU information created..."
            sleep 1
        done
    fi

    for c in ${CONTAINERS[@]}
    do
        if [[ ! $EXISTED_CONTAINERS =~ (^|[[:space:]])"$c"($|[[:space:]]) ]]; then
            echo "[AIC] $c not existed!"
        else
            $DOCKER start $c

            if [ ! -z "$WAIT_TIME" ]; then
                sleep $WAIT_TIME
            fi
        fi
    done
}

function stop {
    USAGE=$(cat <<- EOM

	Usage: aic stop [ID | ID1 ID2...| ID1~ID2]

	Stop Android containers. If there's no ID given, it will stop all Android containers.

	Example:
	  Stop all android instances:
	    ./aic stop
	  Stop android instance 0, 1, 5 to 7.
	    ./aic stop 0 1 5~7
	EOM
    )

    IDS=()
    CONTAINERS=()
    while [ "$#" -gt 0  ]
    do
        case "$1" in
            -h|--help)
                echo "$USAGE"
                exit
                ;;
            *)
                IDS+=($1)
                shift
                ;;
        esac
    done

    check_docker
    check_containers
    parse_ids

    EXISTED_CONTAINERS=$($DOCKER ps -a | awk '{print $NF}' | grep android)

    for c in ${CONTAINERS[@]}
    do
        if [[ ! $EXISTED_CONTAINERS =~ (^|[[:space:]])"$c"($|[[:space:]]) ]]; then
            echo "[AIC] $c not existed!"
        else
            $DOCKER stop -t0 $c
        fi
    done

    if [ -z "$($DOCKER ps | awk '{print $NF}' | grep android)" ] && [ ! -z "$($DOCKER ps | awk '{print $NF}' | grep -w aic-manager)" ]; then
        $DOCKER stop aic-manager
        # umount FUSE mount point if any
        umount_fuse_folder
        # umount binderfs mount point if any
        umount_binderfs
    fi
}

function list {
    USAGE=$(cat <<- EOM

	Usage: aic list [OPTIONS]

	List Android containers.

	Option:
	  -a, --all             Show all Android containers (default shows just running)
	EOM
    )

    while [ "$#" -gt 0  ]
    do
        case "$1" in
            -a|--all)
                shift
                LIST_PARA="-a"
                ;;
            *)
                echo "$USAGE"
                exit 0
                ;;
        esac
    done

    $DOCKER ps $LIST_PARA -f name=android
}

OS_TYPE="ubuntu"

if [ ! -z "$(uname -r | grep rancher)"  ]; then
    OS_TYPE="rancher"
fi

if [ -z "$(docker ps 2>/dev/null)" ]; then
    DOCKER="sudo docker"
else
    DOCKER="docker"
fi

USAGE=$(cat <<- EOM

Usage: aic COMMAND

Android container manager tool.

Commands:
  install        Load and install Android container images.
  uninstall      Clean up all Android containers which was installed before.
  start          Start Android containers.
  stop           Stop Android containers.
  list           List Android contianers.

Run 'aic COMMAND --help' for more information on a command.
EOM
)

subcmd="$1"
case $subcmd in
    install)
        shift
        install $@
        ;;

    uninstall)
        shift
        uninstall $@
        ;;

    start)
        shift
        start $@
        ;;

    stop)
        shift
        stop $@
        ;;

    list)
        shift
        list $@
        ;;

    *)
        echo "$USAGE"
        exit
        ;;
esac

exit
