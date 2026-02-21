#!/bin/bash
# Docker Compose 一键安装/管理脚本
# 包含：架构自动识别、国内/国际源选择、版本管理

set -e

echo "=== Docker Compose 安装/管理脚本 ==="

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 权限运行：sudo $0"
  echo "按回车退出..."
  read -p ""
  exit 1
fi

# 获取系统架构
get_arch() {
  local arch=$(uname -m)
  case $arch in
    x86_64)
      echo "x86_64"
      ;;
    aarch64|arm64)
      echo "aarch64"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# 获取最新版本号
get_latest_version() {
  # 尝试联网获取最新版本，超时3秒
  local latest=$(curl -s --connect-timeout 3 https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  if [ -z "$latest" ]; then
    # 获取失败时的默认版本 (建议定期更新此默认值)
    echo "v2.29.2"
  else
    echo "$latest"
  fi
}

# 源选择函数
select_compose_source() {
  while true; do
    echo
    echo "请选择下载源："
    echo "  1) 国内环境 (使用 ghproxy 镜像加速)"
    echo "  2) 国际环境 (GitHub 官方源)"
    echo "  3) 自动检测 (默认)"
    echo "  0) 返回上一级"
    echo "======================"
    read -p "请输入数字 (0-3): " source_choice </dev/tty
    echo

    if [ -z "$source_choice" ]; then
      source_choice="3"
    fi

    case "$source_choice" in
      1)
        echo "使用国内镜像源..."
        BASE_URL="https://ghproxy.net/https://github.com/docker/compose/releases/download"
        return 0
        ;;
      2)
        echo "使用 GitHub 官方源..."
        BASE_URL="https://github.com/docker/compose/releases/download"
        return 0
        ;;
      3)
        echo "自动检测网络环境..."
        # 尝试连接 Google 判断是否为国际环境
        if curl -s --connect-timeout 2 https://www.google.com >/dev/null; then
          echo "国际环境 → 官方源"
          BASE_URL="https://github.com/docker/compose/releases/download"
        else
          echo "国内环境 → 镜像源"
          BASE_URL="https://ghproxy.net/https://github.com/docker/compose/releases/download"
        fi
        return 0
        ;;
      0)
        return 1
        ;;
      *)
        echo "无效选项，请重新选择..."
        ;;
    esac
  done
}

# 主循环
while true; do
  clear
  echo "======================"
  if command -v docker-compose >/dev/null 2>&1; then
    echo "✓ Docker Compose 已安装：$(docker-compose --version)"
  else
    echo "✗ Docker Compose 未安装"
  fi
  echo
  echo "Docker Compose 管理菜单："
  echo "  1) 安装/更新 Docker Compose"
  echo "  2) 卸载 Docker Compose"
  echo "  0) 退出"
  echo "======================"
  read -p "请输入数字 (0-2): " choice </dev/tty
  echo

  case "$choice" in
    1)
      # 检查架构
      ARCH=$(get_arch)
      if [ "$ARCH" == "unknown" ]; then
        echo "错误：不支持的系统架构 $(uname -m)"
        read -p "按回车继续..."
        continue
      fi

      # 获取版本
      echo "正在获取最新版本信息..."
      VERSION=$(get_latest_version)
      echo "目标版本：$VERSION"
      echo "系统架构：$ARCH"

      # 选择源
      if ! select_compose_source; then
        continue
      fi

      # 构造下载链接
      DOWNLOAD_URL="${BASE_URL}/${VERSION}/docker-compose-linux-${ARCH}"
      INSTALL_PATH="/usr/local/bin/docker-compose"

      echo "正在下载：$DOWNLOAD_URL"
      curl -L "$DOWNLOAD_URL" -o "$INSTALL_PATH"

      if [ $? -eq 0 ]; then
        chmod +x "$INSTALL_PATH"
        # 尝试建立软链接，防止路径不在 PATH 中
        ln -sf "$INSTALL_PATH" /usr/bin/docker-compose
        
        echo "======================"
        echo "✓ 安装成功！"
        echo "版本：$(docker-compose --version)"
        echo "======================"
      else
        echo "======================"
        echo "✗ 下载失败！"
        echo "请检查网络连接或尝试切换源。"
        echo "======================"
      fi
      read -p "按回车继续..."
      ;;
    
    2)
      echo "正在卸载 Docker Compose..."
      rm -f /usr/local/bin/docker-compose
      rm -f /usr/bin/docker-compose
      echo "✓ 卸载完成"
      read -p "按回车继续..."
      ;;

    0)
      echo "退出脚本"
      exit 0
      ;;

    *)
      echo "无效选项"
      read -p "按回车重试..."
      ;;
  esac
done