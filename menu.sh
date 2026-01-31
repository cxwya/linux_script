#!/bin/bash
# 带子菜单的总控脚本

cd "$(dirname "$0")"

# ===== 主菜单 =====
main_menu() {
  while true; do
    clear
    echo "======================"
    echo "主菜单 - 请选择操作："
    echo "  1) 系统管理"
    echo "  2) Web 服务"
    echo "  3) 备份管理" 
    echo "  0) 退出"
    echo "======================"
    read -p "请输入数字 (0-3): " choice </dev/tty
    echo

    case "$choice" in
      1) system_menu ;;
      2) web_menu ;;
      3) backup_menu ;;
      0) echo "已退出。"; exit 0 ;;
      *) echo "无效选项，请按回车重试..."; read -p "" </dev/tty ;;
    esac
  done
}

# ===== 系统管理 =====
system_menu() {
  while true; do
    clear
    echo "======================"
    echo "系统管理子菜单："
    echo "  1) 修改 SSH 端口"
    echo "  2) 查看系统信息"
    echo "  0) 返回主菜单"
    echo "======================"
    read -p "请选择 (0-2): " choice </dev/tty
    echo

    case "$choice" in
      1) 
        echo "执行：修改 SSH 端口..."
        curl -sL https://raw.githubusercontent.com/cxwya/linux_script/main/script/system/change_ssh_port.sh | sudo bash
        read -p "按回车返回系统菜单..."
        ;;
      2)
        echo "系统信息："
        curl -sL https://raw.githubusercontent.com/cxwya/linux_script/main/script/system/system_info.sh | sudo bash
        read -p "按回车返回系统菜单..."
        ;;
      0) return ;;  # return 返回到调用者（主菜单）
      *) echo "无效选项，按回车重试..."; read -p "" </dev/tty ;;
    esac
  done
}

# ===== Web 服务 =====
web_menu() {
  while true; do
    clear
    echo "======================"
    echo "Web 服务菜单："
    echo "  1) 安装 Docker"
    echo "  2) 安装 Apache"
    echo "  0) 返回主菜单"
    echo "======================"
    read -p "请选择 (0-2): " choice </dev/tty
    echo

    case "$choice" in
      1) echo "执行：安装 Docker..."
         curl -sL https://raw.githubusercontent.com/cxwya/linux_script/main/script/web/docker_install.sh | sudo bash
         read -p "按回车返回系统菜单..."
         ;;
      2) echo "执行：安装 Apache..."; bash ./install_apache.sh; read -p "按回车返回..." ;;
      0) return ;;  # return 到主菜单
      *) echo "无效选项，按回车重试..."; read -p "" </dev/tty ;;
    esac
  done
}

# ===== 备份 =====
backup_menu() {
  while true; do
    clear
    echo "======================"
    echo "备份管理子菜单："
    echo "  1) 备份数据库"
    echo "  2) 备份配置文件"
    echo "  0) 返回主菜单"
    echo "======================"
    read -p "请选择 (0-2): " choice </dev/tty
    echo

    case "$choice" in
      1) echo "执行：备份数据库..."; bash ./backup_db.sh; read -p "按回车返回..." ;;
      2) echo "执行：备份配置文件..."; bash ./backup_config.sh; read -p "按回车返回..." ;;
      0) return ;;
      *) echo "无效选项，按回车重试..."; read -p "" </dev/tty ;;
    esac
  done
}

# 启动主菜单
main_menu
