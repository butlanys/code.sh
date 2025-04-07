#!/bin/bash

# ==============================================================================
# 开发环境部署脚本 (Debian/Ubuntu - v6.1 - 修正 local 错误)
# ==============================================================================
#
# 功能: 通过命令行参数或交互式菜单安装开发工具。
#
# 命令行用法示例:
#   sudo ./script.sh --git --python 3.11.9 --node lts --docker
#   sudo ./script.sh --all --no-ppa
#   sudo ./script.sh --help
#
# 交互式用法:
#   sudo ./script.sh (不带参数)
#
# 注意: 需要 root 权限。源码编译 Python 需要较长时间和依赖。
# ==============================================================================

# --- 安全设置 ---
set -e
set -o pipefail
# set -u # 暂时注释掉

# --- 配置 ---
DEFAULT_JAVA_VERSION="21"
DEFAULT_NODE_LTS_MAJOR_VERSION="20"
DEFAULT_NODE_LATEST_MAJOR_VERSION="22"
NVM_VERSION="0.39.7"

# --- 全局变量 ---
CURRENT_USER=${SUDO_USER:-$(whoami)}
CURRENT_HOME=$(eval echo ~$CURRENT_USER)
ID=""
VERSION_ID=""
declare -A MENU_OPTIONS
declare -A INSTALL_FUNCTIONS
declare -A ARGS_INSTALL_CHOICES # 存储命令行参数选择 {tool_name: version_or_true}
NON_INTERACTIVE=false # 标记是否为非交互模式
PHP_NO_PPA=false      # 标记 PHP 是否禁用 PPA
NVM_INSTALLED_FLAG=false
PYTHON_COMPILED_FLAG=false
RUST_INSTALLED_FLAG=false
DOCKER_INSTALLED_FLAG=false

# --- 助手函数 ---
log_info() { echo "[信息] $1"; }
log_error() { echo "[错误] $1" >&2; exit 1; }
log_warning() { echo "[警告] $1" >&2; }

show_help() {
    echo "用法: $0 [选项...]"
    echo ""
    echo "选项:"
    echo "  --basic-packages          安装基础软件包"
    echo "  --git                     安装 Git"
    echo "  --c-cpp                   安装 C/C++ 开发工具"
    echo "  --python <version|apt>    安装 Python ('apt' 或具体版本如 '3.11.9' 进行编译)"
    echo "  --go <apt>                安装 Go (apt 版本)"
    echo "  --java                    安装 Java (Microsoft OpenJDK ${DEFAULT_JAVA_VERSION})"
    echo "  --node <lts|latest|ver>   安装 Node.js ('lts', 'latest', 或主版本如 '20')"
    echo "  --rust                    安装 Rust (rustup)"
    echo "  --ruby <apt>              安装 Ruby (apt 版本)"
    echo "  --php                     安装 PHP (Ubuntu 默认尝试 Ondrej PPA)"
    echo "  --no-ppa                  与 --php 结合使用，强制不添加 PPA (Ubuntu)"
    echo "  --docker                  安装 Docker CE"
    echo "  --nvm                     安装 nvm (Node Version Manager)"
    echo "  --all                     安装所有常用工具 (使用推荐默认设置)"
    echo "  --help                    显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  sudo $0 --git --python 3.11.9 --node lts"
    echo "  sudo $0 --all --no-ppa"
    echo "  sudo $0 (无参数将进入交互式菜单)"
    exit 0
}

show_version_manager_info() {
    local lang=$1; clear; echo "----------------------------------"; log_warning "您选择了不安装 $lang 的 apt 版本或需要特定版本。"; log_info "对于 $lang 的多版本管理或安装特定版本，强烈建议使用专门的版本管理器："; case $lang in Python) echo "  - pyenv: 强大的 Python 版本管理器。"; echo "    安装指南: https://github.com/pyenv/pyenv#installation"; echo "  - deadsnakes PPA (Ubuntu): 提供较新的 Python 版本。"; echo "    查找方法: sudo add-apt-repository ppa:deadsnakes/ppa && sudo apt update"; ;; Go) echo "  - 手动安装: 从 Go 官网下载二进制包进行安装。"; echo "    下载地址: https://go.dev/dl/"; echo "  - gvm (Go Version Manager): 类似于 nvm/rbenv。"; echo "    安装指南: https://github.com/moovweb/gvm"; ;; Ruby) echo "  - rbenv: 流行的 Ruby 版本管理器。"; echo "    安装指南: https://github.com/rbenv/rbenv#installation"; echo "  - RVM (Ruby Version Manager): 另一个功能丰富的版本管理器。"; echo "    安装指南: https://rvm.io/rvm/install"; ;; *) echo "  (无特定版本管理器推荐信息)"; ;; esac; echo "----------------------------------"; read -p "按 Enter 继续..."
}

# --- 安装函数 ---

# 0: 安装基础软件包
install_basic_packages() {
    log_info "正在安装基础软件包..."
    export DEBIAN_FRONTEND=noninteractive
    apt update || log_warning "apt update 失败，继续尝试安装..."
    apt install -y curl wget vim htop git unzip net-tools ca-certificates gnupg lsb-release software-properties-common apt-transport-https || { log_error "基础软件包安装失败。"; return 1; }
    log_info "基础软件包安装完成。"
    return 0
}

# 1: 安装 Git
install_git() {
    log_info "正在安装 Git..."
    export DEBIAN_FRONTEND=noninteractive
    apt install -y git || { log_error "Git 安装失败。"; return 1; }
    log_info "Git 安装完成。 版本: $(git --version)"
    return 0
}

# 2: 安装 C/C++ 开发工具
install_c_cpp() {
    log_info "正在安装 C/C++ 开发工具..."
    export DEBIAN_FRONTEND=noninteractive
    apt install -y build-essential gdb make cmake || { log_error "C/C++ 开发工具安装失败。"; return 1; }
    log_info "C/C++ 开发工具安装完成。"
    log_info "GCC 版本: $(gcc --version | head -n 1)"
    log_info "CMake 版本: $(cmake --version | head -n 1)"
    return 0
}

# 3: 安装 Python 3
install_python() {
    local install_type="$1"
    export DEBIAN_FRONTEND=noninteractive

    if [[ "$NON_INTERACTIVE" == true ]]; then
        if [[ -z "$install_type" ]]; then log_warning "非交互模式下未指定 Python 安装类型 (apt 或版本号)，跳过。"; return 0;
        elif [[ "$install_type" == "apt" ]]; then log_info "正在安装 Python 3 (apt)..."; apt install -y python3 python3-pip python3-venv || { log_error "Python 3 (apt) 安装失败。"; return 1; }; log_info "Python 3 (apt 版本) 安装完成。"
        elif [[ "$install_type" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then log_info "准备从源码编译 Python $install_type..."; compile_python_from_source "$install_type" || return 1
        else log_error "无效的 Python 安装类型 '$install_type'。请使用 'apt' 或 'X.Y.Z' 版本号。"; return 1; fi
    else
        clear; echo "----------------------------------"; echo " Python 3 安装选项"; echo "----------------------------------"; echo "  1) 使用 apt 安装系统默认版本 (推荐，最稳定)"; echo "  2) 从源码编译安装指定版本 (高级，耗时，需要依赖)"; echo "  3) 跳过安装 (推荐使用 pyenv 管理)"; echo "----------------------------------"; read -p "请输入选项 [1, 2, 3, 默认 1]: " python_choice; python_choice=${python_choice:-1}; case "$python_choice" in 1) log_info "正在安装 Python 3 (apt)..."; apt install -y python3 python3-pip python3-venv || { log_error "Python 3 (apt) 安装失败。"; return 1; }; log_info "Python 3 (apt 版本) 安装完成。";; 2) compile_python_from_source || return 1 ;; 3) show_version_manager_info "Python"; return 0 ;; *) log_warning "无效的选择，跳过 Python 安装。"; return 0 ;; esac
    fi
    if command -v python3 &> /dev/null && ( [[ "$install_type" == "apt" ]] || [[ "$python_choice" == "1" ]] ); then log_info "Python 版本: $(python3 --version)"; log_info "Pip 版本: $(pip3 --version)"; fi
    return 0
}

# 从源码编译 Python 的函数
compile_python_from_source() {
    local target_version="$1"
    log_info "开始从源码编译安装 Python..."; if [[ -n "$target_version" ]]; then log_info "目标版本: $target_version (来自命令行参数)"; fi; log_warning "此过程需要安装编译依赖，并可能花费较长时间。"; export DEBIAN_FRONTEND=noninteractive; log_info "正在安装 Python 编译依赖..."; local build_deps="build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget curl llvm libbz2-dev pkg-config liblzma-dev tk-dev libxml2-dev libxmlsec1-dev"; apt update || log_warning "apt update 失败..."; apt install -y $build_deps || { log_error "安装编译依赖失败。"; return 1; }; log_info "编译依赖安装完成。"
    local chosen_version=""; if [[ -n "$target_version" ]]; then chosen_version="$target_version"; log_info "检查版本 $chosen_version 是否存在..."; if ! curl --output /dev/null --silent --head --fail "https://www.python.org/ftp/python/${chosen_version}/"; then log_error "指定的 Python 版本 $chosen_version 在 python.org 上未找到或无法访问。"; return 1; fi; log_info "版本 $chosen_version 存在，继续。"; else log_info "正在从 python.org 获取可用的 Python 3 版本列表..."; local python_versions=(); local available_versions_html=""; available_versions_html=$(curl -s --connect-timeout 10 --retry 3 https://www.python.org/ftp/python/) || { log_error "无法获取 Python 版本列表。"; return 1; }; mapfile -t python_versions < <(echo "$available_versions_html" | grep -oP 'href="3\.([0-9]+)\.([0-9]+)/"' | sed 's/href="//; s/\/"//' | sort -Vur); if [[ ${#python_versions[@]} -eq 0 ]]; then log_error "未能解析出可用的 Python 3 版本。"; return 1; fi; clear; log_info "以下是检测到的最新 Python 3 稳定版本:"; local display_count=15; local options_count=0; declare -A version_map; for i in $(seq 0 $((${#python_versions[@]} - 1))); do if [[ $options_count -lt $display_count ]]; then printf "  %2d) %s\n" "$((options_count + 1))" "${python_versions[$i]}"; version_map[$((options_count + 1))]=${python_versions[$i]}; options_count=$((options_count + 1)); else break; fi; done; echo "----------------------------------"; echo "  0) 取消编译安装"; echo "----------------------------------"; while true; do read -p "请选择要编译安装的版本序号 (输入 0 取消): " version_choice; if [[ "$version_choice" == "0" ]]; then log_info "用户取消编译安装。"; return 0; elif [[ "$version_choice" =~ ^[0-9]+$ ]] && [[ -v version_map[$version_choice] ]]; then chosen_version=${version_map[$version_choice]}; log_info "您选择了版本: $chosen_version"; break; else log_warning "无效的选择，请输入列表中的序号。"; fi; done; fi
    local source_filename="Python-${chosen_version}.tar.xz"; local source_url="https://www.python.org/ftp/python/${chosen_version}/${source_filename}"; local download_dir="/tmp/python_build_$$"; mkdir -p "$download_dir"; local source_path="${download_dir}/${source_filename}"; local source_dir="${download_dir}/Python-${chosen_version}"; log_info "正在下载 Python ${chosen_version} 源码从 $source_url ..."; wget --quiet --show-progress --progress=bar:force:noscroll --connect-timeout=15 --tries=3 -P "$download_dir" "$source_url" || { log_error "下载源码失败 (URL: $source_url)。"; rm -rf "$download_dir"; return 1; }; log_info "源码下载完成: $source_path"
    log_info "正在解压源码..."; rm -rf "$source_dir"; tar -xf "$source_path" -C "$download_dir" || { log_error "解压源码失败。"; rm -rf "$download_dir"; return 1; }; log_info "源码解压到: $source_dir"
    log_info "进入源码目录并开始配置..."; cd "$source_dir"; log_info "运行 ./configure --enable-optimizations --with-ensurepip=install ..."; ./configure --enable-optimizations --with-ensurepip=install LDFLAGS="-Wl,-rpath=/usr/local/lib" || { log_error "配置 (configure) 失败。"; cd /; rm -rf "$download_dir"; return 1; }; log_info "配置完成。开始编译 (这可能需要很长时间)..."; make -j$(nproc) || { log_error "编译 (make) 失败。"; cd /; rm -rf "$download_dir"; return 1; }; log_info "编译完成。开始安装 (使用 altinstall)..."; make altinstall || { log_error "安装 (make altinstall) 失败。"; cd /; rm -rf "$download_dir"; return 1; }; log_info "Python ${chosen_version} 安装完成！"
    log_info "正在清理临时文件..."; cd /; rm -rf "$download_dir"; log_info "清理完成。"
    local installed_python_executable="/usr/local/bin/python${chosen_version%.*}"; log_info "您可以通过命令 '$installed_python_executable' 来使用新安装的 Python 版本。"; log_info "例如: $installed_python_executable --version"; log_info "对应的 pip 命令通常是: ${installed_python_executable} -m pip"; log_warning "请注意，系统默认的 'python3' 命令仍然指向 apt 安装的版本。"; PYTHON_COMPILED_FLAG=true
    return 0
}

# 4: 安装 Go (Golang)
install_go() {
    local install_type="$1"; export DEBIAN_FRONTEND=noninteractive; if [[ "$NON_INTERACTIVE" == true ]]; then if [[ "$install_type" == "apt" ]]; then log_info "正在安装 Go (apt)..."; apt install -y golang-go || { log_error "Go 安装失败。"; return 1; }; log_info "Go (apt 版本) 安装完成。"; else log_warning "非交互模式下 Go 只支持 'apt' 参数，跳过。"; return 0; fi; else read -p "是否安装 apt 源提供的 Go 版本 (golang-go, 可能不是最新版)? (Y/n): " install_apt_go; install_apt_go=${install_apt_go:-Y}; if [[ "$install_apt_go" =~ ^[Yy]$ ]]; then log_info "正在安装 Go (apt)..."; apt install -y golang-go || { log_error "Go 安装失败。"; return 1; }; log_info "Go (apt 版本) 安装完成。"; else show_version_manager_info "Go"; return 0; fi; fi; if command -v go &> /dev/null; then log_info "Go 版本: $(go version)"; else log_warning "Go 命令未在当前 PATH 找到..."; fi; return 0
}

# 5: 安装 Java
install_java() {
    log_info "正在安装 Java (Microsoft OpenJDK ${DEFAULT_JAVA_VERSION})..."; export DEBIAN_FRONTEND=noninteractive; apt install -y wget lsb-release ca-certificates || { log_error "安装 Java 依赖失败。"; return 1; }; log_info "正在添加 Microsoft OpenJDK 仓库..."; OS_VERSION_NUM=$(lsb_release -rs); if [[ -z "$OS_VERSION_NUM" ]]; then log_error "无法获取系统版本号 (lsb_release -rs)。"; fi; MS_REPO_DEB="packages-microsoft-prod.deb"; MS_REPO_URL="https://packages.microsoft.com/config/${ID}/${OS_VERSION_NUM}/packages-microsoft-prod.deb"; log_info "正在下载: $MS_REPO_URL"; wget --timeout=30 --tries=3 "$MS_REPO_URL" -O "$MS_REPO_DEB" || { log_warning "下载 Microsoft 仓库配置失败 (URL: $MS_REPO_URL)。"; rm -f "$MS_REPO_DEB"; return 1; }; if [[ -f "$MS_REPO_DEB" ]]; then dpkg -i "$MS_REPO_DEB"; rm "$MS_REPO_DEB"; log_info "正在更新 apt 软件包列表..."; apt update || log_warning "更新 apt 列表时出错..."; MS_OPENJDK_PKG="msopenjdk-${DEFAULT_JAVA_VERSION}"; log_info "正在安装 ${MS_OPENJDK_PKG}..."; if apt install -y "$MS_OPENJDK_PKG"; then log_info "Java 安装完成。"; log_info "Java 版本: $(java -version 2>&1 | head -n 1)"; return 0; else log_error "安装 ${MS_OPENJDK_PKG} 失败。"; return 1; fi; else log_error "未能下载和配置 Microsoft 仓库。"; return 1; fi
}

# 6: 安装 Node.js
install_nodejs() {
    local version_spec="$1"; log_info "正在安装 Node.js (及 npm) via NodeSource..."; if [[ "$NON_INTERACTIVE" == false ]]; then log_info "提示: 如需管理多个 Node.js 版本，请选择菜单中的 '安装 nvm' 选项。"; fi; export DEBIAN_FRONTEND=noninteractive; apt install -y curl || { log_error "安装 Node.js 依赖 curl 失败。"; return 1; }; local node_install_version=""; if [[ "$NON_INTERACTIVE" == true ]]; then if [[ "$version_spec" == "lts" ]]; then node_install_version="${DEFAULT_NODE_LTS_MAJOR_VERSION}"; elif [[ "$version_spec" == "latest" ]]; then node_install_version="${DEFAULT_NODE_LATEST_MAJOR_VERSION}"; elif [[ "$version_spec" =~ ^[0-9]+$ ]]; then node_install_version="$version_spec"; elif [[ -z "$version_spec" ]]; then log_warning "非交互模式下未指定 Node.js 版本，默认使用 LTS。"; node_install_version="${DEFAULT_NODE_LTS_MAJOR_VERSION}"; else log_error "无效的 Node.js 版本参数 '$version_spec'。"; return 1; fi; else echo "----------------------------------"; echo "请选择要安装的 Node.js 版本 (通过 NodeSource):"; echo "  [1] LTS (推荐, ${DEFAULT_NODE_LTS_MAJOR_VERSION}.x)"; echo "  [2] 最新版 (Current, ${DEFAULT_NODE_LATEST_MAJOR_VERSION}.x)"; echo "----------------------------------"; read -p "请输入选项 [1 或 2, 默认 1]: " NODE_CHOICE; NODE_CHOICE=${NODE_CHOICE:-1}; case "$NODE_CHOICE" in 2) node_install_version="${DEFAULT_NODE_LATEST_MAJOR_VERSION}";; 1|*) node_install_version="${DEFAULT_NODE_LTS_MAJOR_VERSION}";; esac; fi; local node_setup_suffix="${node_install_version}.x"; log_info "选择安装 Node.js v${node_setup_suffix}"; log_info "正在设置 NodeSource 仓库..."; NODESOURCE_URL="https://deb.nodesource.com/setup_${node_setup_suffix}"; curl -fsSL "$NODESOURCE_URL" | bash - || { log_error "设置 NodeSource 仓库失败。"; return 1; }; log_info "正在安装 Node.js..."; apt install -y nodejs || { log_error "Node.js 安装失败。"; return 1; }; log_info "Node.js (NodeSource 版本) 安装完成。"; log_info "Node 版本: $(node -v)"; log_info "npm 版本: $(npm -v)"; return 0
}

# 7: 安装 Rust
install_rust() {
    log_info "正在安装 Rust (通过官方 rustup)..."; log_warning "Rustup 会将 Rust 安装在用户 '$CURRENT_USER' 的主目录 ($CURRENT_HOME/.cargo) 下。"; log_warning "安装完成后，您需要运行 'source \$HOME/.cargo/env' 或重新登录/打开新终端。"; export DEBIAN_FRONTEND=noninteractive; apt install -y curl || { log_error "安装 Rust 依赖 curl 失败。"; return 1; }; RUSTUP_SCRIPT=$(mktemp); curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$RUSTUP_SCRIPT" || { log_error "下载 rustup 脚本失败。"; rm -f "$RUSTUP_SCRIPT"; return 1; }; log_info "正在以用户 '$CURRENT_USER' 的身份运行 rustup 安装脚本 (非交互式)..."; chown $CURRENT_USER "$RUSTUP_SCRIPT"; sudo -u "$CURRENT_USER" sh "$RUSTUP_SCRIPT" -y || { log_warning "Rustup 安装脚本执行失败。"; rm -f "$RUSTUP_SCRIPT"; return 1; }; rm "$RUSTUP_SCRIPT"; BASHRC_PATH="$CURRENT_HOME/.bashrc"; CARGO_ENV_LINE='source "$HOME/.cargo/env"'; if [[ -f "$BASHRC_PATH" ]]; then if ! grep -qF -- "$CARGO_ENV_LINE" "$BASHRC_PATH"; then log_info "尝试将 'source \$HOME/.cargo/env' 添加到 $BASHRC_PATH"; echo "$CARGO_ENV_LINE" | sudo -u "$CURRENT_USER" tee -a "$BASHRC_PATH" > /dev/null; log_info "已添加。请运行 'source $BASHRC_PATH' 或重新登录以使 Rust 生效。"; fi; else log_warning "未找到 $BASHRC_PATH 文件。请手动添加。"; fi; log_info "Rust 安装完成 (需要更新环境才能使用)。"; RUST_INSTALLED_FLAG=true; return 0
}

# 8: 安装 Ruby
install_ruby() {
    local install_type="$1"; export DEBIAN_FRONTEND=noninteractive; if [[ "$NON_INTERACTIVE" == true ]]; then if [[ "$install_type" == "apt" ]]; then log_info "正在安装 Ruby (apt)..."; apt install -y ruby-full ruby-dev || { log_error "Ruby 安装失败。"; return 1; }; log_info "Ruby (apt 版本) 安装完成。"; else log_warning "非交互模式下 Ruby 只支持 'apt' 参数，跳过。"; return 0; fi; else read -p "是否安装 apt 源提供的 Ruby 版本 (ruby-full, 可能不是最新版)? (Y/n): " install_apt_ruby; install_apt_ruby=${install_apt_ruby:-Y}; if [[ "$install_apt_ruby" =~ ^[Yy]$ ]]; then log_info "正在安装 Ruby (apt)..."; apt install -y ruby-full ruby-dev || { log_error "Ruby 安装失败。"; return 1; }; log_info "Ruby (apt 版本) 安装完成。"; else show_version_manager_info "Ruby"; return 0; fi; fi; log_info "Ruby 版本: $(ruby --version)"; return 0
}

# 9: 安装 PHP
install_php() {
    log_info "正在安装 PHP (及常用扩展)..."; export DEBIAN_FRONTEND=noninteractive; local add_ondrej_ppa=false; if [[ "$ID" == "ubuntu" ]]; then if [[ "$NON_INTERACTIVE" == true ]]; then if [[ "$PHP_NO_PPA" == false ]]; then add_ondrej_ppa=true; log_info "非交互模式，尝试添加 Ondrej PPA (使用 --no-ppa 禁用)..."; else log_info "非交互模式，根据 --no-ppa 参数，不添加 Ondrej PPA。"; fi; else read -p "检测到 Ubuntu 系统，是否尝试添加 Ondrej PPA 以获取较新 PHP 版本? (y/N): " ppa_choice; if [[ "$ppa_choice" =~ ^[Yy]$ ]]; then add_ondrej_ppa=true; fi; fi; fi; if [[ "$add_ondrej_ppa" == true ]]; then log_info "正在添加 ppa:ondrej/php..."; apt install -y software-properties-common || { log_error "安装 PPA 依赖失败。"; return 1; }; add-apt-repository -y ppa:ondrej/php || log_warning "添加 Ondrej PPA 失败..."; apt update || log_warning "添加 PPA 后更新软件包列表失败。"; fi; log_info "正在安装 PHP 及常用扩展..."; if apt install -y php php-cli php-common php-dev php-mbstring php-xml php-curl php-zip php-mysql; then log_info "PHP 安装完成。"; log_info "PHP 版本: $(php --version | head -n 1)"; return 0; else log_error "安装 PHP 失败。"; return 1; fi
}

# 10: 安装 Docker CE
install_docker() {
    log_info "正在安装 Docker CE..."; export DEBIAN_FRONTEND=noninteractive; log_info "安装 Docker 依赖..."; apt install -y ca-certificates curl gnupg lsb-release || { log_error "安装 Docker 依赖失败。"; return 1; }; log_info "添加 Docker GPG 密钥..."; install -m 0755 -d /etc/apt/keyrings; curl -fsSL https://download.docker.com/linux/${ID}/gpg -o /etc/apt/keyrings/docker.asc; chmod a+r /etc/apt/keyrings/docker.asc; log_info "添加 Docker apt 仓库..."; echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null; log_info "更新 apt 列表并安装 Docker Engine..."; apt update || log_warning "更新 apt 列表失败..."; apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { log_error "安装 Docker Engine 失败。"; return 1; }; log_info "将用户 '$CURRENT_USER' 添加到 'docker' 组..."; usermod -aG docker "$CURRENT_USER" || log_warning "将用户添加到 docker 组失败..."; log_info "Docker CE 安装完成。"; log_warning "为了使 docker 组权限生效，请重新登录或运行 'newgrp docker'。"; log_info "Docker 版本: $(docker --version)"; DOCKER_INSTALLED_FLAG=true; return 0
}

# 11: 安装 nvm
install_nvm() {
    log_info "正在安装 nvm for user '$CURRENT_USER'..."; export DEBIAN_FRONTEND=noninteractive; if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then log_info "安装 nvm 需要 curl 或 wget..."; apt install -y curl || { log_error "安装 curl 失败。"; return 1; }; fi; log_info "正在下载并执行 nvm v${NVM_VERSION} 安装脚本..."; local install_cmd=""; if command -v curl &> /dev/null; then install_cmd="curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash"; elif command -v wget &> /dev/null; then install_cmd="wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash"; else log_error "未找到 curl 或 wget。"; return 1; fi; if sudo -u "$CURRENT_USER" bash -c "$install_cmd"; then log_info "nvm 安装脚本执行成功。"; log_warning "重要：您需要关闭当前终端并重新打开，或运行 'source $CURRENT_HOME/.bashrc' (或 .zshrc 等) 来加载 nvm。"; log_info "nvm 用法示例:"; echo "  nvm install node"; echo "  nvm install --lts"; echo "  nvm install <版本号>"; echo "  nvm use <版本号>"; echo "  nvm ls"; echo "  nvm ls-remote"; NVM_INSTALLED_FLAG=true; return 0; else log_error "nvm 安装脚本执行失败。"; return 1; fi
}

# --- 参数解析 ---
parse_arguments() {
    if [[ $# -gt 0 ]]; then
        NON_INTERACTIVE=true
        log_info "检测到命令行参数，进入非交互模式..."
    else
        return
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --basic-packages) ARGS_INSTALL_CHOICES["basic"]="true"; shift ;;
            --git) ARGS_INSTALL_CHOICES["git"]="true"; shift ;;
            --c-cpp) ARGS_INSTALL_CHOICES["c_cpp"]="true"; shift ;;
            --python) if [[ -z "$2" || "$2" == --* ]]; then log_error "--python 需要一个参数 ('apt' 或版本号)"; fi; ARGS_INSTALL_CHOICES["python"]="$2"; shift 2 ;;
            --go) if [[ -z "$2" || "$2" == --* || "$2" != "apt" ]]; then log_error "--go 需要 'apt' 参数"; fi; ARGS_INSTALL_CHOICES["go"]="$2"; shift 2 ;;
            --java) ARGS_INSTALL_CHOICES["java"]="true"; shift ;;
            --node) if [[ -z "$2" || "$2" == --* ]]; then log_error "--node 需要一个参数 ('lts', 'latest', 或主版本号)"; fi; ARGS_INSTALL_CHOICES["node"]="$2"; shift 2 ;;
            --rust) ARGS_INSTALL_CHOICES["rust"]="true"; shift ;;
            --ruby) if [[ -z "$2" || "$2" == --* || "$2" != "apt" ]]; then log_error "--ruby 需要 'apt' 参数"; fi; ARGS_INSTALL_CHOICES["ruby"]="$2"; shift 2 ;;
            --php) ARGS_INSTALL_CHOICES["php"]="true"; shift ;;
            --no-ppa) PHP_NO_PPA=true; shift ;;
            --docker) ARGS_INSTALL_CHOICES["docker"]="true"; shift ;;
            --nvm) ARGS_INSTALL_CHOICES["nvm"]="true"; shift ;;
            --all) log_info "选择安装所有工具 (使用默认推荐设置)..."; ARGS_INSTALL_CHOICES["basic"]="true"; ARGS_INSTALL_CHOICES["git"]="true"; ARGS_INSTALL_CHOICES["c_cpp"]="true"; ARGS_INSTALL_CHOICES["python"]="apt"; ARGS_INSTALL_CHOICES["go"]="apt"; ARGS_INSTALL_CHOICES["java"]="true"; ARGS_INSTALL_CHOICES["node"]="lts"; ARGS_INSTALL_CHOICES["rust"]="true"; ARGS_INSTALL_CHOICES["ruby"]="apt"; ARGS_INSTALL_CHOICES["php"]="true"; ARGS_INSTALL_CHOICES["docker"]="true"; ARGS_INSTALL_CHOICES["nvm"]="true"; shift ;;
            --help) show_help ;;
            *) log_error "未知选项: $1. 使用 --help 查看帮助。"; shift ;;
        esac
    done
}

# --- 主逻辑 ---

# 初始化检查
if [[ "$(id -u)" -ne 0 ]]; then log_error "此脚本必须使用 root 权限运行"; fi
if ! command -v apt &> /dev/null; then log_error "未检测到 'apt'。此脚本仅支持 Debian/Ubuntu。"; fi
if [[ -f /etc/os-release ]]; then . /etc/os-release; else ID="unknown"; VERSION_ID="unknown"; fi
log_info "检测到系统: ${PRETTY_NAME:-Debian/Ubuntu} (ID: $ID, Version: $VERSION_ID)"
log_info "将为用户 '$CURRENT_USER' (主目录: $CURRENT_HOME) 安装用户级工具并添加到 docker 组。"

# 解析命令行参数
parse_arguments "$@"

# 定义工具名称到函数名的映射
declare -A TOOL_TO_FUNCTION=( ["basic"]="install_basic_packages" ["git"]="install_git" ["c_cpp"]="install_c_cpp" ["python"]="install_python" ["go"]="install_go" ["java"]="install_java" ["node"]="install_nodejs" ["rust"]="install_rust" ["ruby"]="install_ruby" ["php"]="install_php" ["docker"]="install_docker" ["nvm"]="install_nvm" )

# 非交互式安装
if [[ "$NON_INTERACTIVE" == true ]]; then
    log_info "开始非交互式安装..."
    FAILED_INSTALLS=()
    INSTALL_COUNT=0
    ORDERED_TOOLS=("basic" "git" "c_cpp" "python" "go" "java" "node" "rust" "ruby" "php" "docker" "nvm")

    for tool_name in "${ORDERED_TOOLS[@]}"; do
        if [[ -v ARGS_INSTALL_CHOICES["$tool_name"] ]]; then
            INSTALL_COUNT=$((INSTALL_COUNT + 1))
            # 修正：移除 local
            install_arg="${ARGS_INSTALL_CHOICES[$tool_name]}"
            install_func="${TOOL_TO_FUNCTION[$tool_name]}"
            option_desc="$tool_name"

            echo ""
            log_info "--- 开始处理: $option_desc (参数: $install_arg) ---"
            if [[ "$install_arg" == "true" ]]; then install_arg=""; fi
            if $install_func "$install_arg"; then
                log_info "--- 完成处理: $option_desc ---"
            else
                log_warning "--- 处理失败或跳过: $option_desc (请查看上面的信息) ---"
                FAILED_INSTALLS+=("$option_desc")
            fi
            echo ""
        fi
    done

    echo "=================================================="
    if [[ $INSTALL_COUNT -gt 0 ]]; then
         log_info "非交互式安装任务已执行完毕。"
         if [[ ${#FAILED_INSTALLS[@]} -gt 0 ]]; then log_warning "以下选项处理失败或被跳过:"; for failed in "${FAILED_INSTALLS[@]}"; do echo "  - $failed"; done; fi
         FINAL_WARNINGS=(); if [[ "$RUST_INSTALLED_FLAG" == true ]]; then FINAL_WARNINGS+=("Rust (需要 'source \$HOME/.cargo/env' 或重开终端)"); fi; if [[ "$DOCKER_INSTALLED_FLAG" == true ]]; then FINAL_WARNINGS+=("Docker (需要重新登录或 'newgrp docker')"); fi; if [[ "$NVM_INSTALLED_FLAG" == true ]]; then FINAL_WARNINGS+=("nvm (需要 'source \$HOME/.bashrc' 或重开终端)"); fi; if [[ "$PYTHON_COMPILED_FLAG" == true ]]; then FINAL_WARNINGS+=("编译的 Python (已安装到 /usr/local/bin/pythonX.Y)"); fi; if [[ ${#FINAL_WARNINGS[@]} -gt 0 ]]; then log_warning "请注意以下工具可能需要额外操作或注意:"; for warning in "${FINAL_WARNINGS[@]}"; do echo "  - $warning"; done; fi
    else
         log_warning "没有指定任何有效的安装选项。"
    fi
    echo "=================================================="
    log_info "脚本执行结束。"
    exit 0
fi

# --- 交互式菜单模式 ---

# 定义菜单选项
MENU_OPTIONS[0]="基础软件包 (推荐首次运行安装)"; INSTALL_FUNCTIONS[0]="install_basic_packages"
MENU_OPTIONS[1]="Git"; INSTALL_FUNCTIONS[1]="install_git"
MENU_OPTIONS[2]="C/C++ 开发工具"; INSTALL_FUNCTIONS[2]="install_c_cpp"
MENU_OPTIONS[3]="Python 3 (apt版 / 源码编译 / 跳过)"; INSTALL_FUNCTIONS[3]="install_python" # 修正描述
MENU_OPTIONS[4]="Go (Golang) (apt版 或 提示手动安装)"; INSTALL_FUNCTIONS[4]="install_go"
MENU_OPTIONS[5]="Java (Microsoft OpenJDK ${DEFAULT_JAVA_VERSION})"; INSTALL_FUNCTIONS[5]="install_java"
MENU_OPTIONS[6]="Node.js (通过 NodeSource 安装 LTS/最新版)"; INSTALL_FUNCTIONS[6]="install_nodejs"
MENU_OPTIONS[7]="Rust (官方 rustup)"; INSTALL_FUNCTIONS[7]="install_rust"
MENU_OPTIONS[8]="Ruby (apt版 或 提示版本管理器)"; INSTALL_FUNCTIONS[8]="install_ruby"
MENU_OPTIONS[9]="PHP (及常用扩展, Ubuntu可选PPA)"; INSTALL_FUNCTIONS[9]="install_php"
MENU_OPTIONS[10]="Docker CE (官方源)"; INSTALL_FUNCTIONS[10]="install_docker"
MENU_OPTIONS[11]="安装 nvm (Node 版本管理器)"; INSTALL_FUNCTIONS[11]="install_nvm"

# 显示菜单循环
while true; do
    clear
    echo "=================================================="; echo " 请选择要安装的开发环境/工具 (交互式菜单)"; echo "=================================================="
    sorted_keys=$(printf "%s\n" "${!MENU_OPTIONS[@]}" | sort -n); for i in $sorted_keys; do printf "%2d) %s\n" "$i" "${MENU_OPTIONS[$i]}"; done
    echo "--------------------------------------------------"; echo "输入选项数字，多个选项用逗号或空格分隔 (例如: 0,1,3 或 0 1 3)"; echo "输入 'q' 退出"; echo "=================================================="
    read -p "请输入选项: " USER_CHOICES
    if [[ "$USER_CHOICES" =~ ^[Qq]$ ]]; then log_info "用户选择退出。"; break; fi
    SANITIZED_CHOICES=$(echo "$USER_CHOICES" | tr ',' ' '); INSTALL_COUNT=0; FAILED_INSTALLS=(); NVM_INSTALLED_FLAG=false; PYTHON_COMPILED_FLAG=false; RUST_INSTALLED_FLAG=false; DOCKER_INSTALLED_FLAG=false
    for choice in $SANITIZED_CHOICES; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ -v INSTALL_FUNCTIONS[$choice] ]]; then
            INSTALL_COUNT=$((INSTALL_COUNT + 1)); OPTION_DESC=${MENU_OPTIONS[$choice]}; INSTALL_FUNC=${INSTALL_FUNCTIONS[$choice]}; echo ""; log_info "--- 开始处理: ${choice}) ${OPTION_DESC} ---"
            if $INSTALL_FUNC; then log_info "--- 完成处理: ${choice}) ${OPTION_DESC} ---"; else log_warning "--- 处理失败或跳过: ${choice}) ${OPTION_DESC} (请查看上面的信息) ---"; FAILED_INSTALLS+=("${choice}) ${OPTION_DESC}"); fi
            echo ""; read -p "按 Enter 继续下一个选项或返回菜单..."
        else if [[ -n "$choice" ]]; then log_warning "无效的选项 '$choice'，已忽略。"; fi; fi
    done
    echo "--------------------------------------------------"; if [[ $INSTALL_COUNT -gt 0 ]]; then log_info "本次选择的任务已执行完毕。"; if [[ ${#FAILED_INSTALLS[@]} -gt 0 ]]; then log_warning "以下选项处理失败或被跳过:"; for failed in "${FAILED_INSTALLS[@]}"; do echo "  - $failed"; done; fi; FINAL_WARNINGS=(); if [[ "$RUST_INSTALLED_FLAG" == true ]]; then FINAL_WARNINGS+=("Rust (需要 'source \$HOME/.cargo/env' 或重开终端)"); fi; if [[ "$DOCKER_INSTALLED_FLAG" == true ]]; then FINAL_WARNINGS+=("Docker (需要重新登录或 'newgrp docker')"); fi; if [[ "$NVM_INSTALLED_FLAG" == true ]]; then FINAL_WARNINGS+=("nvm (需要 'source \$HOME/.bashrc' 或重开终端)"); fi; if [[ "$PYTHON_COMPILED_FLAG" == true ]]; then FINAL_WARNINGS+=("编译的 Python (已安装到 /usr/local/bin/pythonX.Y)"); fi; if [[ ${#FINAL_WARNINGS[@]} -gt 0 ]]; then log_warning "请注意以下工具可能需要额外操作或注意:"; for warning in "${FINAL_WARNINGS[@]}"; do echo "  - $warning"; done; fi; elif [[ -n "$USER_CHOICES" ]]; then log_warning "未执行任何有效安装任务。"; fi; echo "--------------------------------------------------"
    read -p "按 Enter 返回菜单，或输入 'q' 退出..." CONTINUE_CHOICE; if [[ "$CONTINUE_CHOICE" =~ ^[Qq]$ ]]; then log_info "用户选择退出。"; break; fi
done

echo "=================================================="; log_info "脚本执行结束。"; echo "=================================================="
exit 0
