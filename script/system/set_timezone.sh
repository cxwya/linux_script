#!/bin/bash

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误: 请使用 root 用户或 sudo 权限运行此脚本。"
  exit 1
fi

# 设置时区的核心函数
set_timezone() {
    local tz=$1
    echo ""
    echo "⏳ 正在将系统时区设置为: $tz ..."
    
    # 优先使用现代系统的 timedatectl
    if command -v timedatectl &> /dev/null; then
        timedatectl set-timezone "$tz"
    else
        # 兼容老旧系统
        if [ -f "/usr/share/zoneinfo/$tz" ]; then
            ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
            echo "$tz" > /etc/timezone
        else
            echo "❌ 错误: 系统中找不到该时区文件 (/usr/share/zoneinfo/$tz)"
            return 1
        fi
    fi
    
    echo "✅ 时区修改成功！"
    echo "⏱️ 当前系统时间为: $(date)"
    echo "----------------------------------------"
}

# 交互式菜单
show_menu() {
    clear
    echo "========================================"
    echo "          VPS 时区一键修改工具"
    echo "========================================"
    echo "  1. 中国 - 上海 (Asia/Shanghai)"
    echo "  2. 中国 - 香港 (Asia/Hong_Kong)"
    echo "  3. 新加坡 (Asia/Singapore)"
    echo "  4. 韩国 - 首尔 (Asia/Seoul)"
    echo "  5. 日本 - 东京 (Asia/Tokyo)"
    echo "  6. 美国 - 洛杉矶/美西 (America/Los_Angeles)"
    echo "  7. 美国 - 纽约/美东 (America/New_York)"
    echo "  8. 恢复默认 - 标准时间 (UTC)"
    echo "  0. 退出脚本"
    echo "========================================"
}

while true; do
    show_menu
    read -p "👉 请输入对应数字选择时区 [0-8]: " choice

    case $choice in
        1) set_timezone "Asia/Shanghai"; break ;;
        2) set_timezone "Asia/Hong_Kong"; break ;;
        3) set_timezone "Asia/Singapore"; break ;;
        4) set_timezone "Asia/Seoul"; break ;;
        5) set_timezone "Asia/Tokyo"; break ;;
        6) set_timezone "America/Los_Angeles"; break ;;
        7) set_timezone "America/New_York"; break ;;
        8) set_timezone "UTC"; break ;;
        0) echo "👋 已退出脚本。"; exit 0 ;;
        *) 
            echo "⚠️ 输入错误，请输入 0-8 之间的有效数字！"
            sleep 2
            ;;
    esac
done
