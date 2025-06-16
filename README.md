# Docker Gost 转发管理脚本

一个基于 Docker 的 Gost 端口转发管理工具，提供友好的交互式界面来管理网络转发规则。

## 功能特性

- 🚀 **一键安装**: 自动安装 Docker 和 Gost
- 🌐 **多协议支持**: 支持 TCP、UDP 和双协议转发
- 📍 **多地址格式**: 支持 IPv4、IPv6 和域名目标地址
- 🔥 **防火墙管理**: 自动配置 UFW 防火墙规则
- 📊 **规则管理**: 轻松创建、查看和删除转发规则
- 📝 **实时日志**: 提供容器日志实时查看功能
- 🔄 **容器管理**: 支持重启和卸载操作
- 🔒 **地址验证**: 智能验证 IPv4、IPv6 和域名格式
- 🇨🇳 **中国大陆优化**: 自动检测网络环境，使用国内镜像源加速

## 快速开始

### 一键安装并运行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/imjettzhang/docker_gost_manager/main/quickstart.sh)
```


## 系统要求

- **操作系统**: Linux (Ubuntu, Debian, CentOS, RHEL 等)
- **权限**: 需要 root 权限或 sudo 访问
- **网络**: 需要访问 GitHub 和 Docker Hub
- **依赖**: curl, docker
