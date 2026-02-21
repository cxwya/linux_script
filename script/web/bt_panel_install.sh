#!/bin/bash
# 宝塔面板安装/管理脚本

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 权限运行：sudo $0"
  exit 1
fi

while true; do
  clear
  echo "======================"
  if [ -f "/usr/bin/bt" ] || [ -d "/www/server/panel" ]; then
    echo "当前状态：宝塔面板 [已安装]"
  else
    echo "当前状态：宝塔面板 [未安装]"
  fi
  echo
  echo "宝塔面板管理："
  echo "  1) 安装 宝塔面板"
  echo "  2) 卸载 宝塔面板"
  echo "  0) 退出"
  echo "======================"
  read -p "请选择 (0-2): " choice </dev/tty ;;
  echo

  case "$choice" in
    1)
      echo "执行：安装 宝塔面板..."
      if [ -f /usr/bin/curl ];then curl -sSO https://download.bt.cn/install/install_panel.sh;else wget -O install_panel.sh https://download.bt.cn/install/install_panel.sh;fi;bash install_panel.sh ed8484bec
      read -p "按回车继续..."
      ;;
    2)
      echo "执行：卸载 宝塔面板..."
      # 下载并运行官方卸载脚本
      wget -O bt-uninstall.sh http://download.bt.cn/install/bt-uninstall.sh && bash bt-uninstall.sh
      read -p "按回车继续..."
      ;;
    0)
      exit 0
      ;;
    *)
      echo "无效选项"
      read -p "按回车重试..."
      ;;
  esac
done
