#!/bin/sh

DigVPS_BASE_PATH="/opt/digvps"
DigVPS_AGENT_PATH="${DigVPS_BASE_PATH}/agent"
DigVPS_LOG_FILE="/opt/digvps/agent.log"
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
export PATH="$PATH:/usr/local/bin"

sudo() {
    myEUID=$(id -ru)
    if [ "$myEUID" -ne 0 ]; then
        if command -v sudo > /dev/null 2>&1; then
            command sudo "$@"
        else
            err "错误: 您的系统未安装 sudo，因此无法进行该项操作。"
            exit 1
        fi
    else
        "$@"
    fi
}

check_systemd() {
    if [ "$os_alpine" != 1 ] && ! command -v systemctl >/dev/null 2>&1; then
        echo "不支持此系统：未找到 systemctl 命令"
        exit 1
    fi
}

err() {
    printf "${red}%s${plain}\n" "$*" >&2
}

success() {
    printf "${green}%s${plain}\n" "$*"
}

info() {
    printf "${yellow}%s${plain}\n" "$*"
}

install_base() {
    (command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 && command -v getenforce >/dev/null 2>&1) ||
        (install_soft curl wget unzip)
}

install_soft() {
    (command -v yum >/dev/null 2>&1 && sudo yum makecache && sudo yum install "$@" selinux-policy -y) ||
        (command -v apt >/dev/null 2>&1 && sudo apt update && sudo apt install "$@" selinux-utils -y) ||
        (command -v pacman >/dev/null 2>&1 && sudo pacman -Syu "$@" base-devel --noconfirm && install_arch) ||
        (command -v apt-get >/dev/null 2>&1 && sudo apt-get update && sudo apt-get install "$@" selinux-utils -y) ||
        (command -v apk >/dev/null 2>&1 && sudo apk update && sudo apk add "$@" -f)
}


selinux() {
    #Check SELinux
    if command -v getenforce >/dev/null 2>&1; then
        if getenforce | grep '[Ee]nfor'; then
            echo "SELinux是开启状态，正在关闭！"
            sudo setenforce 0 >/dev/null 2>&1
            find_key="SELINUX="
            sudo sed -ri "/^$find_key/c${find_key}disabled" /etc/selinux/config
        fi
    fi
}

install_agent() {
    install_base
    selinux

    echo "> 安装Agent"

    echo "正在获取Agent版本号"

    _version=$(curl -m 10 -sL "https://api.github.com/repos/bihell/digvps-agent/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    echo "当前最新版本为： ${_version}"

    echo "正在下载客户端"

    DigVPS_AGENT_URL="https://github.com/bihell/digvps-agent/releases/download/${_version}/agent.zip"

    _cmd="wget -t 2 -T 60 -O agent.zip $DigVPS_AGENT_URL >/dev/null 2>&1"
    if ! eval "$_cmd"; then
        err "Release 下载失败，请检查本机能否连接 ${GITHUB_URL}"
        return 1
    fi
    echo "解压客户端"
    sudo mkdir -p $DigVPS_BASE_PATH
    sudo unzip -qo agent.zip &&
    sudo mv agent $DigVPS_AGENT_PATH &&
    sudo rm -rf agent.zip
}

restart() {
    # 检查程序是否运行并停止
    PID=$(pgrep -f "$DigVPS_AGENT_PATH")
    if [ -n "$PID" ]; then
        echo "Stopping agent (PID: $PID)..."
        kill "$PID"
        sleep 2
        if pgrep -f "$DigVPS_AGENT_PATH" > /dev/null; then
            echo "Force stopping agent..."
            kill -9 "$PID"
        fi
    else
        echo "Agent is not running."
    fi

    # 启动程序
    if [ -x "$DigVPS_AGENT_PATH" ]; then
        echo "Starting agent..."
        nohup "$DigVPS_AGENT_PATH" > "$DigVPS_LOG_FILE" 2>&1 &
        echo "Agent started with PID: $!"
    else
        echo "Error: $DigVPS_AGENT_PATH is not executable or not found."
        exit 1
    fi
}

if [ $# -gt 0 ]; then
    case $1 in
        "install")
            install 0
            ;;
        "restart")
            restart 0
            ;;
    esac
else
    install 0
fi
