#!/usr/bin/env bash

PACMAN_SRC_PUBLIC_IP=35.185.237.82

function valid_ip {
     local ip=$1
     local rc=1

     if [[ ${ip} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
         OIFS=${IFS}
         IFS='.'
         ip=(${ip})
         IFS=${OIFS}
         [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255
             && ${ip[3]} -le 255 ]]
         rc=$?
     fi

     return ${rc}
 }


 if valid_ip ${PACMAN_SRC_PUBLIC_IP} ; then   
    gcloud dns record-sets transaction describe -z=${ZONE_NAME}
  else echo "anothing thing"
 fi

