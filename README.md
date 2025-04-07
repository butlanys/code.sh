# 🚀 开发环境一键部署脚本 (Debian/Ubuntu)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

一个用于在 Debian/Ubuntu 系统上快速、轻松地安装常用开发环境和工具的 Bash 脚本。支持通过命令行参数进行非交互式批量安装，或通过交互式菜单引导用户进行选择性安装。

**项目地址:** [https://github.com/butlanys/code.sh](https://github.com/butlanys/code.sh)

---

## ✨ 功能特性

*   ✅ **多种工具支持**: 一键安装 Git, C/C++, Python (apt/源码编译), Go (apt/官网最新版), Java (OpenJDK), Node.js (LTS/最新), Rust (rustup), Ruby (apt), PHP (可选 PPA), Docker CE, nvm 等。
*   🚀 **命令行模式**: 通过参数指定需要安装的工具，实现快速、自动化的环境部署。非常适合在自动化脚本或新服务器初始化时使用。
*   💡 **交互式菜单**: 无需记忆复杂参数，通过简单直观的菜单选择需要安装的工具，对新手友好。
*   🎨 **彩色输出**: 在交互模式下提供彩色的日志和提示信息，增强可读性和用户体验。 (命令行模式下自动禁用颜色)。
*    mirrors: **镜像源更换**: 内置选项，可快速将 APT 源更换为中国大陆镜像或恢复为国际官方源，解决部分地区下载速度慢的问题 (使用 [linuxmirrors.cn](https://linuxmirrors.cn/) 提供的脚本)。
*   🐍 **灵活的 Python 安装**: 可选择使用 `apt` 安装系统稳定版，或从 Python 官网源码编译安装指定版本。
*   🐹 **灵活的 Go 安装**: 可选择使用 `apt` 安装系统版本，或自动从 Go 官网下载并安装最新的稳定版二进制包。
*   ⚙️ **配置与提示**: 自动处理部分环境配置 (如 Docker 用户组添加, Go PATH 设置)，并提供清晰的后续操作提示 (如 nvm/Rust 环境加载)。

---

## 📋 环境要求

*   **操作系统**: Debian 或 Ubuntu (基于 `apt` 包管理器)。
*   **权限**: 需要 `sudo` 或 `root` 权限运行脚本 (因为需要安装软件包和修改系统配置)。
*   **基础命令**:
    *   `bash`: 脚本解释器。
    *   `curl` 或 `wget`: 用于下载外部脚本和软件包。
    *   `git`: 如果你选择通过 `git clone` 获取脚本。
    *   `grep`, `sed`, `awk`, `tar`: 用于 Go 官网版本安装。
    *   `build-essential` 等: 如果选择从源码编译 Python。

---

## 🚀 使用方法

**1. 获取脚本**
*   **通过 curl:**
    ```bash
    curl -O https://raw.githubusercontent.com/butlanys/code.sh/main/code.sh
    ```
*   **直接下载:**
    访问 [https://github.com/butlanys/code.sh](https://github.com/butlanys/code.sh) 并下载 `code.sh` 文件。

**2. 添加执行权限**

```bash
chmod +x code.sh
```

**3. 运行脚本**

**重要提示:** 脚本需要 `sudo` 权限！

*   **交互式菜单模式 (推荐新手):**
    ```bash
    sudo ./code.sh
    ```
    脚本将以彩色界面启动，根据菜单提示选择要安装的工具。

*   **命令行参数模式 (适合自动化):**
    ```bash
    sudo ./code.sh [选项...]
    ```
    **示例:**
    ```bash
    # 安装 Git, 从源码编译 Python 3.11.9, 安装 Node.js LTS 版, 从官网安装 Go 最新版
    sudo ./code.sh --git --python 3.11.9 --node lts --go manual

    # 更换为中国大陆 APT 源，然后安装基础包和 Docker
    sudo ./code.sh --change-source cn --basic-packages --docker

    # 安装所有常用工具 (使用默认推荐设置)，但 PHP 不使用 PPA
    sudo ./code.sh --all --no-ppa

    # 查看帮助信息
    sudo ./code.sh --help
    ```

---

## 🛠️ 可用选项 (命令行)

| 选项                      | 参数                     | 描述                                                                 |
| :------------------------ | :----------------------- | :------------------------------------------------------------------- |
| `--basic-packages`        | (无)                     | 安装基础软件包 (curl, wget, git, vim, etc.)                          |
| `--git`                   | (无)                     | 安装 Git 版本控制系统                                                |
| `--c-cpp`                 | (无)                     | 安装 C/C++ 开发工具 (build-essential, cmake, gdb)                    |
| `--python`                | `<version>` 或 `apt`     | 安装 Python ('apt' 或指定版本如 '3.11.9' 进行编译)                   |
| `--go`                    | `apt` 或 `manual/latest` | 安装 Go ('apt' 或从官网安装最新稳定版)                               |
| `--java`                  | (无)                     | 安装 Java (Microsoft OpenJDK)                                        |
| `--node`                  | `lts`, `latest`, `<ver>` | 安装 Node.js (LTS, 最新版, 或指定主版本号如 '20')                    |
| `--rust`                  | (无)                     | 安装 Rust (通过官方 rustup)                                          |
| `--ruby`                  | `apt`                    | 安装 Ruby (仅支持 'apt' 安装系统版本)                                |
| `--php`                   | (无)                     | 安装 PHP 及常用扩展 (Ubuntu 默认尝试 PPA)                            |
| `--no-ppa`                | (无)                     | 与 `--php` 结合，强制不在 Ubuntu 上添加 Ondrej PPA                   |
| `--docker`                | (无)                     | 安装 Docker CE (社区版)                                              |
| `--nvm`                   | (无)                     | 安装 nvm (Node Version Manager)                                      |
| `--change-source`         | `cn` 或 `abroad`         | 更换 APT 源 (cn: 中国大陆镜像, abroad: 国际官方源)                   |
| `--all`                   | (无)                     | 安装除换源外的所有常用工具 (使用默认推荐设置)                        |
| `--help`                  | (无)                     | 显示帮助信息并退出                                                   |

---

## ⚠️ 重要注意事项

*   **权限:** 再次强调，脚本必须以 `sudo` 或 `root` 权限运行。
*   **Python 编译:** 从源码编译 Python 会安装编译依赖 (`build-essential` 等)，且耗时较长。
*   **Go 官网安装:** 从官网安装 Go 依赖 `curl`/`wget`, `grep`, `sed`, `awk`, `tar`。其解析下载链接和校验和的逻辑依赖于 Go 官网页面结构，若官网改版可能失效。
*   **更换 APT 源:**
    *   此功能使用外部脚本 (`linuxmirrors.cn`)，请确保您信任该脚本来源。
    *   更换源会修改系统核心配置 (`/etc/apt/sources.list`)，请谨慎操作。
    *   换源后，脚本**不会**自动执行 `apt update`，请在脚本执行完毕后根据提示手动运行 `sudo apt update && sudo apt upgrade`。
*   **用户级工具:** `nvm` 和 `rustup` 会安装到执行 `sudo` 命令的用户的家目录下 (通常是你的普通用户，而不是 root)。
*   **后续操作:**
    *   **Docker:** 安装后，需要重新登录或运行 `newgrp docker` 命令，才能让当前用户免 `sudo` 使用 `docker` 命令。
    *   **nvm/Rust:** 安装后，需要关闭当前终端并重新打开，或手动执行 `source ~/.bashrc` (或 `.zshrc` 等对应文件) 来加载环境变量。
    *   **Go (手动安装):** 安装后，需要重新登录或运行 `source /etc/profile.d/go.sh` 来使 `go` 命令在 PATH 中生效。

---

## 🤝 贡献

欢迎通过提交 Pull Requests 或报告 Issues 来改进此脚本！

---

## 📄 许可证

本项目使用 [MIT](LICENSE) 许可证。

爱来自[Gemini 2.5 Pro Preview 03-25](https://aistudio.google.com/prompts/)
