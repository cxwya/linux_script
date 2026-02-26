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
   echo -e "请使用: ${YELLOW}sudo $0${NC}"
   exit 1
fi

# 修改密码核心函数
do_change_password() {
    local user=$1
    
    # 检查用户是否存在
    if ! id "$user" &>/dev/null; then
        echo -e "${RED}错误: 用户 '$user' 不存在。${NC}"
        return
    fi

    echo -e "正在修改用户 ${CYAN}$user${NC} 的密码。"
    
    # 读取密码 (使用 /dev/tty 确保在管道执行时也能读取)
    while true; do
        echo -n "请输入新密码: "
        read -s pass1 </dev/tty
        echo
        echo -n "请再次输入新密码: "
        read -s pass2 </dev/tty
        echo

        if [ -z "$pass1" ]; then
            echo -e "${RED}密码不能为空，请重新输入。${NC}"
            continue
        fi

        if [ "$pass1" == "$pass2" ]; then
            break
        else
            echo -e "${RED}两次输入的密码不一致，请重新输入。${NC}"
        fi
    done

    # 使用 chpasswd 修改密码 (支持管道执行)
    echo "$user:$pass1" | chpasswd
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}成功: 用户 $user 的密码已修改。${NC}"
    else
        echo -e "${RED}失败: 密码修改遇到错误。${NC}"
    fi
}

while true; do
    echo -e "\n${CYAN}=== 修改服务器密码 ===${NC}"
    echo "1. 修改 root 密码"
    echo "2. 修改指定用户密码"
    echo "0. 退出"
    read -p "请输入选项 [0-2]: " OPTION </dev/tty

    case $OPTION in
        1) do_change_password "root" ;;
        2) read -p "请输入用户名: " u </dev/tty; do_change_password "$u" ;;
        0) echo -e "${GREEN}退出脚本。${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选项。${NC}" ;;
    esac
done