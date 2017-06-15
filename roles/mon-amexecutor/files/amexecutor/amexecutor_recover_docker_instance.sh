#!/bin/bash

#
# amexecutor_recover_docker_instance.sh
#   usage: trigger by prometheus-am-executor
#          get ENV variables from prometheus-am-executor, more details about prometheus-am-executor,
#          refer to https://github.com/imgix/prometheus-am-executor
#

#
# set global variables
#
export _file_name=$(readlink -f $0)
export _script_name=$(basename ${_file_name})
export _dir_name=$(dirname ${_file_name})

export recover_script=${_dir_name}/recover_docker_instance.sh
export ssh_keypair=${_dir_name}/id_rsa

#
# precheck script status by checking pid
#   VERY IMPORTANT: there are some cases that some script is running and caused the container down for temporarily
#                   eg: fabric-backup.sh, monitoring-backup.sh, dnsmasq-backup.sh AND recover_docker_instance.sh
#               SO: these script share the same pidfile in order to avoid run these scripts at the sametime
#                   It is hardcoded to be /var/run/hfc-jcloud-com-backup-restore.pid
#
export pidfile="/var/run/hfc-jcloud-com-backup-restore.pid"
export retry_interval=5

echo -e "
                   INFO:  prechecking before running this script ...
                   "

# totally try to check for (1 + 3) * ${retry_interval} seconds
exist_pid=`cat ${pidfile} 2>/dev/null`

if [[ -e "${pidfile}" ]] && [[ "${exist_pid}" != "$$" ]] ; then
    echo -e "
                   WARN:  \"${exist_pid_cmd}\" is running ...
                   WARN:   we will retry after ${retry_interval}s ...
                   "
    sleep ${retry_interval}
    # try sleep 3 more times before exit
    for cnt in {1..3}; do
        exist_pid=`cat ${pidfile} 2>/dev/null`
        echo -e "
                   WARN:  this is the ${cnt} retry ...
                   "
        if [[ -e "${pidfile}" ]] && [[ "${exist_pid}" != "$$" ]] ; then
            echo -e "
                   WARN:  \"${exist_pid_cmd}\" is running ...
                   WARN:   we will retry after ${retry_interval}s ...
                   "
        fi
        sleep ${retry_interval}
    done
    # exit after 1 + 3 checks
    exist_pid_cmd=`ps -o cmd --no-headers ${exist_pid}`
    echo -e "
                   WARN:  \"${exist_pid_cmd}\" is running ...
                   WARN:  so we exit with nothing did ...
                   "
    exit 1
fi

echo -e "
                   INFO:  >>>> ${_script_name} started at `date +"%F %T %:z"` <<<<
"

#
# write current pid to ${pidfile}
#
trap "rm -f -- \"${pidfile}\"" EXIT INT KILL TERM
echo "$$" > "${pidfile}"

#
# functions predefined
#
set_ssh_opts() {
    #
    # func:  generate ssh options for ssh/scp connection
    # usage: set_ssh_opts SSH_OPTS "${KEYPAIR_FILE}"
    #        SSH_OPTS will be the return value from set_ssh_opts
    #
    local SSH_BASE_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=3"

    local KEYPAIR_FILE=${KEYPAIR_FILE:="./id_rsa"}

    if [[ $2 ]]; then
        KEYPAIR_FILE=$2
    fi

    if [[ ! -e "${KEYPAIR_FILE}" ]]; then
        echo -e "
                   ERROR: ${KEYPAIR_FILE} is not found!!!
                   ERROR: exit ${_script_name} now ...
                   "
        exit 1
    fi
    # the private key must be 0600
    chmod 0600 ${KEYPAIR_FILE}

    local SSH_OPTS=${SSH_BASE_OPTS}" -i ${KEYPAIR_FILE}"

    eval "$1=\"${SSH_OPTS}\""
}

check_host_connectivity() {
    #
    # func:  check host connectivity via ssh
    # usage: check_host_connectivity CONNECTIVITY "${SSH_OPTS}" "${TGT_HOST}"
    #        CONNECTIVITY will be the return value from check_host_connectivity
    #        "" around is required
    #
    local SSH_OPTS=$2
    local TGT_HOST=$3

    RET=`ssh ${SSH_OPTS} ${TGT_HOST} "echo connected" 2> /dev/null`

    if [[ $RET == "connected" ]]; then
        CONNECTIVITY="success"
    else
        CONNECTIVITY="failed"
    fi

    eval "$1=\"${CONNECTIVITY}\""
}

copy_and_run_on_host() {
    #
    # func:  copy and run shell script on target host
    # usage: copy_and_run_on_host "${SSH_OPTS}" "${SCRIPT}" "${TGT_HOST}" "${TGT_CONTAINER_ID}"
    #
    local SSH_OPTS=$1
    local SCRIPT=$2
    local TGT_HOST=$3
    local TGT_CONTAINER_ID=$4

    tmp_script=`ssh ${SSH_OPTS} ${TGT_HOST} "mktemp" 2>/dev/null`
    scp ${SSH_OPTS} ${SCRIPT} ${TGT_HOST}:${tmp_script}
    ssh ${SSH_OPTS} ${TGT_HOST} "chmod +x ${tmp_script} && nohup bash ${tmp_script} ${TGT_CONTAINER_ID} >${tmp_script}.log 2>&1 &"
}

#
# main process
#

echo -e "\n
                   +------------------------------------------------------+
                   +  ${_script_name}               +
                   +------------------------------------------------------+
                   "

# 1. loop for all alerts

counter=1
while [ ${counter} -le ${AMX_ALERT_LEN} ]; do
    echo "
                   +--> started to fix the #${counter} alert ...
                   "

    # 1.1 set alert information needed
    alert_action=''
    alert_host_uri=''
    alert_host=''
    alert_container_name=''
    alert_container_id=''
    alert_status=''

    SKIP=0

    eval "alert_action=\${AMX_ALERT_${counter}_LABEL_action}"
    eval "alert_host_uri=\${AMX_ALERT_${counter}_LABEL_instance}"
    alert_host=$(echo ${alert_host_uri} | cut -d ':' -f1)
    eval "alert_container_name=\${AMX_ALERT_${counter}_LABEL_name}"
    eval "alert_container_id=\${AMX_ALERT_${counter}_LABEL_id}"
    eval "alert_status=\${AMX_ALERT_${counter}_STATUS}"

    # 1.2 check ${alert_status}
    #           possible value is resolved, firing?
    if [[ "${alert_status}" == "resolved" ]]; then
        echo -e "
                   INFO:  the alert ${counter} is ${alert_status} !!!
                          container id     -- ${alert_container_id}
                          container name   -- ${alert_container_name}
                          container host   -- ${alert_host}
                          container action -- ${alert_action}
                          container status -- ${alert_status}
                   INFO:  skipping...
                   "

        # skip actions
        SKIP=1
    fi


    # 1.3 check ${alert_action}
    #           defined value is recover
    if [[ "${alert_action}" != "recover" ]]; then
        echo -e "
                   INFO:  the alert ${counter} is intend for ${alert_action} !!!
                          container id     -- ${alert_container_id}
                          container name   -- ${alert_container_name}
                          container host   -- ${alert_host}
                          container action -- ${alert_action}
                          container status -- ${alert_status}
                   INFO:  skipping ...
                   "

        # skip actions
        SKIP=1
    fi

    if [[ ${SKIP} -eq 0 ]]; then
        # 1.3 set_ssh_opts
        echo "
                   +--> setting ssh connection for ${alert_container_name} @ #${counter} alert ...
                   "
        set_ssh_opts alert_ssh_opts "${ssh_keypair}"

        # 1.4 check_host_connectivity to ${alert_host}
        echo "
                   +--> checking host connectivity for ${alert_container_name} @ #${counter} alert ...
                   "
        check_host_connectivity alert_host_connectivity ${alert_ssh_opts} ${alert_host}

        # 1.5 copy_and_run_on_host
        echo "
                   +--> starting recover process for ${alert_container_name} @ #${counter} alert ...
                   "
        copy_and_run_on_host "${alert_ssh_opts}" "${recover_script}" "${alert_host}" "${alert_container_id}"
    fi
    # let counter increase
    let counter+=1
done
echo -e "
                   INFO:  >>>> ${_script_name} finished at `date +"%F %T %:z"` <<<<
"
