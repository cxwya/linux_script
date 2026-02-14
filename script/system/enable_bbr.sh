#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须以 root 权限运行此脚本。${NC}"
   exit 1
fi

# 检查内核版本 (BBR 需要 Linux Kernel 4.9+)
check_kernel() {
    local kernel_version=$(uname -r)
    local major_version=$(echo "$kernel_version" | cut -d. -f1)
    local minor_version=$(echo "$kernel_version" | cut -d. -f2)

    echo -e "当前内核版本: ${CYAN}$kernel_version${NC}"

    if [[ "$major_version" -lt 4 ]] || [[ "$major_version" -eq 4 && "$minor_version" -lt 9 ]]; then
        echo -e "${RED}错误: BBR 需要 Linux 内核版本 >= 4.9。${NC}"
        echo -e "请先升级内核再运行此脚本。"
        exit 1
    fi
}

# 开启 BBR
enable_bbr() {
    echo -e "${YELLOW}正在配置 BBR...${NC}"

    # 备份 sysctl.conf
    if [ ! -f /etc/sysctl.conf.bak ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.bak
        echo -e "已备份配置文件到 /etc/sysctl.conf.bak"
    fi

    # 清理旧配置 (避免重复)
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

    # 写入新配置
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf

    # 应用更改
    sysctl -p > /dev/null 2>&1
    
    echo -e "${GREEN}BBR 配置已应用。${NC}"
    echo -e "${YELLOW}提示: 为了确保更改完全生效，建议重启服务器 (reboot)。${NC}"
}

# 关闭 BBR
disable_bbr() {
    echo -e "${YELLOW}正在关闭 BBR...${NC}"

    # 清理配置
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

    # 应用更改
    sysctl -p > /dev/null 2>&1
    
    echo -e "${GREEN}BBR 配置已移除。${NC}"
    echo -e "${YELLOW}提示: 为了确保更改完全生效，建议重启服务器 (reboot)。${NC}"
}

# 验证状态
check_status() {
    echo -e "\n${CYAN}--- BBR 状态检查 ---${NC}"
    
    local sysctl_check=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [[ "$sysctl_check" == "bbr" ]]; then
        echo -e "拥塞控制算法: ${GREEN}$sysctl_check (已开启)${NC}"
    else
        echo -e "拥塞控制算法: ${RED}$sysctl_check (未开启)${NC}"
    fi
}

# 主逻辑
check_kernel

while true; do
    echo -e "\n${CYAN}=== Linux BBR 管理脚本 ===${NC}"
    echo "1. 开启 BBR"
    echo "2. 关闭 BBR"
    echo "3. 查看状态"
    echo "0. 退出"
    read -p "请输入选项 [0-3]: " OPTION </dev/tty
    
    OPTION=$(echo "$OPTION" | tr -d '[:space:]')

    case $OPTION in
        1)
            enable_bbr
            check_status
            ;;
        2)
            disable_bbr
            check_status
            ;;
        3)
            check_status
            ;;
        0)
            echo -e "${GREEN}退出脚本。${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项。${NC}"
            ;;
    esac
done