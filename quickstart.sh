#!/bin/bash
set -e

# 你所有脚本的文件名
files=(
    gost_docker_manager.sh
)

# 创建目标目录
mkdir -p docker_gost_manager/sh

# 下载所有脚本
for file in "${files[@]}"; do
    # echo "正在下载 $file ..."
    curl -fsSL -o "docker_gost_manager/sh/$file" "https://raw.githubusercontent.com/imjettzhang/docker_gost_manager/main/$file"
done

# 给所有脚本加执行权限
chmod +x docker_gost_manager/sh/*.sh

# 运行主程序
./docker_gost_manager/sh/gost_docker_manager.sh
