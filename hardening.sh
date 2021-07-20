#!/bin/sh
set -e

SYSTEM_ACCOUNTS="root nginx apache oracle sshd"
SUPPORT_OS="alpine debian ubuntu ol centos"
CURRENT_OS="unknown"
CURRENT_OS_VERSION="unknown"

function logging {
    echo $(date) "______" "$1"
}

function show_help {
    echo "Usage: $0 -u [app user]"
}

function detect_os {
    logging "Detecting operating system.."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        CURRENT_OS=$ID
        CURRENT_OS_VERSION="${VERSION:-$VERSION_ID}"
    else
        logging "Can not detect the operating system"
        exit 1
    fi

    if [ "${SUPPORT_OS/$CURRENT_OS}" != "$SUPPORT_OS" ] ; then
        logging "$CURRENT_OS detected, we can continue.."
    else
        logging "$CURRENT_OS is not supported yet."
        exit 1
    fi

}

function clear_cache {
    if [ "$CURRENT_OS" = "alpine" ]; then
        if [ "$user" = "nginx" ]; then
            # remove unnecesary packages and modules for nginx
            apk del --no-cache freetype libgd nginx-module-image-filter || true
        fi
        rm -f /var/cache/apk/*
    fi

    if [[ "$CURRENT_OS" = "debian" || "$CURRENT_OS" = "ubuntu" ]]; then
        apt-get clean
        apt-get autoclean
        rm -rf /var/lib/apt/lists/* 
    fi
    if [[ "$CURRENT_OS" = "ol" && "${CURRENT_OS_VERSION:0:1}" == "8" ]]; then
        yum clean packages -y
        yum clean all -y
    else
        if [[ "$CURRENT_OS" = "ol" || "$CURRENT_OS" = "centos" ]]; then
            yum clean headers -y
            yum clean packages -y
            yum clean all -y
            rpm --rebuilddb
        fi   
         
    fi
    rm -rf /tmp/* /var/tmp/*

}

function upgrade_os {
    if [ "$CURRENT_OS" = "alpine" ]; then
        apk update && apk upgrade --no-cache --available
    fi

    if [[ "$CURRENT_OS" = "debian" || "$CURRENT_OS" = "ubuntu" ]]; then
        apt-get update && apt-get upgrade -y --no-install-recommends
    fi

    if [[ "$CURRENT_OS" = "ol" || "$CURRENT_OS" = "centos" ]]; then
        yum update -y
    fi

}

function install_package {
    if [ "$CURRENT_OS" = "alpine" ]; then
        apk update && apk add --no-cache $1
    fi

    if [[ "$CURRENT_OS" = "debian" || "$CURRENT_OS" = "ubuntu" ]]; then
        apt-get update && apt-get install -y --no-install-recommends $1
    fi

    if [[ "$CURRENT_OS" = "ol" || "$CURRENT_OS" = "centos" ]]; then
        yum install -y $1
    fi

}

if [[ $# -eq 0 ]]; then
    show_help
    exit 1
fi

while getopts u:h opt; do
    case $opt in
    h)
        show_help
        exit 0
        ;;
    u)
        if [ -z "$OPTARG" ]; then
            logging "Error, user app was not provided.."
            show_help
            exit 1
        else
            user="$OPTARG"
        fi
        ;;
    *)
        show_help >&2
        exit 1
        ;;
    esac
done

detect_os

 
logging "Upgrade operating system packages..."
upgrade_os

logging "Adding bash..."  
install_package bash

if [ -z "$user" ]; then
        logging "Error, user app was not provided.."
        show_help
        exit 1
fi

if [ "${SYSTEM_ACCOUNTS/$user}" = "$SYSTEM_ACCOUNTS" ] ; then

    # Privilegios sudo sin contraseña limitado para ejecutar apk
    logging "Adding restricted sudo access for user $user..."
    install_package sudo

    if [ "$CURRENT_OS" = "alpine" ]; then
        echo "#/etc/sudoers.d/sudo-$user
        Cmnd_Alias APP_CMDS = /sbin/apk
        $user ALL=NOPASSWD: APP_CMDS" >> /etc/sudoers.d/sudo-$user
    fi

    if [[ "$CURRENT_OS" = "debian" || "$CURRENT_OS" = "ubuntu" ]]; then
        echo "#/etc/sudoers.d/sudo-$user
        Cmnd_Alias APP_CMDS = /usr/bin/apt-get
        $user ALL=NOPASSWD: APP_CMDS" >> /etc/sudoers.d/sudo-$user
    fi

    if [[ "$CURRENT_OS" = "ol" || "$CURRENT_OS" = "centos" ]]; then
        echo "#/etc/sudoers.d/sudo-$user
        Cmnd_Alias APP_CMDS = /usr/bin/yum
        $user ALL=NOPASSWD: APP_CMDS" >> /etc/sudoers.d/sudo-$user
    fi

    chmod 440 /etc/sudoers.d/sudo-$user
fi

logging "Removing all unnecesary accounts except root and $user..."
# Remover cuentas innecesarias solo dejamos algunos
sed -i -r '/^('"${user}"'|root)/!d' /etc/group
sed -i -r '/^('"${user}"'|root)/!d' /etc/passwd

logging "Removing all unnecesary cron jobs..."
# Remover existentes crontabs
rm -fr /var/spool/cron
rm -fr /etc/crontabs
rm -fr /etc/periodic

sysdirs="
  /bin
  /etc
  /lib
  /sbin
  /usr
"

logging "root must be owner on system directories..." 
# revision de directorios del sistema
find $sysdirs -xdev -type d \
  -exec chown root:root {} \; \
  -exec chmod 0755 {} \;

logging "Removing suid binaries except sudo..." 
# Remover los archivos suid except sudo binary
find $sysdirs -xdev -type f \( ! -iname "sudo" \) -a -perm /4000 -delete

logging "Removing unnecesary and dangerous programs..." 
# eliminar programas peligrosos
find $sysdirs -xdev \( \
  -name dos2unix -o \
  -name crontab -o \
  -name ftpget -o \
  -name ftpput -o \
  -name nc -o \
  -name telnet -o \
  -name resize -o \
  -name tftp -o \
  -name killall -o \
  -name eject -o \
  -name awk -o \
  -name blkdiscard -o \
  -name bunzip2 -o \
  -name bzcat -o \
  -name bzip2 -o \
  -name cal -o \
  -name beep -o \
  -name chvt -o \
  -name cpio -o \
  -name strings -o \
  -name su \
  \) -delete || true

logging "Removing init scripts .." 
# eliminar script de inicio
rm -fr /etc/init.d
rm -fr /lib/rc
rm -fr /etc/conf.d
rm -fr /etc/inittab
rm -fr /etc/runlevels
rm -fr /etc/rc.conf

logging "Removing fstab..." 
# eliminar fstab
rm -f /etc/fstab

logging "Cleaning cache..." 
clear_cache
