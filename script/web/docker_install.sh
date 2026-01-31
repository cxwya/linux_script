#!/bin/bash
# Docker 一键安装/管理循环脚本（完整版）
# 支持：源选择跳过返回主菜单、精确Docker检测、服务启停

set -e

echo "=== Docker 安装/管理脚本 ==="

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 权限运行：sudo $0"
  echo "按回车退出..."
  read -p ""
  exit 1
fi

# 精确检查 Docker 是否正常可用
check_docker_installed() {
  docker info >/dev/null 2>&1
}

# 源选择函数并安装 - 选择0返回主菜单
select_docker_source() {
  while true; do
    echo
    echo "请选择 Docker 安装源："
    echo "  1) DaoCloud（国内推荐）"
    echo "  2) Docker 官方源"
    echo "  3) 自动检测（默认）"
    echo "  0) 返回 Docker 主菜单"
    echo "======================"
    read -p "请输入数字 (0-3): " source_choice </dev/tty ;;
    echo

    # 默认值处理
    if [ -z "$source_choice" ]; then
      source_choice="3"
    fi

    case "$source_choice" in
      1)
        echo "使用 DaoCloud 国内源..."
        curl -sSL https://get.daocloud.io/docker | sh
        return 0
        ;;
      2)
        echo "使用 Docker 官方源..."
        wget -qO- get.docker.com | bash
        return 0
        ;;
      3)
        echo "自动检测网络环境..."
        if curl -s --connect-timeout 3 ipinfo.io/country 2>/dev/null | grep -qi "CN"; then
          echo "国内环境 → DaoCloud"
          curl -sSL https://get.daocloud.io/docker | sh
        else
          echo "国际环境 → 官方源"
          wget -qO- get.docker.com | bash
        fi
        return 0
        ;;
      0)
        echo "返回 Docker 主菜单..."
        return 1
        ;;
      *)
        echo "无效选项，请重新选择..."
        ;;
    esac
  done
}

# 主循环 - Docker 管理菜单
while true; do
  clear
  echo "======================"
  if check_docker_installed; then
    echo "✓ Docker 已安装：$(docker --version | head -1)"
  else
    echo "✗ Docker 未安装"
  fi
  echo
  echo "Docker 管理菜单："
  echo "  1) 安装/卸载 Docker"
  echo "  2) 启动/重启服务"
  echo "  3) 查看状态"
  echo "  4) 停止服务"
  echo "  0) 退出"
  echo "======================"
  read -p "请输入数字 (0-4): " choice </dev/tty ;;
  echo

  case "$choice" in
    1)
      echo "=== 安装/卸载 Docker ==="
      # 先卸载（如果已安装）
      if check_docker_installed; then
        while true; do
          echo "✓ Docker 已安装：$(docker --version | head -1)"
          read -p "检测到已安装，是否卸载重装？(y/n) " confirm </dev/tty ;;
          case "$confirm" in
          [Yy])
            echo "卸载 Docker..."
            apt-get remove -y docker docker-engine docker.io containerd runc || true
            apt-get purge -y docker-ce docker-ce-cli containerd.io || true
            yum remove -y docker docker-ce docker-ce-cli containerd.io || true
            rm -rf /var/lib/docker /etc/docker
            systemctl daemon-reload
            echo "======================"
            echo "✓ 卸载完成！"
            echo "======================"
            echo "按回车继续..."
            read -p ""
            continue 2
            ;;
          [Nn])
            echo "取消，按回车继续..."
            read -p ""
            continue 2
            ;;
          *)
            echo "请输入 y/Y（是）或 n/N（否），请重新输入！"
          esac
        done
      fi

      # 安装
      echo "✗ Docker 未安装"
      # 源选择 - 跳过直接回主菜单
      if ! select_docker_source; then
        echo "跳过安装，返回 Docker 菜单"
      else
        # 源选择成功，继续安装后续步骤
        echo "安装 docker.io 兼容包..."
        apt install -y docker.io 2>/dev/null || true
        systemctl start docker 2>/dev/null || service docker start || true
        systemctl enable docker 2>/dev/null || true
        
        echo "======================"
        echo "✓ Docker 安装完成！"
        echo "版本：$(docker --version | head -1)"
        echo "测试：docker run --rm hello-world"
        echo "======================"
        echo "按回车继续..."
        read -p ""
      fi
      ;;

    2)
      if check_docker_installed; then
        echo "启动/重启 Docker 服务..."
        systemctl restart docker 2>/dev/null || service docker restart || true
        systemctl enable docker 2>/dev/null || true
        echo "状态："
        systemctl is-active docker 2>/dev/null && echo "✓ 运行中" || echo "✗ 未运行"
        echo "按回车继续..."
        read -p ""
      else
        echo "✗ Docker 未安装！按回车继续..."
        read -p ""
      fi
      ;;
    3)
      if check_docker_installed; then
        echo "=== Docker 状态信息 ==="
        docker --version | head -1 2>/dev/null || echo "Docker 未安装"
        echo "服务状态：$(systemctl is-active --quiet docker 2>/dev/null && echo "运行中" || echo "停止")"
        if check_docker_installed; then
          echo "容器数：$(docker info --format '{{.Containers}}' 2>/dev/null || echo "未知")"
          echo "镜像数：$(docker info --format '{{.Images}}' 2>/dev/null || echo "未知")"
        fi
        echo "按回车继续..."
        read -p ""
      else
        echo "✗ Docker 未安装！按回车继续..."
        read -p ""
      fi
      ;;
      
    4)
    if check_docker_installed; then
      echo "停止 Docker 服务..."
      
      # 停止所有 Docker 相关服务
      for service in docker docker.service docker.socket containerd; do
        systemctl stop "$service" 2>/dev/null || true
      done
      
      # 老系统 service 命令
      for service in docker docker.socket containerd; do
        service "$service" stop 2>/dev/null || true
      done
      
      # 强制杀进程
      pkill -f dockerd 2>/dev/null || true
      pkill -f containerd 2>/dev/null || true
      
      sleep 2
      
      # 验证停止
      if ! pgrep -x dockerd >/dev/null 2>&1 && ! pgrep -x containerd >/dev/null 2>&1; then
        echo "✓ Docker 服务已完全停止"
      else
        echo "⚠ 仍有残留进程"
        pgrep -fa docker || pgrep -fa containerd || true
      fi
      echo "按回车继续..."
      read -p ""
    else
      echo "✗ Docker 未安装！按回车继续..."
      read -p ""
    fi
    ;;
    0)
      echo "退出 Docker 管理脚本"
      exit 0
      ;;
      
    *)
      echo "无效选项，请输入 0-4"
      echo "按回车重试..."
      read -p ""
      ;;
  esac
done
