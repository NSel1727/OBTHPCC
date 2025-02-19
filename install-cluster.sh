#!/bin/bash

################################################################################
#    HPCC SYSTEMS software Copyright (C) 2012 HPCC Systems®.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
################################################################################

#
# Usage: install-cluster.sh
#
# This script is used as a remote engine for a cluster installation.
#
# Flow:
#
# 1. SSH Keys Generated.
# 2. Run install-hpcc.sh through cluster-script.py to perform HPCC install and
#        configuration on remote hosts
# 3. Return.
#

INSTALL_DIR=/opt/HPCCSystems
CONFIG_DIR=/etc/HPCCSystems
ENV_XML_FILE=environment.xml
ENV_CONF_FILE=environment.conf

source  ${INSTALL_DIR}/etc/init.d/hpcc_common
source  ${INSTALL_DIR}/etc/init.d/init-functions
source  ${INSTALL_DIR}/etc/init.d/export-path

export REMOTE_INSTALL="/tmp/remote_install"
export NEW="${REMOTE_INSTALL}/new_keys"
export CMDPREFIX="sudo"

printUsage(){
    echo ""
    echo "usage: install-cluster.sh [-h|--help] [-p|--pushkeydir <directory>] [-k|--newkey] [-n|--concurrent <number>] <Platform Package>"
    echo "   -p:  copy previously generated keys from a directory"
    echo "   -k:  generate a new ssh key pair."
    echo "   -n:  how many concurrent execution allowd. The default is 5"
    echo "   <Platform Package>: HPCCSystems package file."
    echo ""
    exit 1
}

getUserAndPasswd(){
    trial=0
    max_trial=3
    while [ 1 ]
    do
       echo ""
       read -p "Please enter admin username: " ADMIN_USER;
       echo ""
       echo "Please enter ssh/scp user password. If this is no password required (assume"
       echo "the user has ssh private key: <user home>/.ssh/id_rsa) just press 'Enter':"
       read -s PASS
       echo ""

       password_string="and a password ($(echo $PASS | sed 's/./\./g'))."
       [ -z "$password_string" ] && password_string="with an empty password for passwordless login."
       echo "You entered user $ADMIN_USER $password_string"
       read -p  "Are these correct? [Y|n] " answer
       if [ "$answer" = "Y" ] || [ "$answer" = "y" ]
       then
          break
       fi

       trial=$(expr $trial \+ 1)
       if [ $trial -eq $max_trial ]
       then
          echo ""
          echo "Exceeded maximum attempts. Giving up."
          echo ""
          exit 1
       fi
    done

  if [ "$file_transfer_user" == "root" ]
  then
     CMDPREFIX=""
  fi

  export ADMIN_USER
  export PASS
}


generateKey(){
    GENKEY=${PWD}/new_ssh
    if [ -d ${GENKEY} ]; then
        rm -rf ${GENKEY}
    fi
    mkdir -p ${GENKEY}
    ssh-keygen -t rsa -f ${GENKEY}/id_rsa -P ""
}

createPayload(){
    if [ -d ${REMOTE_INSTALL} ]; then
        rm -rf ${REMOTE_INSTALL};
    fi
    mkdir -p ${REMOTE_INSTALL};
    if [ ${NEW_KEY} -eq 1 ]; then
        mkdir -p ${NEW}
        cp -r ${GENKEY}/* ${NEW}/
    elif [[ ${COPY_KEY} -eq 1 && -n $KEY_DIR ]]; then
        mkdir -p ${NEW}
        cp -r ${KEY_DIR}/* ${NEW}/
    fi
    
    cp -r ${PKG} ${REMOTE_INSTALL}
    cp -r ${CONFIG_DIR}/${ENV_XML_FILE} ${REMOTE_INSTALL}
    cp -r ${CONFIG_DIR}/${ENV_CONF_FILE} ${REMOTE_INSTALL}
    cp -r ${INSTALL_DIR}/sbin/remote-install-engine.sh ${REMOTE_INSTALL}

    echo "tar -zcvf /tmp/remote_install.tgz ${REMOTE_INSTALL}/*"
    tar -zcvf /tmp/remote_install.tgz ${REMOTE_INSTALL}/*
    ls -l /tmp/remote_install.tgz
    rm -rf ${REMOTE_INSTALL}
}

removePayload(){
    rm /tmp/remote_install.tgz
}


######################################################################
#
# MAIN
#
######################################################################

cluster_tools_init

if [ "$(whoami)" != "root" ]; then
   echo ""
   echo "The script must run as root or sudo."
   echo ""
   exit 1
fi

NEW_KEY=0
COPY_KEY=0
OPTIONS="-l DEBUG -e ${CONFIG_DIR}/${ENV_CONF_FILE} -s ${SECTION:-DEFAULT}"

TEMP=`/usr/bin/getopt -o p:n:s:kh --long help,pushkeydir,newkey,concurrent: -n 'install-cluster' -- "$@"`
if [ $? != 0 ] ; then echo "Failure to parse commandline." >&2 ; exit 1 ; fi
eval set -- "$TEMP"
while true ; do
    case "$1" in
        -k|--newkey)
            NEW_KEY=1
            if [[ $COPY_KEY -eq 1 ]]; then
                echo "Cannot use both [-p|--pushkeydir] and [-k|--newkey] options"
                exit 1
            fi
            shift ;;
        -p|--pushkeydir)
            COPY_KEY=1
            KEY_DIR=$2
            if [[ $NEW_KEY -eq 1 ]]; then
                echo "Cannot use both [-p|--pushkeydir] and [-k|--newkey] options"
                exit 1
            fi
            shift 2 ;;
        -n|--concurrent)
            if [ -n "$2" ] && [[ $2 =~ ^[0-9]+$ ]]
            then
               [ $2 -gt 0 ] && OPTOINS="${OPTIONS:+"$OPTIONS "}-n $2"
            fi
            shift 2 ;;
        -h|--help) printUsage
                   shift ;;
        --) shift ; break ;;
        *) printUsage ;;
    esac
done

for arg do arg=$arg; done
PKG=${arg}
[ -z "$PKG" ] && printUsage

export PKG

getUserAndPasswd

pkgtype=`echo "${PKG}" | grep -i rpm`
if [ -z $pkgtype ]; then
    pkgcmd="dpkg"
else
    pkgcmd="rpm"
fi

if [ ${NEW_KEY} -eq 1 ]; then
    generateKey
fi

export NEW_KEY
export KEY_DIR

createPayload;

expected_python_version=2.6
is_python_installed ${expected_python_version}

if [ $? -eq 0 ]
then
   chksum=$(md5sum ${INSTALL_DIR}/sbin/install-hpcc.exp | cut -d' ' -f1)
   eval ${INSTALL_DIR}/sbin/cluster_script.py -f ${INSTALL_DIR}/sbin/install-hpcc.exp -c $chksum $OPTIONS -l DEBUG
else
   echo ""
   echo "Cannot detect python version ${expected_python_version}+. Will run on the cluster hosts sequentially."
   echo ""
   run_cluster ${INSTALL_DIR}/sbin/install-hpcc.exp 0
fi
removePayload;
