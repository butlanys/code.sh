# 开发环境部署脚本 (`code.sh`)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

一个用于在 Debian 和 Ubuntu 系统上快速部署常用开发环境和工具的 Bash 脚本。它支持交互式菜单选择和非交互式命令行参数执行。

**脚本界面语言：中文**

## 主要功能

*   **操作系统支持:** 专为 Debian 和 Ubuntu 系统设计。
*   **双模式运行:**
    *   **交互式菜单:** 无参数运行时，提供清晰的数字菜单供用户选择安装项。
    *   **命令行参数:** 支持通过命令行参数指定安装项，方便自动化和脚本化部署。
*   **广泛的工具支持:** 可安装包括：
    *   基础软件包 (curl, wget, vim, git, htop 等)
    *   版本控制: Git
    *   编译环境: C/C++ (build-essential, cmake, gdb)
    *   脚本语言: Python 3 (apt 安装 / **从源码编译指定版本**), Ruby (apt), PHP (apt, Ubuntu 可选 PPA)
    *   编译语言: Go (apt), Java (Microsoft OpenJDK 21), Rust (rustup)
    *   Web 开发: Node.js (通过 NodeSource 安装 LTS/最新版), PHP
    *   容器化: Docker CE (官方源), Docker Compose
    *   版本管理器: nvm (Node Version Manager)
*   **灵活的 Python 安装:** 支持通过 apt 安装系统稳定版，或**从 Python 官网获取版本列表并编译安装指定版本**。
*   **自动化友好:** 命令行模式允许在脚本或自动化流程中集成。

## 系统要求

*   **操作系统:** Debian 或 Ubuntu (已在 Debian 12 和 Ubuntu 22.04 上测试)
*   **权限:** 需要 `root` 或 `sudo` 权限来安装软件包和修改系统配置。
*   **网络:** 需要互联网连接以下载软件包、源码和安装脚本。
*   **基础工具:** `curl` 或 `wget` (脚本会尝试安装基础包，但如果连这些都没有可能无法开始)。

## 使用方法

### 1. 获取脚本

**选项 A: 使用 Git 克隆仓库 (推荐)**

```bash
git clone https://github.com/butlanys/code.sh.git
cd code.sh
```

选项 B: 直接下载脚本
```bash
使用 curl:

curl -LO https://raw.githubusercontent.com/butlanys/code.sh/main/code.sh
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END
```
或者使用 wget:
```bash
wget https://raw.githubusercontent.com/butlanys/code.sh/main/code.sh
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END
2. 添加执行权限
chmod +x code.sh
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END
3. 运行脚本
```
重要: 必须使用 sudo 或以 root 用户身份运行。

方式一：交互式菜单模式

直接运行脚本，不带任何参数：
```bash
sudo ./code.sh
```
脚本将显示一个带编号的菜单，您可以输入数字（单个或多个，用空格或逗号分隔）来选择要安装的工具。每次选择执行后，会提示按 Enter 继续或输入 'q' 退出。

方式二：非交互式命令行模式

通过添加命令行参数来指定要安装的内容，脚本将跳过菜单直接执行。

可用参数:

--basic-packages: 安装基础软件包

--git: 安装 Git

--c-cpp: 安装 C/C++ 开发工具

--python <version|apt>: 安装 Python。

apt: 使用 apt 安装系统默认版本。

<version>: 指定具体版本号 (如 3.11.9) 进行源码编译。

--go <apt>: 安装 Go (目前仅支持 apt 版本)。

--java: 安装 Java (Microsoft OpenJDK 21)。

--node <lts|latest|ver>: 安装 Node.js。

lts: 安装最新的 LTS 版本。

latest: 安装最新的 Current 版本。

<ver>: 指定主版本号 (如 20) 安装该系列的最新版。

--rust: 安装 Rust (通过 rustup)。

--ruby <apt>: 安装 Ruby (目前仅支持 apt 版本)。

--php: 安装 PHP (Ubuntu 默认尝试 Ondrej PPA)。

--no-ppa: (与 --php 结合使用) 强制不在 Ubuntu 上添加 Ondrej PPA。

--docker: 安装 Docker CE。

--nvm: 安装 nvm (Node Version Manager)。

--all: 尝试安装所有支持的工具 (使用推荐的默认设置，如 Python 用 apt, Node 用 lts)。

--help: 显示帮助信息并退出。

命令行示例:
```bash
# 安装 Git 和 Docker
sudo ./code.sh --git --docker

# 安装系统默认 Python 和 LTS 版 Node.js
sudo ./code.sh --python apt --node lts

# 从源码编译安装 Python 3.12.4 并安装 Rust
sudo ./code.sh --python 3.12.4 --rust

# 安装所有工具，但在 Ubuntu 上不使用 PHP PPA
sudo ./code.sh --all --no-ppa
IGNORE_WHEN_COPYING_START
content_copy
download
Use code with caution.
Bash
IGNORE_WHEN_COPYING_END
```
支持的工具和环境列表

[0] 基础软件包: curl, wget, vim, htop, git, unzip, net-tools, ca-certificates, gnupg, lsb-release, software-properties-common, apt-transport-https

[1] Git: 版本控制系统。

[2] C/C++: build-essential, gdb, make, cmake。

[3] Python 3:

通过 apt 安装系统稳定版。

从源码编译安装用户选择的特定版本 (例如 3.11.9)。

提供 pyenv 作为版本管理器的建议。

[4] Go (Golang): 通过 apt 安装 (版本可能较旧)，提供手动安装最新版的建议。

[5] Java: Microsoft OpenJDK 21 (通过官方 apt 源)。

[6] Node.js: 通过 NodeSource 安装指定的 LTS 或最新版系列。

[7] Rust: 通过官方 rustup 安装脚本安装。

[8] Ruby: 通过 apt 安装 (版本可能较旧)，提供 rbenv/rvm 作为版本管理器的建议。

[9] PHP: 通过 apt 安装，在 Ubuntu 上可选择添加 Ondrej PPA 获取更新版本。

[10] Docker CE: 安装 Docker 引擎、CLI、containerd、Buildx 和 Compose 插件 (来自 Docker 官方 apt 源)。

[11] nvm: 安装 Node Version Manager，用于管理多个 Node.js 版本。

重要提示

权限: 再次强调，运行此脚本需要 sudo 或 root 权限。

# Python 源码编译:

此过程会安装大量编译依赖 (-dev 包)。

编译非常耗时 (5-30+ 分钟，取决于机器性能)。

使用 make altinstall 将 Python 安装到 /usr/local/bin/pythonX.Y，不会覆盖系统默认的 python3。

对于多版本管理，强烈推荐使用 pyenv。

版本管理器: 对于 Python, Go, Ruby，如果需要精确的版本控制或安装 apt 源中没有的版本，强烈建议使用对应的版本管理器 (pyenv, 手动安装 Go, rbenv/rvm)。脚本在相应选项中会提供建议。

# 环境生效:

安装 nvm 或 rustup 后，需要关闭当前终端并重新打开，或手动执行 source ~/.bashrc (或对应的 shell 配置文件) 才能使用 nvm 或 cargo/rustc 命令。

安装 Docker 后，当前用户需要重新登录或执行 newgrp docker 才能无需 sudo 运行 docker 命令。

网络: 所有安装过程都需要稳定的互联网连接。

测试: 建议首次在测试环境或虚拟机中运行此脚本。

幂等性: 脚本没有严格实现幂等性。重复运行安装同一个工具通常没问题 (apt 会处理)，但重复执行源码编译或添加 PPA/源可能会产生非预期结果。

# 贡献

欢迎通过提交 Issues 或 Pull Requests 来改进此脚本。

# 许可证

本项目采用 MIT 许可证。
