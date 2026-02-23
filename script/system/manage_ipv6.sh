#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置文件路径
SYSCTL_CONF="/etc/sysctl.conf"

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须以 root 权限运行此脚本。${NC}"
   echo -e "请使用: ${YELLOW}sudo $0${NC}"
   exit 1
fi

# 查看 IPv6 状态
check_status() {
    echo -e "\n${CYAN}--- IPv6 状态检查 ---${NC}"
    
    # 检查内核参数 (0: 开启, 1: 关闭)
    local is_disabled=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)
    
    if [[ "$is_disabled" == "0" ]]; then
        echo -e "IPv6 功能: ${GREEN}已开启 (Enabled)${NC}"
        
        # 尝试获取 IPv6 地址信息
        local ip6_addr=$(ip -6 addr show | grep inet6 | grep -v "::1/128" | awk '{print $2}' | head -n 1)
        if [ -n "$ip6_addr" ]; then
            echo -e "当前 IPv6 地址: ${YELLOW}$ip6_addr${NC}"
        else
            echo -e "${YELLOW}提示: 内核已开启 IPv6，但未检测到公网 IPv6 地址 (可能是网卡未配置或无网络)。${NC}"
        fi
    else
        echo -e "IPv6 功能: ${RED}已禁用 (Disabled)${NC}"
    fi
}

# 修改配置函数
apply_ipv6_config() {
    local enable=$1 # 0 for enable, 1 for disable
    local action_name=""
    
    if [ "$enable" -eq 0 ]; then
        action_name="开启"
    else
        action_name="禁用"
    fi

    echo -e "${YELLOW}正在${action_name} IPv6...${NC}"

    # 备份配置文件
    if [ ! -f "${SYSCTL_CONF}.bak" ]; then
        cp "$SYSCTL_CONF" "${SYSCTL_CONF}.bak"
        echo "已备份配置文件到 ${SYSCTL_CONF}.bak"
    fi

    # 清理旧的配置 (防止重复堆叠)
    sed -i '/net.ipv6.conf.all.disable_ipv6/d' "$SYSCTL_CONF"
    sed -i '/net.ipv6.conf.default.disable_ipv6/d' "$SYSCTL_CONF"
    sed -i '/net.ipv6.conf.lo.disable_ipv6/d' "$SYSCTL_CONF"

    # 写入新配置
    echo "net.ipv6.conf.all.disable_ipv6 = $enable" >> "$SYSCTL_CONF"
    echo "net.ipv6.conf.default.disable_ipv6 = $enable" >> "$SYSCTL_CONF"
    echo "net.ipv6.conf.lo.disable_ipv6 = $enable" >> "$SYSCTL_CONF"

    # 应用更改
    sysctl -p > /dev/null 2>&1
    
    echo -e "${GREEN}IPv6 已${action_name}。${NC}"
    
    # 如果是开启，提示用户可能需要重启网卡
    if [ "$enable" -eq 0 ]; then
        echo -e "${YELLOW}注意: 如果未获取到 IP，尝试重启服务器或运行 'systemctl restart networking' (风险操作，可能断连)。${NC}"
    fi
}

# 主菜单
while true; do
    echo -e "\n${CYAN}=== Linux IPv6 管理脚本 ===${NC}"
    echo "1. 开启 IPv6"
    echo "2. 禁用 IPv6"
    echo "3. 查看状态"
    echo "0. 退出"
    read -p "请输入选项 [0-3]: " OPTION </dev/tty
    
    OPTION=$(echo "$OPTION" | tr -d '[:space:]')

    case $OPTION in
        1)
            apply_ipv6_config 0
            check_status
            ;;
        2)
            apply_ipv6_config 1
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