#!/bin/bash
# 带子菜单的总控脚本

cd "$(dirname "$0")"

# ===== 主菜单 =====
main_menu() {
  while true; do
    # clear
    echo "======================"
    echo "主菜单 - 请选择操作："
    echo "  1) 系统管理"
    echo "  2) Web 服务"
    echo "  3) 备份管理"
    echo "  4) 检测脚本"
    echo "  0) 退出"
    echo "======================"
    read -p "请输入数字 (0-4): " choice </dev/tty
    echo

    case "$choice" in
      1) system_menu ;;
      2) web_menu ;;
      3) backup_menu ;;
      4) detection_menu ;;
      0) echo "已退出。"; exit 0 ;;
      *) echo "无效选项，请按回车重试..."; read -p "" </dev/tty ;;
    esac
  done
}

# ===== 系统管理 =====
system_menu() {
  while true; do
    # clear
    echo "======================"
    echo "系统管理子菜单："
    echo "  1) 修改 SSH 端口"
    echo "  2) 查看系统信息"
    echo "  3) 修改时区"
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
      3)
        echo "执行：修改时区..."
        curl -sL https://raw.githubusercontent.com/cxwya/linux_script/main/script/system/set_timezone.sh | sudo bash
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
    # clear
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
    # clear
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

# ===== 检测 =====
detection_menu() {
  while true; do
    # clear
    echo "======================"
    echo "检测脚本："
    echo "  1) 酒神"
    echo "  2) 融合怪"
    echo "  3) YABS"
    echo "  4) Speedtest"
    echo "  5) 回程测试"
    echo "  6)  运行 Geekbench 5 测试并禁用 Geekbench 6 测试和iperf （网络性能） 测试"
    echo "  0) 返回主菜单"
    echo "======================"
    read -p "请选择 (0-6): " choice </dev/tty
    echo

    case "$choice" in
      1) 
        echo "执行：酒神脚本..."; 
        bash <(curl -sL https://Check.Place)
        read -p "按回车返回..." ;;
      2) 
        echo "执行：融合怪脚本..."; 
        curl -L https://github.com/spiritLHLS/ecs/raw/main/ecs.sh -o ecs.sh && chmod +x ecs.sh && bash ecs.sh
        read -p "按回车返回..." ;;
      3) 
        echo "执行：YABS脚本..."; 
        curl -sL https://yabs.sh | bash
        read -p "按回车返回..." ;;
      4)
        echo "执行：Speedtest脚本..."; 
        bash <(curl -sL bash.icu/speedtest)
        read -p "按回车返回..." ;;
      5) 
        echo "执行：回程测试脚本..."; 
        wget -N --no-check-certificate https://raw.githubusercontent.com/Chennhaoo/Shell_Bash/master/AutoTrace.sh && chmod +x AutoTrace.sh && bash AutoTrace.sh
        read -p "按回车返回..." ;;
      6) 
        echo "执行：运行 Geekbench 5 测试并禁用 Geekbench 6 测试和iperf （网络性能） 测试脚本..."; 
        curl -sL https://yabs.sh | bash -s -- -i -5
        read -p "按回车返回..." ;;
      0) return ;;
      *) echo "无效选项，按回车重试..."; read -p "" </dev/tty ;;
    esac
  done
}

# 启动主菜单
main_menu
