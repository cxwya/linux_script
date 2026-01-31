#!/bin/bash
# 总控菜单脚本：根据用户选择执行不同子脚本

# 确保当前目录就是脚本所在目录
cd "$(dirname "$0")"

while true; do
  echo "======================"
  echo "请选择要执行的操作："
  echo "  1) 修改 SSH 端口"
  echo "  88) 退出"
  echo "======================"
  read -p "请输入数字并回车: " choice

  case "$choice" in
    1)
      echo "执行：修改 SSH 端口脚本..."
      # 加上 bash 或直接执行（前提是子脚本有执行权限）
      curl -sL https://raw.githubusercontent.com/cxwya/linux_script/main/change_ssh_port.sh | sudo bash
      ;;
    88)
      echo "退出。"
      exit 0
      ;;
    *)
      echo "无效选项，请重新输入。"
      ;;
  esac

  echo    # 每次执行完留一个空行，回到菜单
done