#!/bin/bash
# 系统信息查看脚本
# 用法：bash system_info.sh 或 ./system_info.sh

echo "======================"
echo "系统信息概览"
echo "======================"

# 基本系统信息
echo "1. 基本信息："
echo "   主机名：$(hostname)"
echo "   系统：$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "   内核：$(uname -r)"
echo "   架构：$(uname -m)"
echo
echo "2. CPU 信息："
echo "   核心数：$(nproc) 核"
echo "   CPU型号：$(lscpu | grep 'Model name' | head -1 | cut -d':' -f2 | xargs)"
echo
echo "3. 内存信息："
free -h | sed 's/^/   /'
echo
echo "4. 磁盘使用情况："
df -h | head -5 | sed 's/^/   /'  # 只显示前5行（根分区等）
echo
echo "5. 网络信息："
echo "   IP地址："
ip addr show | grep 'inet ' | grep -v 127.0.0.1 | awk '{print "   " $2}' | cut -d/ -f1 | head -3
echo
echo "6. 运行进程数："
echo "   总进程：$(ps aux | wc -l) 个"
echo "   负载：$(uptime | awk '{print $(NF-2)" "$(NF-1)" "$(NF)}')"
echo
echo "7. SSH 服务状态："
if systemctl is-active --quiet sshd 2>/dev/null; then
  echo "   SSH 服务：运行中"
elif systemctl is-active --quiet ssh 2>/dev/null; then
  echo "   SSH 服务：运行中"
else
  echo "   SSH 服务：未运行"
fi

printf "======================"
printf "信息查看完成。"
printf "======================"
printf "按回车退出..."
read -p ""
