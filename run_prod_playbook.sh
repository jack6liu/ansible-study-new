#!/bin/bash

OPTS=${OPTS:='-f'}
if [[ $1 ]]; then
    OPTS=$1
fi

case ${OPTS} in
    -C)
        printf "\n\n\n<<<checking prod_prepare.yml>>>\n\n\n"
        ansible-playbook $OPTS -i inventories/prod/hosts prod_fabric.yml
        ;;
    -a|-all)
        printf "\n\n\n<<<running prod_prepare.yml>>>\n\n\n"
        ansible-playbook -i inventories/prod/hosts prod_prepare.yml
        printf "\n\n\n<<<running prod_dnsmasq.yml>>>\n\n\n"
        ansible-playbook -i inventories/prod/hosts prod_dnsmasq.yml
        printf "\n\n\n<<<running prod_monitor.yml>>>\n\n\n"
        ansible-playbook -i inventories/prod/hosts prod_monitor.yml
        printf "\n\n\n<<<running prod_fabric.yml>>>\n\n\n"
        ansible-playbook -i inventories/prod/hosts prod_fabric.yml
        ;;
    -f|-fabric)
        printf "\n\n\n<<<running prod_fabric.yml>>>\n\n\n"
        ansible-playbook -i inventories/prod/hosts prod_fabric.yml
        ;;
    -m|-monitor)
        printf "\n\n\n<<<running prod_monitor.yml>>>\n\n\n"
        ansible-playbook -i inventories/prod/hosts prod_monitor.yml
        ;;
    -n|-dnsmasq)
        printf "\n\n\n<<<running prod_dnsmasq.yml>>>\n\n\n"
        ansible-playbook -i inventories/prod/hosts prod_dnsmasq.yml
        ;;
    *)
        echo "Only 1 options accept: -vvv, -C, -p|-P, -d|-D"
        echo "    -C,           Dry run, check only"
        echo "    -a|-all,      Fully deploy by running prod_prepare.yml, prod_dnsmasq.yml, prod_monitor.yml, prod_fabric.yml all together"
        echo "    -f|-fabric,   [DEFAULT]ONLY run <prod_fabric.yml>, deploy fabric nodes only, DEFAULT"
        echo "             this is the DEFAULT choice"
        echo "    -m|-monitor,  ONLY run <prod_monitor.yml>, deploy monitoring nodes only"
        echo "    -n|-dnsmasq,  ONLY run <prod_monitor.yml>, deploy dnsmasq nodes only"
        ;;
esac
