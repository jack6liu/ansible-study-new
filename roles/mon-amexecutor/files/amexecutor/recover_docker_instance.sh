#!/bin/bash

#
# recover_docker_instance.sh
#   usage: bash recover_docker_instance.sh "${target_container_id}"
#   note: must be running by root
#

#
# get args from stdin
#
target_container_id=$1

#
# set global variables
#
export _file_name=$(readlink -f $0)
export _script_name=$(basename ${_file_name})
export _dir_name=$(dirname ${_file_name})

#
# precheck script status by checking pid
#   VERY IMPORTANT: there are some cases that some script is running and caused the container down for temporarily
#                   eg: fabric-backup.sh, monitoring-backup.sh, dnsmasq-backup.sh AND recover_docker_instance.sh
#               SO: these script share the same pidfile in order to avoid run these scripts at the sametime
#                   It is hardcoded to be /var/run/hfc-jcloud-com-backup-restore.pid
#
export pidfile="/var/run/hfc-jcloud-com-backup-restore.pid"
export retry_interval=5

echo "INFO:  prechecking before running this script ..."

# totally try to check for (1 + 3) * ${retry_interval} seconds
exist_pid=`cat ${pidfile} 2>/dev/null`

if [[ -e "${pidfile}" ]] && [[ "${exist_pid}" != "$$" ]] ; then
    echo "WARN:  \"${exist_pid_cmd}\" is running ..."
    echo "WARN:   we will retry after ${retry_interval}s ..."
    sleep ${retry_interval}
    # try sleep 3 more times before exit
    for cnt in {1..3}; do
        exist_pid=`cat ${pidfile} 2>/dev/null`
        echo "WARN:  this is the ${cnt} retry ..."
        if [[ -e "${pidfile}" ]] && [[ "${exist_pid}" != "$$" ]] ; then
            echo "WARN:  \"${exist_pid_cmd}\" is running ..."
            echo "WARN:   we will retry after ${retry_interval}s ..."
        fi
        sleep ${retry_interval}
    done
    # exit after 1 + 3 checks
    exist_pid_cmd=`ps -o cmd --no-headers ${exist_pid}`
    echo "WARN:  \"${exist_pid_cmd}\" is running ..."
    echo "WARN:  so we exit with nothing did ..."
    exit 1
fi

echo "INFO:  >>>> ${_script_name} started at `date +"%F %T(%:z)"` <<<<"

#
# write current pid to ${pidfile}
#
trap "rm -f -- \"${pidfile}\"" EXIT INT KILL TERM
echo "$$" > "${pidfile}"

#
# functions predefined
#
get_timestamp() {
    printf "%.19s" "$(date +%Y%m%d.%H%M%S.%N)"
}

format_output() {
    "$@" 2>&1 | while read -r line; do echo -e "\\t\t $line"; done
}

get_dockerd_version() {
    printf "`docker version --format {{.Server.Version}} 2>/dev/null`"
}

get_name_by_container_id(){
    local container_id=$1
    printf "`docker ps -a --no-trunc -f id="${container_id}" --format {{.Names}}`"
}

get_image_by_container_id(){
    local container_id=$1
    printf "`docker ps -a --no-trunc -f id="${container_id}" --format {{.Image}} | awk -F '/|-|:' '{print $2}'`"
}

get_stopped_container_ids(){
    printf "`docker ps -qa --no-trunc -f "status=exited" -f "status=dead" -f "status=paused"`"
}

is_running_by_container_id() {
    local container_id=$1
    printf "`docker ps -qa --no-trunc -f "status=running" -f id="${container_id}"`"
}

is_running_by_container_name() {
    local container_name=$1
    printf "`docker ps -qa --no-trunc  -f "status=running" -f name="${container_name}$"`"
}

get_id_by_container_name() {
    local container_name=$1
    printf "`docker ps -qa --no-trunc -f name="${container_name}$" | tr -d '\n'`"
}


get_backup_file_by_image() {
    #
    # usage: get_backup_file_by_image "${container_name}" "${container_image}"
    # check backup files from
    #              /var/lib/docker/dnsmasq-backup     for dnsmasq
    #              /var/lib/docker/hfc-backup         for fabric nodes
    #              /var/lib/docker/monitoring-backup  for monitoring nodes
    #
    local container_name=$1
    local container_image=$2
    local backup_dir

    case ${container_image,,} in
        dnsmasq)
            backup_dir=/var/lib/docker/dnsmasq-backup
            ;;
        fabric)
            backup_dir=/var/lib/docker/hfc-backup
            ;;
        *)
            backup_dir=/var/lib/docker/monitoring-backup
            ;;
    esac

    printf "`ls ${backup_dir}/${container_name}* 2>/dev/null | sort | tail -1`"
}

set_restore_file_from_backup_tgz() {
    #
    # usage: set_restore_file_from_backup_tgz "${backup_tgz}"
    # backup_tgz should be tar.gz file with full path archived
    #                   eg: /hfc-data/ca.org1.hfc.test.io
    #                   backup tgz file name: ca.org1.hfc.test.io_20170511-105501-998.tgz
    #
    local backup_tgz=$1

    local container_name=`basename ${backup_tgz} | cut -d '_' -f 1`
    local timestamp=`get_timestamp`

    # backup existing /hfc-data/${container_name}
    local target_dir=/hfc-data/${container_name}
    if [[ -e "${target_dir}" ]]; then
        mv -f ${target_dir} ${target_dir}.${timestamp}
    fi

    # replace with backup file
    temp_dir=$(mktemp -d)
    tar -zxf ${backup_tgz} -C ${temp_dir}

    # make sure /hfc-data exists, for some cases that the volume may not mounted to the host
    mkdir -p /hfc-data/
    mv -f ${temp_dir}/hfc-data/${container_name} /hfc-data/
}

#
# main process
#

# 0. precheck the ${target_container_id}
if [[ ! ${target_container_id} ]]; then
    echo "ERROR: no container_id provided !!!"
    echo "ERROR: exited with nothing done !!!"
    exit 1
fi

# 1. check dockerd status, try to start if dockerd is not running
#    check dockerd running status by checking dockerd version
dockerd_version=`get_dockerd_version`

if [[ ! ${dockerd_version} ]]; then
    #    1.1 if dockerd is not running, try to start
    echo "ERROR: docker daemon is stopped !!!"
    echo "WARN:  trying to restart docker daemon ..."

    #    1.2 try to start dockerd
    format_output systemctl start docker.service

    #    1.3 verify dockerd running status again
    daemon_state=`get_dockerd_version`

    if [[ ! ${daemon_state} ]]; then
        echo "ERROR: docker daemon cannot started !!!"
        echo "ERROR: Exit recovery operation now ..."
        echo "INFO:  >>>> ${_script_name} finished at `date +"%F %T(%:z)"` <<<<"
        exit 1
    else
        # 2. till now, dockerd should be running, try to start all instances status=exited/dead/paused
        echo "INFO:  docker daemon is running ..."

        echo "WARN:  trying to start all docker instances (exited, dead, paused) ..."
        stopped_container_ids=`get_stopped_container_ids`
        for container_id in ${stopped_container_ids} ; do
            #    2.1 try to start ${container_id}
            format_output docker start ${container_id}

            #    2.2 verify ${container_id} state
            sleep 0.5
            state=`is_running_by_container_id "${container_id}"`
            if [[ ! ${state} ]]; then
                name=`get_name_by_container_id "${container_id}"`
                echo "ERROR: instance id=${container_id} name=${name} cannot be started !!!"
            fi
        done
    fi
fi

# 3. try to start the target_instance, actually it should be started at step2.
#    3.1 set instance info
target_container_name=`get_name_by_container_id "${target_container_id}"`
target_container_image=`get_image_by_container_id "${target_container_id}"`
target_restore_dir="/hfc-data/${target_container_name}/restore"
target_restore_script="run-${target_container_name}.sh"

#    3.2 check the ${target_container_id} exists or not
if [[ ! ${target_container_name} ]]; then
    echo "ERROR: the target instance id=${target_container_id} was not found !!!"
    echo "ERROR: IS id=${target_container_id} running on this host???"
    echo "ERROR: Exit recovery operation now ..."
    echo "INFO:  >>>> ${_script_name} finished at `date +"%F %T(%:z)"` <<<<"
    exit 1
fi

#    3.3 check ${target_container_id} running state
state=`is_running_by_container_id "${target_container_id}"`
if [[ ! ${state} ]]; then
    #    3.3.1 start ${target_container_id} if not running
    format_output docker start ${target_container_id}

    #    3.3.2 verify ${target_container_id} state
    sleep 0.5
    state=`is_running_by_container_id "${target_container_id}"`
    if [[ ! ${state} ]]; then
        echo "ERROR: target instance id=${target_container_id} name=${target_container_name} cannot be started !!!"

        #    3.3.2.1 try to restore from backup if start failed
        echo "WARN:  Try to restore from backup ..."

        #    3.3.2.1.1 check ${target_restore_script} exists or not
        if [[ ! -f "${target_restore_dir}/${target_restore_script}" ]]; then
            echo "WARN:  ${target_restore_dir}/${target_restore_script} is not found !!!"
            echo "WARN:  try to recover from backup tgz file ..."

            #    3.3.2.1.2 try to recover from ${latest_backup_tgz} if not found
            latest_backup_tgz=`get_backup_file_by_image "${target_container_name}" "${target_container_image}"`

            if [[ ! ${latest_backup_tgz} ]]; then
                echo "ERROR: NO backup tgz file found !!!"
                echo "ERROR: target instance id=${target_container_id} name=${target_container_name} cannot be restored !!!"
                echo "ERROR: IS IT the right host??? CHECK it manually !!!"
                echo "ERROR: Exit recovery operation now ..."
                exit 1
            else
                #    3.3.2.1.3 extract /hfc-data/${target_container_name} files
                echo "INFO:  recover restore files from ${latest_backup_tgz} ..."
                set_restore_file_from_backup_tgz "${latest_backup_tgz}"
            fi
        fi
        #    3.3.2.2 try to restore ${target_container_id} by run ${target_restore_script}
        echo "INFO:  try to restore target instance id=${target_container_id} name=${target_container_name} now ..."
        cd ${target_restore_dir}
        bash ${target_restore_script} --force
        cd ${_dir_name}

        #    3.3.3.3 verify ${target_container_id} state after restored
        #            NOTE, have to verify by ${target_container_name} here, cause the id was changed after restore!!!
        sleep 0.5
        state=`is_running_by_container_name "${target_container_name}"`
        if [[ ! ${state} ]]; then
            echo "ERROR: target instance id=${target_container_id} name=${target_container_name} was restored but cannot started !!!"
            echo "ERROR: CHECK it manually !!!"
            echo "ERROR: Exit recovery operation now ..."
            echo "INFO:  >>>> ${_script_name} finished at `date +"%F %T(%:z)"` <<<<"
            exit 1
        fi
        new_container_id=`get_id_by_container_name "${target_container_name}"`
        echo "INFO:  target instance id=${target_container_id} name=${target_container_name} restored successfully ..."
        echo "INFO:  the restore instance is id=${new_container_id} name=${target_container_name} ..."
    fi
else
    echo "WARN:  instance id=${target_container_id} is already running !!!"
    echo "WARN:  There must be something wrong with the monitoring system or network !!!"
    echo "INFO:  >>>> ${_script_name} finished at `date +"%F %T(%:z)"` <<<<"
fi
