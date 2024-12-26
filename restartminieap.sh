#!/bin/sh
if [ -s /usr/sbin/mwan3 ]; then
    while true; do
        ping_count=0
        ping_addr_1=114.114.114.114
        ping_addr_2=223.5.5.5
        while [ "${ping_count}" -lt 5 ]; do
            if /bin/ping -c 1 "${ping_addr_1}" >/dev/null 2>&1; then
                ping_err=0
                break
            else
                if /bin/ping -c 1 "${ping_addr_2}" >/dev/null 2>&1; then
                    ping_err=0
                    break
                else
                    ping_count=$((ping_count + 1))
                    ping_err=1
                fi
            fi
        done
        ping_count=0
        if [ "${ping_err}" -eq 0 ]; then
            for i in $(mwan3 interfaces | grep "is offline" | awk '{print $2}'); do
                interface=$(uci get network."${i}".device)
                netconfig=$(uci show network | grep "${interface}" | grep -v -e "@")
                if [ -n "${netconfig}" ]; then
                    for j in $(echo "${netconfig}" | awk -F'.' '{print $2}'); do
                        /sbin/ifdown "${j}"
                        /sbin/ifup "${j}"
                    done
                fi
            done
        fi
        sleep 60
    done
fi
