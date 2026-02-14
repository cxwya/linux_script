#!/bin/bash

# 定义颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 此脚本必须以 root 权限运行。${NC}"
   echo -e "请使用: ${YELLOW}sudo $0${NC}"
   exit 1
fi

# 获取当前 Swap 信息
function show_current_swap() {
    echo -e "${CYAN}--- 当前 Swap 状态 ---${NC}"
    swapon --show
    free -h | grep -i swap
    echo -e "${CYAN}----------------------${NC}"
}

# 添加 Swap
function add_swap() {
    echo -e "${YELLOW}准备添加 Swap...${NC}"
    
    # 1. 设置路径
    read -p "请输入 Swap 文件路径 (默认: /swapfile): " SWAP_FILE </dev/tty
    SWAP_FILE=${SWAP_FILE:-/swapfile}

    if [ -f "$SWAP_FILE" ]; then
        echo -e "${RED}错误: 文件 $SWAP_FILE 已存在！请先删除或更换路径。${NC}"
        return
    fi

    # 2. 设置大小
    read -p "请输入 Swap 大小 (单位 MB, 例如 1024 代表 1GB): " SWAP_SIZE </dev/tty
    if ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 请输入有效的数字。${NC}"
        return
    fi

    echo -e "正在创建 ${SWAP_SIZE}MB 的 Swap 文件，请稍候..."
    
    # 使用 dd 创建文件 (兼容性最好)
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE" status=progress
    if [ $? -ne 0 ]; then
        echo -e "${RED}创建文件失败。${NC}"
        return
    fi

    # 3. 设置权限
    chmod 600 "$SWAP_FILE"
    
    # 4. 格式化为 Swap
    mkswap "$SWAP_FILE"
    
    # 5. 启用 Swap
    swapon "$SWAP_FILE"
    if [ $? -ne 0 ]; then
        echo -e "${RED}启用 Swap 失败。${NC}"
        # 回滚：删除文件
        rm -f "$SWAP_FILE"
        return
    fi

    # 6. 写入 fstab 实现持久化
    echo -e "正在备份 /etc/fstab 到 /etc/fstab.bak ..."
    cp /etc/fstab /etc/fstab.bak
    
    if grep -q "$SWAP_FILE" /etc/fstab; then
        echo -e "${YELLOW}警告: fstab 中已存在该条目，跳过写入。${NC}"
    else
        echo "$SWAP_FILE swap swap defaults 0 0" >> /etc/fstab
        echo -e "${GREEN}已将配置写入 /etc/fstab。${NC}"
    fi

    echo -e "${GREEN}成功！Swap 已添加并启用。${NC}"
    show_current_swap
}

# 删除 Swap
function remove_swap() {
    echo -e "${YELLOW}准备删除 Swap...${NC}"
    show_current_swap
    
    read -p "请输入要删除的 Swap 文件路径 (默认: /swapfile): " SWAP_FILE </dev/tty
    SWAP_FILE=${SWAP_FILE:-/swapfile}

    if [ ! -f "$SWAP_FILE" ]; then
        echo -e "${RED}错误: 文件 $SWAP_FILE 不存在。${NC}"
        return
    fi

    # 确认操作
    read -p "确定要删除 $SWAP_FILE 吗？(y/n): " CONFIRM </dev/tty
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo -e "${YELLOW}操作已取消。${NC}"
        return
    fi

    # 1. 关闭 Swap
    echo -e "正在关闭 Swap (这可能需要一点时间)..."
    swapoff "$SWAP_FILE"
    if [ $? -ne 0 ]; then
        echo -e "${RED}关闭 Swap 失败！可能正在被大量使用或路径错误。${NC}"
        return
    fi

    # 2. 从 fstab 移除
    echo -e "正在备份 /etc/fstab 到 /etc/fstab.bak ..."
    cp /etc/fstab /etc/fstab.bak
    
    # 使用 sed 删除包含该文件路径的行
    # 使用 | 作为分隔符以避免路径中的 / 冲突
    sed -i "\|$SWAP_FILE|d" /etc/fstab
    echo -e "${GREEN}已从 /etc/fstab 移除配置。${NC}"

    # 3. 删除文件
    rm -f "$SWAP_FILE"
    echo -e "${GREEN}文件 $SWAP_FILE 已删除。${NC}"
    
    echo -e "${GREEN}成功！Swap 已移除。${NC}"
    show_current_swap
}

# 主菜单
while true; do
    echo -e "\n${CYAN}=== Linux Swap 管理脚本 ===${NC}"
    echo "1. 添加 Swap"
    echo "2. 删除 Swap"
    echo "3. 查看当前 Swap"
    echo "0. 退出"
    read -p "请输入选项 [0-3]: " OPTION </dev/tty

    case $OPTION in
        1)
            add_swap
            ;;
        2)
            remove_swap
            ;;
        3)
            show_current_swap
            ;;
        0)
            echo -e "${GREEN}退出脚本。${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重试。${NC}"
            ;;
    esac
done
