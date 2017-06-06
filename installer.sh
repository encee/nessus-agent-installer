#!/bin/bash

getHostInfo(){
    echo "Gathering host info..."
    if $(hash lsb_release &> /dev/null); then
        OS=$(lsb_release -si|tr '[:upper:]' '[:lower:]')
        OS_VER=$(lsb_release -sr|tr -d '.')
        OS_CNAME=$(lsb_release -sc|tr '[:upper:]' '[:lower:]')
        OS_DESC=$(lsb_release -sd|tr '[:upper:]' '[:lower:]')
    elif [[ -f /etc/os-release ]]; then
        soure /etc/os-release
        OS=$(echo $DISTRIB_ID |tr '[:upper:]' '[:lower:]')
        OS_VER=$(echo $DISTRIB_RELEASE |tr -d '.')
        OS_CNAME=$(echo $DISTRIB_CODENAME |tr '[:upper:]' '[:lower:]')
        OS_DESC=$(echo $DISTRIB_DESCRIPTION |tr '[:upper:]' '[:lower:]')
    elif [[ -f /etc/redhat-release ]]; then
        OS=$(cat /etc/centos-release |awk {'print $1'} |tr '[:upper:'] '[:lower:]')
        OS_VER=$(cat /etc/centos-release |awk {'print $3'}|awk -F"." {'print $1'})
        OS_CNAME="$OS $OS_VER"
        OS_DESC="$OS_CNAME"
    else
        echo "Unable to determine host information"
        exit 1
    fi
    ARCH=$(uname -m)
    echo "Host is $OS - $OS_VER"
}

downloadAgent(){
    filePrefix="NessusAgent-6.10.7"
    fileDelim="."
    if [ ! -z $OS ] && [ ! -z $OS_VER ]; then
        case $OS in
            "ubuntu" )
                case $OS_VER in
                    1110 | 1204 | 1210 | 1304 | 1310 | 1404 | 1604 |1704)
                        OS_FILE="ubuntu1110"
                    ;;
                    910 | 1004 )
                        OS_FILE="ubuntu910"
                    ;;
                    * )
                        echo "Unsupported version $OS - $OS_VER"
                        exit 1
                esac
                fileExt="deb"
                fileDelim="_"
                ARCH=$(echo $ARCH |sed -e 's/x86_64/amd64/')
            ;;
            "debian" )
                case $OS_VER in
                    6 | 7 | 8 )
                        OS_FILE="debian6"
                        fileExt="deb"
                    ;;
                    * )
                    echo "Unsupported version $OS - $OS_VER"
                    exit 1
                esac
                fileDelim="_"
                fileExt="deb"
            ;;
            "fedora" )
                case $OS_VER in
                    20 | 21 )
                        OS_FILE="fc20"
                    ;;
                    * )
                        echo "Unsupported version $OS - $OS_VER"
                        exit 1
                esac
                fileExt="rpm"
                ARCH=$(echo $ARCH |sed -e 's/x86_64/amd64/')
            ;;
            "centos" | "redhat" )
                case $OS_VER in
                    5 | 6 | 7 )
                        OS_FILE="es${OS_VER}"
                    ;;
                    * )
                        echo "Unsupported version $OS - $OS_VER"
                        exit 1
                    ;;
                esac
                fileExt="rpm"
            ;;
            "amzn" )
            ;;
        esac
    else
        echo "Undetected os and os version"
        exit 1
    fi
    fileSuffix="${OS_FILE}${fileDelim}${ARCH}.${fileExt}"

    echo "Acquiring tenable timestamp..."
    con="https://downloads.nessus.org/nessus3dl.php?file=${filePrefix}-${fileSuffix}&licence_accept=yes"
    timestamp=$(wget -qO- $con|grep 'timecheck' |awk -F">" {'print $5'}|awk -F"<" {'print $1'})

    echo "Downloading file - $fileSuffix"
    fullCon="${con}&t=${timestamp}"
    wget -O $fileSuffix $fullCon
}

installAgent(){
    echo "Installing file - $fileSuffix"
    case $fileExt in
        "rpm" )
            if $(hash yum &> /dev/null); then
                install_command="sudo yum install -y"
            else
                echo "Unable to locate yum installer for $fileSuffix."
                exit 1
            fi
        ;;
        "deb")
            if $(hash dpkg &> /dev/null); then
                install_command="DEBIAN_FRONTEND=noninteractive sudo dpkg -i"
            else
                echo "Unable to locate dpkg installer for $fileSuffix"
            fi
        ;;
        * )
            echo "Unknown package type $fileExt"
            exit 1
        ;;
    esac
    eval "$install_command $fileSuffix"
}

connectAgent(){
    /opt/nessus_agent/sbin/nessuscli agent link \
        --key=${license} \
        --name=${agentName:-$(hostname)} \
        --groups=${groups:-"All"} \
        --host=${host} \
        --port=${port:-8834}
}

usage(){
    echo "Usage: $0"
    echo ""
    echo "-a   : agent name (Optional)"
    echo "-g   : groups for agent to join (Optional)"
    echo "-h   : host to connect to (Required)"
    echo "-l   : license key (Required)"
    echo "-p   : port (Optional)"
}

validate(){
  local errors=()
  [ -z "$host" ]    && errors=( "${errors[@]}" "host option is required." )
  [ -z "$license" ] && errors=( "${errors[@]}" "license option is required." )
  [ $EUID -ne 0 ]   && errors=( "${errors[@]}" "must be ran as root." )

  local size=${#errors[*]}

  if [ ${#errors[@]} -gt 0 ]; then
      for (( i=0; i<$size; i++ )); do
        echo "config error: ${errors[$i]}"
      done
      exit 1
  fi
}
main(){
  while getopts ":a:g:h:l:p:" o; do
    case "${o}" in
        a) agentName=${OPTARG};;
        g) groups=${OPTARG};;
        h) host=${OPTARG};;
        l) license=${OPTARG};;
        p) port=${OPTARG};;
        *) usage;;
    esac
  done
  shift $((OPTIND-1))
  validate
  getHostInfo
  downloadAgent
  installAgent
}

main "$@"
