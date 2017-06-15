#!/bin/bash

CONTAINER_NAME=$1
#CONTAINER_NAME=$(docker ps --format "{{.ID}}\t{{.Names}}" | awk '/peer[0-9]?$/ {print $2}')
DATA_SRC_DIR=/hfc-data/${CONTAINER_NAME}/
BACKUP_DEST_DIR=/var/lib/docker/dnsmasq-backup
TIME_STAMP=$(printf "%.19s" "$(date +%Y%m%d-%H%M%S-%N)")
BACKUP_FILENAME=${BACKUP_DEST_DIR}/${CONTAINER_NAME}_${TIME_STAMP}.tgz

export CONTAINER_NAME
export DATA_SRC_DIR
export BACKUP_DEST_DIR
export BACKUP_FILENAME

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

#
# write current pid to ${pidfile}
#
trap "rm -f -- \"${pidfile}\"" EXIT INT KILL TERM
echo "$$" > "${pidfile}"


local_time() {
    printf "%.23s" "$(date '+%Y-%m-%d %H:%M:%S.%N')"
}

backup() {
    echo "==== Stopping ${CONTAINER_NAME} ..."
    docker stop ${CONTAINER_NAME}

    echo "==== Wait 1 second before backup ..."
    sleep 1

    echo "==== Backup ${DATA_SRC_DIR} to ${BACKUP_FILENAME}"
    mkdir -p ${BACKUP_DEST_DIR}
    tar -czf ${BACKUP_FILENAME} ${DATA_SRC_DIR}

    echo "==== Wait 1 second after backup ..."
    sleep 1

    echo "==== Starting ${CONTAINER_NAME} ..."
    docker start ${CONTAINER_NAME}
}

prune_old_backup() {
    DATE_LIMIT=$(date +%Y%m%d --date="-7 day")
    for BAK_FILE in $(ls ${BACKUP_DEST_DIR}); do
        BAK_DATE=$(echo ${BAK_FILE} | sed "s/${CONTAINER_NAME}_//g" | cut -d '-' -f 1)
        if [[ "${BAK_DATE}" -lt "${DATE_LIMIT}" ]]; then
            echo "---- Deleting ${BAK_FILE} ..."
            rm -f ${BAK_FILE}
        else
            echo "---- Skipping ${BAK_FILE} ..."
        fi
    done
}

LOG_FILE=/var/log/${CONTAINER_NAME}-backup.log

echo "==== BACKUP for ${CONTAINER_NAME} started @ $(local_time)"  > ${LOG_FILE}
backup 2>&1                                                       >> ${LOG_FILE}
prune_old_backup 2>&1                                             >> ${LOG_FILE}
echo "==== BACKUP for ${CONTAINER_NAME} finished @ $(local_time)" >> ${LOG_FILE}

