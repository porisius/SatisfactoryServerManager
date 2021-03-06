#!/bin/bash

echo "#-----------------------------#"
echo "#      _____ _____ __  __     #"
echo "#     / ____/ ____|  \/  |    #"
echo "#    | (___| (___ | \  / |    #"
echo "#     \___ \\\\___ \| |\/| |    #"
echo "#     ____) |___) | |  | |    #"
echo "#    |_____/_____/|_|  |_|    #"
echo "#-----------------------------#"
echo "# Satisfactory Server Manager #"
echo "#-----------------------------#"

TEMP_DIR=$(mktemp -d /tmp/XXXXX)
INSTALL_DIR="/opt/SSM"

FORCE=0
UPDATE=0
NOSERVICE=0

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    --force | -f)
        FORCE=1
        shift # past value
        ;;

    --update | -u)
        UPDATE=1
        shift # past value
        ;;
    --noservice)
        NOSERVICE=1
        shift
        ;;
    --installdir)
        INSTALL_DIR=$2
        shift
        shift
        ;;
    esac
done

PLATFORM="$(uname -s)"

if [ ! "${PLATFORM}" == "Linux" ]; then
    echo "Error: Install Script Only Works On Linux Platforms!"
    exit 1
fi

if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
else
    echo "Error: This version of Linux is not supported for SSM"
    exit 2
fi

if [[ "${OS}" == "Debian" ]] || [[ "${OS}" == "Ubuntu" ]]; then
    apt-get -qq update -y
    apt-get -qq upgrade -y
    apt-get -qq install curl wget jq -y
else
    echo "Error: This version of Linux is not supported for SSM"
    exit 2
fi

if [[ "${OS}" == "Ubuntu" ]] && [[ "${VER}" != "19.10" ]]; then
    check_lib=$(strings /usr/lib/x86_64-linux-gnu/libstdc++.so.6 | grep GLIBCXX_3.4.26 | wc -l)

    if [ $check_lib -eq 0 ]; then
        add-apt-repository ppa:ubuntu-toolchain-r/test -y >/dev/null 2>&1
        apt-get -qq update -y
        apt-get -qq upgrade -y
    fi

    check_lib=$(strings /usr/lib/x86_64-linux-gnu/libstdc++.so.6 | grep GLIBCXX_3.4.26 | wc -l)

    if [ $check_lib -eq 0 ]; then
        echo "Error: Couldn't install required libraries"
        exit 1
    fi
fi

curl --silent "https://api.github.com/repos/mrhid6/satisfactoryservermanager/releases/latest" >${TEMP_DIR}/SSM_releases.json

SSM_VER=$(cat ${TEMP_DIR}/SSM_releases.json | jq -r ".tag_name")
SSM_URL=$(cat ${TEMP_DIR}/SSM_releases.json | jq -r ".assets[].browser_download_url" | grep -i "Linux" | sort | head -1)

if [ -d "${INSTALL_DIR}" ]; then
    if [[ ${UPDATE} -eq 0 ]] && [[ ${FORCE} -eq 0 ]]; then
        echo "Error: SSM is already installed!"
        exit 1
    else
        SSM_CUR=$(cat ${INSTALL_DIR}/version.txt)
        echo "Updating SSM ${SSM_CUR} to ${SSM_VER} ..."
    fi
else
    echo "Installing SSM ${SSM_VER} ..."
    mkdir -p ${INSTALL_DIR}
fi

SSM_SERVICENAME="SSM.service"
SSM_SERVICEFILE="/etc/systemd/system/SSM.service"
SSM_SERVICE=$(
    systemctl list-units --full -all | grep -Fq "${SSM_SERVICENAME}"
    echo $?
)

if [ ${SSM_SERVICE} -eq 0 ]; then
    echo "Stopping SSM Service"
    systemctl stop ${SSM_SERVICENAME}
fi

echo "* Downloading SSM"
rm -r ${INSTALL_DIR}/* 2>&1 >/dev/null
mkdir -p "${INSTALL_DIR}/SMLauncher"

wget -q "${SSM_URL}" -O "${INSTALL_DIR}/SSM.tar.gz"
tar xzf "${INSTALL_DIR}/SSM.tar.gz" -C "${INSTALL_DIR}"
rm "${INSTALL_DIR}/SSM.tar.gz" >/dev/null 2>&1
rm "${INSTALL_DIR}/build.log" >/dev/null 2>&1
echo ${SSM_VER} >"${INSTALL_DIR}/version.txt"

chmod -R +x ${INSTALL_DIR}

echo "* Cleanup"
rm -r ${TEMP_DIR}

if [ ${NOSERVICE} -eq 0 ]; then
    echo "Creating SSM Service"
    ENV_SYSTEMD=$(pidof systemd >/dev/null && echo "systemd" || echo "other")

    if [ "${ENV_SYSTEMD}" == "other" ]; then
        echo "Error: Cant install service on this system!"
        exit 3
    fi

    if [ ${SSM_SERVICE} -eq 0 ]; then
        echo "* Removing Old SSM Service"
        systemctl disable ${SSM_SERVICENAME} >/dev/null 2>&1
        rm -r "${SSM_SERVICEFILE}" >/dev/null 2>&1
        systemctl daemon-reload >/dev/null 2>&1
    fi

    echo "* Create SSM Service"

    cat >>${SSM_SERVICEFILE} <<EOL
[Unit]
Description=SatisfactoryServerManager Daemon
After=network.target

[Service]
User=root
Group=root

Type=simple
WorkingDirectory=/opt/SSM
ExecStart=/opt/SSM/SatisfactoryServerManager
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL
    echo "* Start SSM Service"
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable ${SSM_SERVICENAME} >/dev/null 2>&1
    systemctl start ${SSM_SERVICENAME} >/dev/null 2>&1

else
    echo "SSM Service Skipped"
    SSM_SERVICE=$(
        systemctl list-units --full -all | grep -Fq "${SSM_SERVICENAME}"
        echo $?
    )

    if [ ${SSM_SERVICE} -eq 0 ]; then
        echo "* Start SSM Service"
        systemctl start ${SSM_SERVICENAME} >/dev/null 2>&1
    fi
fi
