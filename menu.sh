#!/bin/bash
# 总控菜单脚本：根据用户选择执行不同子脚本

# 确保当前目录就是脚本所在目录
cd "$(dirname "$0")"

while true; do
  clear  # 清屏让菜单更清晰
  echo "======================"
  echo "请选择要执行的操作："
  echo "  1) 修改 SSH 端口"
  echo "  88) 退出"
  echo "======================"
  
  # 只读一个字符，并强制从键盘设备读，避免管道污染
  read -n 1 -p "请输入数字: " choice </dev/tty
  echo    # 换行
  
  case "$choice" in
    1)
      echo "执行：修改 SSH 端口脚本..."
      curl -sL https://raw.githubusercontent.com/cxwya/linux_script/main/script/change_ssh_port.sh | sudo bash
      read -p "按回车返回菜单..."
      ;;
    0)
      echo "已退出菜单。"
      exit 0
      ;;
    *)
      echo "无效选项 '$choice'，请重新输入。"
      read -p "按回车继续..."
      ;;
  esac
done
