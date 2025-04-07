#!/bin/bash
# shellcheck disable=SC2155 # Allow 'local var=$(command)'

# ==============================================================================
# 开发环境部署脚本 (Debian/Ubuntu - v6.5 Help Color Fix)
#
# 功能: 通过命令行参数或交互式菜单安装开发工具，并提供更换 APT 源选项。
# 项目地址: https://github.com/butlanys/code.sh
#
# 命令行用法示例:
#   sudo ./deploy_dev_env.sh --git --python 3.11.9 --node lts --docker --go manual
#   sudo ./deploy_dev_env.sh --all --no-ppa
#   sudo ./deploy_dev_env.sh --change-source cn --basic-packages --git
#   sudo ./deploy_dev_env.sh --help
#
# 交互式用法:
#   sudo ./deploy_dev_env.sh (不带参数，启用彩色输出)
#
# 注意: 需要 root 权限。源码编译 Python 需要较长时间和依赖。
#       从官网安装 Go 依赖 curl/wget, grep, sed, awk, tar，且解析逻辑可能因官网改版失效。
#       更换 APT 源会修改系统配置，请谨慎操作，并确保信任 linuxmirrors.cn 脚本。
# ==============================================================================

# --- 安全设置 ---
set -e
set -o pipefail
# set -u

# ==============================================================================
# 颜色定义 (Color Definitions)
# 在非交互模式下会被清空
# ==============================================================================
COLOR_RESET='\e[0m'
COLOR_RED='\e[91m'
COLOR_GREEN='\e[32m'
COLOR_YELLOW='\e[33m'
COLOR_BLUE='\e[34m'
COLOR_MAGENTA='\e[35m'
COLOR_CYAN='\e[36m'
COLOR_BOLD='\e[1m'
COLOR_DIM='\e[2m'

# ==============================================================================
# 配置项 (Configuration)
# ==============================================================================
readonly DEFAULT_JAVA_VERSION="21"
readonly DEFAULT_NODE_LTS_MAJOR_VERSION="20"
readonly DEFAULT_NODE_LATEST_MAJOR_VERSION="22"
readonly NVM_VERSION="0.39.7" # 请检查 https://github.com/nvm-sh/nvm/releases 获取最新版

# ==============================================================================
# 全局变量 (Global Variables)
# ==============================================================================
readonly CURRENT_USER="${SUDO_USER:-$(whoami)}"
readonly CURRENT_HOME=$(eval echo "~$CURRENT_USER")
OS_ID=""
OS_VERSION_ID=""
OS_PRETTY_NAME=""

declare -A g_cli_choices
g_non_interactive=false
g_php_no_ppa=false

g_nvm_installed=false
g_python_compiled=false
g_rust_installed=false
g_docker_installed=false
g_go_manual_installed=false
g_source_changed=false

# ==============================================================================
# 助手函数 (Helper Functions)
# ==============================================================================

# --- 日志函数 (带颜色) ---
_log_info() {
    echo -e "${COLOR_BLUE}[信息]${COLOR_RESET} $1"
}
_log_success() {
    echo -e "${COLOR_GREEN}[成功]${COLOR_RESET} $1"
}
_log_warning() {
    echo -e "${COLOR_YELLOW}[警告]${COLOR_RESET} $1" >&2
}
_log_error() {
    echo -e "${COLOR_RED}${COLOR_BOLD}[错误]${COLOR_RESET}${COLOR_RED} $1${COLOR_RESET}" >&2
    exit 1
}

# --- 带颜色的提示输入 ---
_read_prompt() {
    local prompt_text="$1"
    local variable_name="$2"
    local default_value="${3:-}"

    local prompt_display="${prompt_text}"
    if [[ -n "$default_value" ]]; then
        prompt_display+=" [默认: ${default_value}]"
    fi

    # 使用 read -p 输出带颜色的提示 (颜色变量可能为空)
    read -p "$(echo -e "${COLOR_CYAN}${prompt_display}:${COLOR_RESET} ")" "$variable_name"

    if [[ -z "${!variable_name}" && -n "$default_value" ]]; then
        # 使用 eval 动态设置变量值
        eval "$variable_name=\"$default_value\""
    fi
}


# --- 显示帮助信息 ---
_show_help() {
    # 帮助信息总是带颜色，因为它只在直接请求帮助时显示
    local R='\e[0m' B='\e[1m' D='\e[2m'
    local RD='\e[91m' GR='\e[32m' YL='\e[33m' BL='\e[34m' MG='\e[35m' CY='\e[36m'

    printf "\n"
    printf "%b\n" "${MG}${B}开发环境部署脚本 (Debian/Ubuntu)${R}"
    printf "\n"
    printf "%b\n" "${YL}功能:${R} 通过命令行参数或交互式菜单安装开发工具，并提供更换 APT 源选项。"
    printf "%b\n" "${YL}项目:${R} ${CY}https://github.com/butlanys/code.sh${R}"
    printf "\n"
    printf "%b\n" "${MG}${B}用法:${R} $0 [选项...]"
    printf "\n"
    printf "%b\n" "${YL}选项:${R}"
    printf "%b\n" "  ${GR}--basic-packages${R}          安装基础软件包 (curl, wget, git, vim, etc.)"
    printf "%b\n" "  ${GR}--git${R}                     安装 Git 版本控制系统"
    printf "%b\n" "  ${GR}--c-cpp${R}                   安装 C/C++ 开发工具 (build-essential, cmake, gdb)"
    printf "%b\n" "  ${GR}--python <version|apt>${R}    安装 Python。'apt' 安装系统默认版本；"
    printf "%b\n" "                            提供具体版本号 (如 '3.11.9') 将尝试从源码编译。"
    printf "%b\n" "  ${GR}--go <apt|manual|latest>${R}  安装 Go 语言环境。'apt' 安装系统版本；"
    printf "%b\n" "                            'manual' 或 'latest' 从官网下载安装最新稳定版。"
    printf "%b\n" "  ${GR}--java${R}                    安装 Java (Microsoft OpenJDK ${DEFAULT_JAVA_VERSION})。"
    printf "%b\n" "  ${GR}--node <lts|latest|ver>${R}   安装 Node.js。'lts' 安装 LTS 版本 (${DEFAULT_NODE_LTS_MAJOR_VERSION}.x)，"
    printf "%b\n" "                            'latest' 安装最新版 (${DEFAULT_NODE_LATEST_MAJOR_VERSION}.x)，或指定主版本号 (如 '20')。"
    printf "%b\n" "                            (通过 NodeSource 安装)"
    printf "%b\n" "  ${GR}--rust${R}                    安装 Rust 语言环境 (通过官方 rustup)。"
    printf "%b\n" "  ${GR}--ruby <apt>${R}              安装 Ruby (仅支持 'apt' 安装系统版本)。"
    printf "%b\n" "  ${GR}--php${R}                     安装 PHP 及常用扩展。在 Ubuntu 上默认尝试添加 Ondrej PPA。"
    printf "%b\n" "  ${GR}--no-ppa${R}                  与 --php 结合使用，强制不在 Ubuntu 上添加 Ondrej PPA。"
    printf "%b\n" "  ${GR}--docker${R}                  安装 Docker CE (社区版)。"
    printf "%b\n" "  ${GR}--nvm${R}                     安装 nvm (Node Version Manager)，用于管理多个 Node.js 版本。"
    printf "%b\n" "  ${GR}--change-source <cn|abroad>${R} 更换 APT 软件源 ${D}(当默认源下载速度慢时使用)${R}。"
    printf "%b\n" "                            'cn' 使用中国大陆镜像，'abroad' 使用国际官方源。"
    printf "%b\n" "                            (使用 linuxmirrors.cn 脚本)"
    printf "%b\n" "  ${GR}--all${R}                     安装所有上述常用工具 (使用推荐的默认设置，Go默认从官网安装)。"
    printf "%b\n" "  ${GR}--help${R}                    显示此帮助信息并退出。"
    printf "\n"
    printf "%b\n" "${MG}${B}示例:${R}"
    printf "%b\n" "  ${D}# 安装 git, 编译 python 3.11.9, 安装 node lts 版, 从官网安装 Go${R}"
    printf "%b\n" "  sudo $0 --git --python 3.11.9 --node lts --go manual"
    printf "\n"
    printf "%b\n" "  ${D}# 更换为中国大陆源后安装基础包和 git${R}"
    printf "%b\n" "  sudo $0 --change-source cn --basic-packages --git"
    printf "\n"
    printf "%b\n" "  ${D}# 安装所有工具，但不为 PHP 添加 PPA${R}"
    printf "%b\n" "  sudo $0 --all --no-ppa"
    printf "\n"
    printf "%b\n" "  ${D}# 进入交互式菜单${R}"
    printf "%b\n" "  sudo $0"
    printf "\n"
    printf "%b\n" "${MG}${B}注意事项:${R}"
    printf "%b\n" "  - 脚本需要以 ${YL}root 权限 (sudo)${R} 运行。"
    printf "%b\n" "  - 源码编译 Python 可能需要较长时间，并依赖 build-essential 等包。"
    printf "%b\n" "  - 从官网安装 Go 依赖 curl/wget, grep, sed, awk, tar，且解析逻辑可能因官网改版失效。"
    printf "%b\n" "  - 更换 APT 源会修改系统配置，请谨慎操作，并确保信任 ${CY}linuxmirrors.cn${R} 脚本。"
    # 在注意事项中动态获取 CURRENT_USER
    printf "%b\n" "  - Rust 和 nvm 会安装到执行 sudo 命令的用户 (${YL}${SUDO_USER:-$(whoami)}${R}) 的家目录下。"
    printf "%b\n" "  - 安装 Docker 后，需要重新登录或运行 'newgrp docker' 才能免 sudo 使用 docker 命令。"
    printf "%b\n" "  - 手动安装 Go 后，需要重新登录或运行 'source /etc/profile.d/go.sh' 才能使用 go 命令。"
    printf "%b\n" "  - 更换 APT 源后，建议在脚本执行完毕后运行 'sudo apt update && sudo apt upgrade'。"
    printf "\n"

    exit 0
}


# --- 显示版本管理器建议 ---
_show_version_manager_info() {
    local lang="$1"
    clear
    echo -e "${COLOR_MAGENTA}--------------------------------------------------${COLOR_RESET}"
    _log_warning "您选择了不安装 $lang 的 apt 版本或需要特定版本。"
    _log_info "对于 $lang 的多版本管理或安装特定版本，强烈建议使用专门的版本管理器："
    case "$lang" in
        Python)
            echo -e "  - ${COLOR_GREEN}pyenv${COLOR_RESET}: 强大的 Python 版本管理器。"
            echo -e "    安装指南: ${COLOR_CYAN}https://github.com/pyenv/pyenv#installation${COLOR_RESET}"
            echo -e "  - ${COLOR_GREEN}asdf${COLOR_RESET}: 通用的版本管理器，支持多种语言，包括 Python。"
            echo -e "    安装指南: ${COLOR_CYAN}https://asdf-vm.com/${COLOR_RESET}"
            echo -e "  - ${COLOR_GREEN}deadsnakes PPA${COLOR_RESET} (仅 Ubuntu): 提供较新的 Python apt 包。"
            echo -e "    查找方法: sudo add-apt-repository ppa:deadsnakes/ppa && sudo apt update"
            ;;
        Go)
            echo -e "  - ${COLOR_GREEN}gvm${COLOR_RESET} (Go Version Manager): 类似于 nvm/rbenv。"
            echo -e "    安装指南: ${COLOR_CYAN}https://github.com/moovweb/gvm${COLOR_RESET}"
            echo -e "  - ${COLOR_GREEN}asdf${COLOR_RESET}: 通用的版本管理器，支持 Go。"
            echo -e "    安装指南: ${COLOR_CYAN}https://asdf-vm.com/${COLOR_RESET}"
            ;;
        Ruby)
            echo -e "  - ${COLOR_GREEN}rbenv${COLOR_RESET}: 流行的 Ruby 版本管理器。"
            echo -e "    安装指南: ${COLOR_CYAN}https://github.com/rbenv/rbenv#installation${COLOR_RESET}"
            echo -e "  - ${COLOR_GREEN}RVM${COLOR_RESET} (Ruby Version Manager): 另一个功能丰富的版本管理器。"
            echo -e "    安装指南: ${COLOR_CYAN}https://rvm.io/rvm/install${COLOR_RESET}"
            echo -e "  - ${COLOR_GREEN}asdf${COLOR_RESET}: 通用的版本管理器，支持 Ruby。"
            echo -e "    安装指南: ${COLOR_CYAN}https://asdf-vm.com/${COLOR_RESET}"
            ;;
        *)
            echo "  (无特定版本管理器推荐信息)"
            ;;
    esac
    echo -e "${COLOR_MAGENTA}--------------------------------------------------${COLOR_RESET}"
    local dummy_var
    _read_prompt "按 Enter 继续" dummy_var
}

# --- 运行 apt update (带重试和警告) ---
_run_apt_update() {
    _log_info "正在更新软件包列表 (apt update)..."
    if ! apt update; then
        _log_warning "第一次 apt update 失败，尝试再次更新..."
        if ! apt update; then
            _log_warning "apt update 仍然失败，后续安装可能会遇到问题，但脚本将继续尝试。"
        fi
    fi
}

# --- 安装 apt 包 (带错误处理) ---
# 用法: _install_apt_packages "包名1" "包名2" ...
_install_apt_packages() {
    if [[ $# -eq 0 ]]; then
        _log_warning "_install_apt_packages: 没有指定要安装的包。"
        return 1
    fi
    local pkgs=("$@")
    _log_info "正在安装软件包: ${COLOR_YELLOW}${pkgs[*]}${COLOR_RESET}..."
    export DEBIAN_FRONTEND=noninteractive
    if ! apt install -y "${pkgs[@]}"; then
        echo -e "${COLOR_RED}[错误]${COLOR_RESET} 安装软件包失败: ${COLOR_YELLOW}${pkgs[*]}${COLOR_RESET}" >&2
        return 1
    fi
    _log_success "软件包安装完成: ${COLOR_YELLOW}${pkgs[*]}${COLOR_RESET}"
    return 0
}

# --- 获取 Go 架构名称 ---
_get_go_arch() {
    local dpkg_arch
    dpkg_arch=$(dpkg --print-architecture)
    case "$dpkg_arch" in
        amd64) echo "amd64" ;;
        arm64) echo "arm64" ;;
        armhf) echo "armv6l" ;;
        i386)  echo "386" ;;
        *)     _log_error "当前脚本不支持为架构 '${dpkg_arch}' 自动安装 Go。"; return 1 ;;
    esac
    return 0
}

# ==============================================================================
# 安装函数 (Installation Functions)
# ==============================================================================

# --- 0: 安装基础软件包 ---
_install_basic_packages() {
    _log_info "[0] 开始安装基础软件包..."
    _run_apt_update
    # 添加 Go 手动安装需要的依赖: curl/wget, grep, sed, awk, tar
    if ! _install_apt_packages curl wget vim htop git unzip net-tools ca-certificates gnupg lsb-release software-properties-common apt-transport-https grep sed awk tar; then
        _log_error "基础软件包安装失败。"
        return 1
    fi
    _log_success "[0] 基础软件包安装完成。"
    return 0
}

# --- 1: 安装 Git ---
_install_git() {
    _log_info "[1] 开始安装 Git..."
    if ! _install_apt_packages git; then
        _log_error "Git 安装失败。"
        return 1
    fi
    local git_version=$(git --version 2>/dev/null || echo "未知")
    _log_success "[1] Git 安装完成。版本: ${COLOR_GREEN}${git_version}${COLOR_RESET}"
    return 0
}

# --- 2: 安装 C/C++ 开发工具 ---
_install_c_cpp() {
    _log_info "[2] 开始安装 C/C++ 开发工具..."
    if ! _install_apt_packages build-essential gdb make cmake; then
        _log_error "C/C++ 开发工具安装失败。"
        return 1
    fi
    local gcc_version=$(gcc --version | head -n 1 2>/dev/null || echo "未知")
    local cmake_version=$(cmake --version | head -n 1 2>/dev/null || echo "未知")
    _log_success "[2] C/C++ 开发工具安装完成。"
    _log_info "   - GCC 版本: ${COLOR_GREEN}${gcc_version}${COLOR_RESET}"
    _log_info "   - CMake 版本: ${COLOR_GREEN}${cmake_version}${COLOR_RESET}"
    return 0
}

# --- 3: 安装 Python 3 ---
_install_python() {
    local install_type="$1"

    if [[ "$g_non_interactive" == true ]]; then
        if [[ -z "$install_type" ]]; then
            _log_warning "[3] 非交互模式下未指定 Python 安装类型 (apt 或版本号)，跳过。"
            return 0
        elif [[ "$install_type" == "apt" ]]; then
            _log_info "[3] 开始安装 Python 3 (apt)..."
            if ! _install_apt_packages python3 python3-pip python3-venv; then
                 _log_error "Python 3 (apt) 安装失败。"
                 return 1
            fi
            _log_success "[3] Python 3 (apt) 安装完成。"
        elif [[ "$install_type" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            _log_info "[3] 准备从源码编译 Python ${COLOR_YELLOW}${install_type}${COLOR_RESET}..."
            if ! _compile_python_from_source "${install_type}"; then
                return 1
            fi
        else
            _log_error "[3] 无效的 Python 安装类型 '${COLOR_YELLOW}${install_type}${COLOR_RESET}'。请使用 'apt' 或 'X.Y.Z' 版本号。"
            return 1
        fi
    else
        clear
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        echo -e " ${COLOR_BOLD}Python 3 安装选项${COLOR_RESET}"
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        echo "  1) 使用 apt 安装系统默认版本 (${COLOR_GREEN}推荐，最稳定${COLOR_RESET})"
        echo "  2) 从源码编译安装指定版本 (${COLOR_YELLOW}高级，耗时，需要依赖${COLOR_RESET})"
        echo "  3) 跳过安装 (${COLOR_DIM}推荐使用 pyenv 等版本管理器${COLOR_RESET})"
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        local python_choice
        _read_prompt "请输入选项" python_choice "1"

        case "$python_choice" in
            1)
                _log_info "[3] 开始安装 Python 3 (apt)..."
                if ! _install_apt_packages python3 python3-pip python3-venv; then
                    _log_error "Python 3 (apt) 安装失败。"
                    return 1
                fi
                _log_success "[3] Python 3 (apt) 安装完成。"
                ;;
            2)
                _log_info "[3] 准备从源码编译 Python..."
                if ! _compile_python_from_source; then
                     return 1
                fi
                ;;
            3)
                _show_version_manager_info "Python"
                return 0
                ;;
            *)
                _log_warning "[3] 无效的选择，跳过 Python 安装。"
                return 0
                ;;
        esac
    fi

    if [[ "$install_type" == "apt" || "$python_choice" == "1" ]] && command -v python3 &> /dev/null; then
        local py_version=$(python3 --version 2>/dev/null || echo "未知")
        local pip_version=$(pip3 --version 2>/dev/null || echo "未知")
        _log_info "   - Python 3 (apt) 版本: ${COLOR_GREEN}${py_version}${COLOR_RESET}"
        _log_info "   - pip3 (apt) 版本: ${COLOR_GREEN}${pip_version}${COLOR_RESET}"
    fi

    return 0
}

# --- 3.1: 从源码编译 Python (被 _install_python 调用) ---
_compile_python_from_source() {
    local target_version="$1"
    local chosen_version=""

    _log_info "开始 Python 源码编译过程..."
    _log_warning "此过程需要安装编译依赖，并可能花费较长时间。"

    _log_info "正在安装 Python 编译依赖..."
    local build_deps="build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget curl llvm libbz2-dev pkg-config liblzma-dev tk-dev libxml2-dev libxmlsec1-dev"
    if ! _install_apt_packages ${build_deps}; then return 1; fi
    _log_success "编译依赖安装完成。"

    if [[ -n "$target_version" ]]; then
        _log_info "检查指定的 Python 版本 ${COLOR_YELLOW}${target_version}${COLOR_RESET} 是否可用..."
        if curl --output /dev/null --silent --head --fail "https://www.python.org/ftp/python/${target_version}/"; then
            _log_success "版本 ${COLOR_YELLOW}${target_version}${COLOR_RESET} 可用，继续。"
            chosen_version="$target_version"
        else
            _log_error "指定的 Python 版本 ${COLOR_YELLOW}${target_version}${COLOR_RESET} 在 python.org 上未找到或无法访问。"
            return 1
        fi
    else
        _log_info "正在从 python.org 获取可用的 Python 3 稳定版本列表..."
        local available_versions_html
        if ! available_versions_html=$(curl -sL --fail --connect-timeout 15 https://www.python.org/ftp/python/); then
             _log_error "无法从 python.org 获取版本列表。"
             return 1
        fi

        local python_versions
        mapfile -t python_versions < <(echo "$available_versions_html" | grep -oP 'href="3\.([0-9]+)\.([0-9]+)/"' | sed 's/href="//; s/\/"//' | sort -Vur)

        if [[ ${#python_versions[@]} -eq 0 ]]; then
            _log_error "未能解析出可用的 Python 3 版本。"
            return 1
        fi

        clear
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        echo -e " ${COLOR_BOLD}选择要编译的 Python 3 版本${COLOR_RESET}"
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        _log_info "以下是检测到的最新 Python 3 稳定版本:"
        local display_count=15
        local options_count=0
        declare -A version_map
        for i in "${!python_versions[@]}"; do
            if [[ $options_count -lt $display_count ]]; then
                local index=$((options_count + 1))
                printf "  %2d) %s\n" "$index" "${COLOR_YELLOW}${python_versions[$i]}${COLOR_RESET}"
                version_map[$index]="${python_versions[$i]}"
                options_count=$((options_count + 1))
            else
                break
            fi
        done
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        echo "   0) 取消编译安装"
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"

        while true; do
            local version_choice
            _read_prompt "请选择版本序号 (输入 0 取消)" version_choice
            if [[ "$version_choice" == "0" ]]; then
                _log_info "用户取消编译安装。"
                return 1
            elif [[ "$version_choice" =~ ^[0-9]+$ ]] && [[ -v version_map[$version_choice] ]]; then
                chosen_version=${version_map[$version_choice]}
                _log_info "您选择了版本: ${COLOR_YELLOW}${chosen_version}${COLOR_RESET}"
                break
            else
                _log_warning "无效的选择，请输入列表中的序号。"
            fi
        done
    fi

    local source_filename="Python-${chosen_version}.tar.xz"
    local source_url="https://www.python.org/ftp/python/${chosen_version}/${source_filename}"
    local download_dir="/tmp/python_build_$$"
    mkdir -p "$download_dir" || { _log_error "无法创建临时目录 ${download_dir}"; return 1; }

    local source_path="${download_dir}/${source_filename}"
    local source_dir="${download_dir}/Python-${chosen_version}"

    _log_info "正在下载 Python ${COLOR_YELLOW}${chosen_version}${COLOR_RESET} 源码从 ${COLOR_CYAN}${source_url}${COLOR_RESET} ..."
    if ! wget --quiet --show-progress --progress=bar:force:noscroll --connect-timeout=15 --tries=3 -P "$download_dir" "$source_url"; then
        _log_error "下载源码失败 (URL: ${source_url})。"
        rm -rf "$download_dir"
        return 1
    fi
    _log_success "源码下载完成: ${source_path}"

    _log_info "正在解压源码..."
    rm -rf "$source_dir"
    if ! tar -xf "$source_path" -C "$download_dir"; then
        _log_error "解压源码失败 (${source_path})。"
        rm -rf "$download_dir"
        return 1
    fi
    _log_success "源码解压到: ${source_dir}"

    _log_info "进入源码目录并开始配置..."
    cd "$source_dir" || { _log_error "无法进入源码目录 ${source_dir}"; cd /; rm -rf "$download_dir"; return 1; }

    _log_info "运行 ${COLOR_DIM}./configure --enable-optimizations --with-ensurepip=install ...${COLOR_RESET}"
    if ! ./configure --enable-optimizations --with-ensurepip=install LDFLAGS="-Wl,-rpath=/usr/local/lib"; then
        _log_error "配置 (configure) 失败。"
        cd /; rm -rf "$download_dir"
        return 1
    fi

    _log_info "配置完成。开始编译 (${COLOR_DIM}make -j N${COLOR_RESET})... ${COLOR_YELLOW}这可能需要很长时间。${COLOR_RESET}"
    if ! make -j"$(nproc)"; then
        _log_error "编译 (make) 失败。"
        cd /; rm -rf "$download_dir"
        return 1
    fi

    _log_info "编译完成。开始安装 (${COLOR_DIM}make altinstall${COLOR_RESET})..."
    if ! make altinstall; then
        _log_error "安装 (make altinstall) 失败。"
        cd /; rm -rf "$download_dir"
        return 1
    fi

    _log_success "Python ${COLOR_YELLOW}${chosen_version}${COLOR_RESET} 编译安装完成！"

    _log_info "正在清理临时文件..."
    cd /
    rm -rf "$download_dir"
    _log_success "清理完成。"

    local installed_python_executable="/usr/local/bin/python${chosen_version%.*}"
    if [[ -x "$installed_python_executable" ]]; then
        _log_info "您可以通过命令 '${COLOR_GREEN}${installed_python_executable}${COLOR_RESET}' 来使用新安装的 Python 版本。"
        _log_info "例如: ${COLOR_GREEN}${installed_python_executable} --version${COLOR_RESET}"
        _log_info "对应的 pip 命令通常是: ${COLOR_GREEN}${installed_python_executable} -m pip${COLOR_RESET}"
    else
         _log_warning "编译安装后未找到预期的 Python 可执行文件: ${installed_python_executable}"
    fi
    _log_warning "请注意，系统默认的 'python3' 命令仍然指向 apt 安装的版本（如果存在）。"

    g_python_compiled=true
    return 0
}

# --- 4: 安装 Go (Golang) ---
_install_go() {
    local install_type="$1"

    if [[ "$g_non_interactive" == true ]]; then
        if [[ "$install_type" == "apt" ]]; then
            _log_info "[4] 开始安装 Go (apt)..."
            if ! _install_apt_packages golang-go; then
                _log_error "Go (apt) 安装失败。"
                return 1
            fi
            _log_success "[4] Go (apt) 安装完成。"
        elif [[ "$install_type" == "manual" || "$install_type" == "latest" ]]; then
             _log_info "[4] 开始从官网手动安装最新稳定版 Go..."
             if ! _install_go_manual; then
                 return 1
             fi
        else
            _log_error "[4] 无效的 Go 安装类型 '${COLOR_YELLOW}${install_type}${COLOR_RESET}'。请使用 'apt' 或 'manual'/'latest'。"
            return 1
        fi
    else
        clear
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        echo -e " ${COLOR_BOLD}Go (Golang) 安装选项${COLOR_RESET}"
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        echo "  1) 使用 apt 安装系统默认版本 (${COLOR_DIM}可能不是最新版${COLOR_RESET})"
        echo "  2) 从官网下载并安装最新稳定版本 (${COLOR_GREEN}推荐${COLOR_RESET})"
        echo "  3) 跳过安装 (${COLOR_DIM}或使用 gvm/asdf 等管理器${COLOR_RESET})"
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        local go_choice
        _read_prompt "请输入选项" go_choice "2"

        case "$go_choice" in
            1)
                _log_info "[4] 开始安装 Go (apt)..."
                if ! _install_apt_packages golang-go; then
                    _log_error "Go (apt) 安装失败。"
                    return 1
                fi
                _log_success "[4] Go (apt) 安装完成。"
                ;;
            2)
                _log_info "[4] 开始从官网手动安装最新稳定版 Go..."
                if ! _install_go_manual; then
                    return 1
                fi
                ;;
            3)
                _show_version_manager_info "Go"
                return 0
                ;;
            *)
                _log_warning "[4] 无效的选择，跳过 Go 安装。"
                return 0
                ;;
        esac
    fi

    local go_executable=""
    if ([[ "$install_type" == "apt" || "$go_choice" == "1" ]]) && command -v go &> /dev/null; then
        go_executable="go"
    elif ([[ "$install_type" == "manual" || "$install_type" == "latest" || "$go_choice" == "2" ]]) && [[ -x "/usr/local/go/bin/go" ]]; then
         go_executable="/usr/local/go/bin/go"
         _log_info "Go 已安装到 ${COLOR_YELLOW}/usr/local/go${COLOR_RESET}。请重新登录或 ${COLOR_CYAN}source /etc/profile.d/go.sh${COLOR_RESET} 来使用 'go' 命令。"
    fi

    if [[ -n "$go_executable" ]]; then
         local go_version=$("$go_executable" version 2>/dev/null || echo "未知")
         _log_info "   - Go 版本: ${COLOR_GREEN}${go_version}${COLOR_RESET}"
    elif [[ "$install_type" != "manual" && "$install_type" != "latest" && "$go_choice" != "2" && "$go_choice" != "3" ]]; then
         _log_warning "Go 命令 (go) 未在当前 PATH 找到。"
    fi
    return 0
}

# --- 4.1: 从官网手动安装 Go (被 _install_go 调用) ---
_install_go_manual() {
    local go_arch
    if ! go_arch=$(_get_go_arch); then return 1; fi
    local go_os="linux"

    _log_info "目标平台: ${COLOR_YELLOW}${go_os}-${go_arch}${COLOR_RESET}"

    local missing_deps=()
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then missing_deps+=("curl 或 wget"); fi
    if ! command -v grep &> /dev/null; then missing_deps+=("grep"); fi
    if ! command -v sed &> /dev/null; then missing_deps+=("sed"); fi
    if ! command -v awk &> /dev/null; then missing_deps+=("awk"); fi
    if ! command -v tar &> /dev/null; then missing_deps+=("tar"); fi
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        _log_error "缺少必要的命令: ${COLOR_YELLOW}${missing_deps[*]}${COLOR_RESET}。请先安装它们。"
        return 1
    fi

    _log_info "正在从 ${COLOR_CYAN}go.dev/dl/${COLOR_RESET} 获取最新稳定版 Go 信息..."
    local dl_page_html downloader_cmd
    if command -v curl &> /dev/null; then
        downloader_cmd="curl -sL --fail --connect-timeout 15 https://go.dev/dl/"
    elif command -v wget &> /dev/null; then
        downloader_cmd="wget -qO- --timeout=15 https://go.dev/dl/"
    fi

    if ! dl_page_html=$($downloader_cmd); then
        _log_error "无法获取 Go 下载页面内容 (${COLOR_CYAN}https://go.dev/dl/${COLOR_RESET})。"
        return 1
    fi

    _log_info "正在解析适用于 ${COLOR_YELLOW}${go_os}-${go_arch}${COLOR_RESET} 的最新稳定版 Go 下载链接..."
    local download_url_path filename go_version

    download_url_path=$(echo "$dl_page_html" | \
        grep -o -E -m 1 'href="(/dl/go[0-9]+\.[0-9]+(\.[0-9]+)?\.linux-'"$go_arch"'\.tar\.gz)"' | \
        sed 's/href="//; s/"$//')

    if [[ -z "$download_url_path" ]]; then
        _log_error "无法在下载页面上找到适用于 ${COLOR_YELLOW}${go_os}-${go_arch}${COLOR_RESET} 的 .tar.gz 下载链接。"
        _log_warning "Go 官网页面结构可能已更改，此脚本的解析逻辑需要更新。"
        return 1
    fi

    filename=$(basename "$download_url_path")
    go_version=$(echo "$filename" | sed -n 's/^go\([0-9.]*\)\.linux.*$/\1/p')

    if [[ -z "$filename" || -z "$go_version" ]]; then
        _log_error "无法从下载链接 '${COLOR_YELLOW}${download_url_path}${COLOR_RESET}' 中解析出文件名或版本号。"
        return 1
    fi

    local download_url="https://go.dev${download_url_path}"

    _log_success "找到最新稳定 Go 版本: ${COLOR_YELLOW}${go_version}${COLOR_RESET} (${COLOR_DIM}${filename}${COLOR_RESET})"
    _log_info "下载地址: ${COLOR_CYAN}${download_url}${COLOR_RESET}"

    _log_info "正在解析 SHA256 校验和..."
    local expected_checksum
    expected_checksum=$(echo "$dl_page_html" | \
         awk -v url_path="$download_url_path" '
         BEGIN { RS="</tr>" }
         $0 ~ url_path {
             if (match($0, /<tt>([a-f0-9]{64})<\/tt>/, arr)) {
                 print arr[1];
                 exit;
             }
         }')

    if [[ -z "$expected_checksum" ]]; then
        _log_warning "无法自动解析 SHA256 校验和。将 ${COLOR_RED}跳过校验${COLOR_RESET}${COLOR_YELLOW}！请手动验证文件完整性。${COLOR_RESET}"
    else
        _log_info "预期 SHA256: ${COLOR_DIM}${expected_checksum}${COLOR_RESET}"
    fi

    local download_path="/tmp/${filename}"
    _log_info "正在下载 ${COLOR_YELLOW}${filename}${COLOR_RESET} 到 /tmp ..."
    local wget_extra_args="--quiet --show-progress --progress=bar:force:noscroll"
    local curl_extra_args="-# -L"
    if command -v wget &> /dev/null; then
        if ! wget $wget_extra_args -O "$download_path" "$download_url"; then
             _log_error "使用 wget 下载 Go 归档文件失败 (URL: ${download_url})。"
             rm -f "$download_path"
             return 1
        fi
    elif command -v curl &> /dev/null; then
         if ! curl $curl_extra_args -o "$download_path" "$download_url"; then
             _log_error "使用 curl 下载 Go 归档文件失败 (URL: ${download_url})。"
             rm -f "$download_path"
             return 1
         fi
    fi
    _log_success "下载完成: ${download_path}"

    if [[ -n "$expected_checksum" ]]; then
        _log_info "正在校验 SHA256 checksum..."
        local actual_checksum
        actual_checksum=$(sha256sum "$download_path" | awk '{print $1}')
        if [[ "$actual_checksum" != "$expected_checksum" ]]; then
            _log_error "SHA256 校验和不匹配！下载的文件可能已损坏或被篡改。"
            _log_error "  预期: ${COLOR_DIM}${expected_checksum}${COLOR_RESET}"
            _log_error "  实际: ${COLOR_RED}${actual_checksum}${COLOR_RESET}"
            rm -f "$download_path"
            return 1
        fi
        _log_success "校验和匹配。"
    else
        _log_warning "已跳过 SHA256 校验。"
    fi

    local install_dir="/usr/local"
    _log_info "正在将 Go 解压到 ${COLOR_YELLOW}${install_dir}${COLOR_RESET} ..."
    if [[ -d "${install_dir}/go" ]]; then
        _log_info "检测到旧的 Go 安装目录 (${install_dir}/go)，正在移除..."
        rm -rf "${install_dir}/go" || { _log_error "移除旧的 Go 安装目录失败。"; rm -f "$download_path"; return 1; }
    fi
    if ! tar -C "$install_dir" -xzf "$download_path"; then
        _log_error "解压 Go 归档文件 (${download_path}) 到 ${install_dir} 失败。"
        rm -f "$download_path"
        rm -rf "${install_dir}/go"
        return 1
    fi
    _log_success "Go 已成功解压到 ${COLOR_YELLOW}${install_dir}/go${COLOR_RESET}"

    local go_profile_path="/etc/profile.d/go.sh"
    _log_info "正在配置系统范围的 PATH 环境变量 (${COLOR_YELLOW}${go_profile_path}${COLOR_RESET})..."
    if ! tee "$go_profile_path" > /dev/null <<EOF
# Go lang path configuration (added by script)
export PATH=\$PATH:/usr/local/go/bin
# Optional: Set GOROOT if needed by older tools, though often unnecessary now
# export GOROOT=/usr/local/go
# Optional: Set default GOPATH if desired
# export GOPATH=\$HOME/go
# export PATH=\$PATH:\$GOPATH/bin
EOF
    then
        _log_warning "写入 ${go_profile_path} 失败。请手动将 /usr/local/go/bin 添加到系统 PATH。"
    else
        chmod +x "$go_profile_path" || _log_warning "无法设置 ${go_profile_path} 的执行权限。"
        _log_success "环境变量已配置。请重新登录或运行 '${COLOR_CYAN}source ${go_profile_path}${COLOR_RESET}' 以使更改生效。"
    fi

    _log_info "正在清理下载文件 ${download_path} ..."
    rm -f "$download_path"

    _log_success "[4] Go (手动安装 ${COLOR_YELLOW}${go_version}${COLOR_RESET}) 完成。"
    g_go_manual_installed=true
    return 0
}


# --- 5: 安装 Java ---
_install_java() {
    _log_info "[5] 开始安装 Java (Microsoft OpenJDK ${COLOR_YELLOW}${DEFAULT_JAVA_VERSION}${COLOR_RESET})..."

    _log_info "正在安装 Java 依赖 (wget, lsb-release, ca-certificates)..."
    if ! _install_apt_packages wget lsb-release ca-certificates; then
        _log_error "安装 Java 依赖失败。"
        return 1
    fi

    _log_info "正在添加 Microsoft OpenJDK 仓库..."
    if [[ -z "$OS_VERSION_ID" || "$OS_ID" == "unknown" ]]; then
        _log_error "无法获取系统 ID (${OS_ID}) 或版本号 (${OS_VERSION_ID})，无法添加仓库。"
        return 1
    fi
    local ms_repo_deb="packages-microsoft-prod.deb"
    local ms_repo_url="https://packages.microsoft.com/config/${OS_ID}/${OS_VERSION_ID}/${ms_repo_deb}"

    _log_info "正在下载 Microsoft 仓库配置文件: ${COLOR_CYAN}${ms_repo_url}${COLOR_RESET}"
    local temp_deb_path="/tmp/${ms_repo_deb}"
    if ! wget --timeout=30 --tries=3 "$ms_repo_url" -O "$temp_deb_path"; then
        _log_warning "下载 Microsoft 仓库配置文件失败 (URL: ${ms_repo_url})。"
        rm -f "$temp_deb_path"
        return 1
    fi

    _log_info "正在配置 Microsoft 仓库..."
    if dpkg -i "$temp_deb_path"; then
        rm -f "$temp_deb_path"
    else
        _log_error "配置 Microsoft 仓库失败 (dpkg -i ${temp_deb_path})。"
        rm -f "$temp_deb_path"
        rm -f "/etc/apt/sources.list.d/microsoft-prod.list"
        return 1
    fi

    _run_apt_update
    local ms_openjdk_pkg="msopenjdk-${DEFAULT_JAVA_VERSION}"
    _log_info "正在安装 ${COLOR_YELLOW}${ms_openjdk_pkg}${COLOR_RESET}..."
    if ! _install_apt_packages "$ms_openjdk_pkg"; then
        _log_error "安装 ${ms_openjdk_pkg} 失败。"
        rm -f "/etc/apt/sources.list.d/microsoft-prod.list"
        apt update || _log_warning "移除 Microsoft 仓库后 apt update 失败。"
        return 1
    fi

    _log_success "[5] Java (Microsoft OpenJDK ${COLOR_YELLOW}${DEFAULT_JAVA_VERSION}${COLOR_RESET}) 安装完成。"
    if command -v java &> /dev/null; then
         local java_version=$(java -version 2>&1 | head -n 1 || echo "未知")
         _log_info "   - Java 版本: ${COLOR_GREEN}${java_version}${COLOR_RESET}"
    else
         _log_warning "Java 命令 (java) 未在当前 PATH 找到。"
    fi
    return 0
}

# --- 6: 安装 Node.js ---
_install_nodejs() {
    local version_spec="$1"
    local node_install_version=""

    _log_info "[6] 开始安装 Node.js (通过 NodeSource)..."
    if [[ "$g_non_interactive" == false ]]; then
        _log_info "${COLOR_DIM}提示: 如需管理多个 Node.js 版本，请考虑使用 nvm (菜单选项 11)。${COLOR_RESET}"
    fi

    if [[ "$g_non_interactive" == true ]]; then
        if [[ "$version_spec" == "lts" ]]; then
            node_install_version="${DEFAULT_NODE_LTS_MAJOR_VERSION}"
        elif [[ "$version_spec" == "latest" ]]; then
            node_install_version="${DEFAULT_NODE_LATEST_MAJOR_VERSION}"
        elif [[ "$version_spec" =~ ^[0-9]+$ ]]; then
            node_install_version="$version_spec"
        elif [[ -z "$version_spec" ]]; then
            _log_warning "[6] 非交互模式下未指定 Node.js 版本，默认使用 LTS (${DEFAULT_NODE_LTS_MAJOR_VERSION})。"
            node_install_version="${DEFAULT_NODE_LTS_MAJOR_VERSION}"
        else
            _log_error "[6] 无效的 Node.js 版本参数 '${COLOR_YELLOW}${version_spec}${COLOR_RESET}'。请使用 'lts', 'latest', 或主版本号。"
            return 1
        fi
    else
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        echo -e " ${COLOR_BOLD}请选择要安装的 Node.js 版本 (通过 NodeSource)${COLOR_RESET}"
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        echo "  [1] LTS (${COLOR_GREEN}推荐${COLOR_RESET}, ${DEFAULT_NODE_LTS_MAJOR_VERSION}.x)"
        echo "  [2] 最新版 (Current, ${DEFAULT_NODE_LATEST_MAJOR_VERSION}.x)"
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        local node_choice
        _read_prompt "请输入选项" node_choice "1"
        case "$node_choice" in
            2) node_install_version="${DEFAULT_NODE_LATEST_MAJOR_VERSION}" ;;
            1 | *) node_install_version="${DEFAULT_NODE_LTS_MAJOR_VERSION}" ;;
        esac
    fi

    local node_setup_suffix="${node_install_version}.x"
    _log_info "选择安装 Node.js v${COLOR_YELLOW}${node_setup_suffix}${COLOR_RESET}"

    if ! command -v curl &> /dev/null; then
        _log_info "安装 Node.js 需要 curl，正在安装..."
        if ! _install_apt_packages curl; then
            _log_error "安装 curl 失败。"
            return 1
        fi
    fi

    _log_info "正在设置 NodeSource 仓库 (Node.js v${node_setup_suffix})..."
    local nodesource_url="https://deb.nodesource.com/setup_${node_setup_suffix}"
    if ! curl -fsSL "$nodesource_url" | bash - ; then
        _log_error "设置 NodeSource 仓库失败 (URL: ${nodesource_url})。"
        rm -f /etc/apt/sources.list.d/nodesource.list
        return 1
    fi

    _log_info "正在安装 Node.js..."
    if ! _install_apt_packages nodejs; then
        _log_error "安装 nodejs 失败。"
        rm -f /etc/apt/sources.list.d/nodesource.list
        apt update || _log_warning "移除 NodeSource 仓库后 apt update 失败。"
        return 1
    fi

    _log_success "[6] Node.js (NodeSource v${node_setup_suffix}) 安装完成。"
    local node_version=$(node -v 2>/dev/null || echo "未知")
    local npm_version=$(npm -v 2>/dev/null || echo "未知")
    _log_info "   - Node 版本: ${COLOR_GREEN}${node_version}${COLOR_RESET}"
    _log_info "   - npm 版本: ${COLOR_GREEN}${npm_version}${COLOR_RESET}"
    return 0
}

# --- 7: 安装 Rust ---
_install_rust() {
    _log_info "[7] 开始安装 Rust (通过官方 rustup)..."
    _log_warning "Rustup 会将 Rust 安装在用户 '${COLOR_YELLOW}${CURRENT_USER}${COLOR_RESET}' 的主目录 (${COLOR_YELLOW}${CURRENT_HOME}/.cargo${COLOR_RESET}) 下。"
    _log_warning "安装完成后，您需要运行 '${COLOR_CYAN}source \"\$HOME/.cargo/env\"${COLOR_RESET}' 或重新登录/打开新终端才能使用。"

    if ! command -v curl &> /dev/null; then
        _log_info "安装 Rust 需要 curl，正在安装..."
        if ! _install_apt_packages curl; then
            _log_error "安装 curl 失败。"
            return 1
        fi
    fi

    local rustup_script_path
    rustup_script_path=$(mktemp) || { _log_error "无法创建临时文件用于 rustup 脚本。"; return 1; }

    _log_info "正在下载 rustup 安装脚本..."
    if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$rustup_script_path"; then
        _log_error "下载 rustup 脚本失败。"
        rm -f "$rustup_script_path"
        return 1
    fi

    _log_info "正在以用户 '${COLOR_YELLOW}${CURRENT_USER}${COLOR_RESET}' 的身份运行 rustup 安装脚本 (非交互式)..."
    chown "$CURRENT_USER" "$rustup_script_path" || _log_warning "无法更改 rustup 脚本的所有者为 ${CURRENT_USER}。"
    if ! sudo -u "$CURRENT_USER" sh "$rustup_script_path" -y; then
        _log_warning "Rustup 安装脚本执行失败或被中断。"
        rm -f "$rustup_script_path"
        return 1
    fi
    rm -f "$rustup_script_path"

    local bashrc_path="${CURRENT_HOME}/.bashrc"
    local cargo_env_line="source \"\$HOME/.cargo/env\""
    if [[ -f "$bashrc_path" ]]; then
        if ! grep -qF -- "$cargo_env_line" "$bashrc_path"; then
            _log_info "尝试将 Rust 环境变量配置添加到 ${COLOR_YELLOW}${bashrc_path}${COLOR_RESET} ..."
            if echo "$cargo_env_line" | sudo -u "$CURRENT_USER" tee -a "$bashrc_path" > /dev/null; then
                 _log_success "已添加。请运行 '${COLOR_CYAN}source ${bashrc_path}${COLOR_RESET}' 或重新登录以使 Rust 生效。"
            else
                 _log_warning "无法自动将 Rust 环境变量添加到 ${bashrc_path}。"
                 _log_warning "请手动添加以下行到您的 shell 配置文件 (${bashrc_path} 或 .zshrc 等):"
                 _log_warning "  ${COLOR_CYAN}${cargo_env_line}${COLOR_RESET}"
            fi
        else
             _log_info "Rust 环境变量配置已存在于 ${bashrc_path}。"
        fi
    else
        _log_warning "未找到 ${bashrc_path} 文件。"
        _log_warning "请手动添加以下行到您的 shell 配置文件:"
        _log_warning "  ${COLOR_CYAN}${cargo_env_line}${COLOR_RESET}"
    fi

    _log_success "[7] Rust (rustup) 安装完成 (${COLOR_YELLOW}需要更新环境才能使用${COLOR_RESET})。"
    g_rust_installed=true
    return 0
}

# --- 8: 安装 Ruby ---
_install_ruby() {
    local install_type="$1"

    if [[ "$g_non_interactive" == true ]]; then
        if [[ "$install_type" == "apt" ]]; then
            _log_info "[8] 开始安装 Ruby (apt)..."
            if ! _install_apt_packages ruby-full ruby-dev; then
                 _log_error "Ruby (apt) 安装失败。"
                 return 1
            fi
            _log_success "[8] Ruby (apt) 安装完成。"
        else
            _log_warning "[8] 非交互模式下 Ruby 只支持 'apt' 参数，跳过。"
            return 0
        fi
    else
        local install_apt_ruby
        _read_prompt "是否安装 apt 源提供的 Ruby 版本 (ruby-full, 可能不是最新版)? (Y/n)" install_apt_ruby "Y"
        if [[ "$install_apt_ruby" =~ ^[Yy]$ ]]; then
            _log_info "[8] 开始安装 Ruby (apt)..."
            if ! _install_apt_packages ruby-full ruby-dev; then
                 _log_error "Ruby (apt) 安装失败。"
                 return 1
            fi
            _log_success "[8] Ruby (apt) 安装完成。"
        else
            _show_version_manager_info "Ruby"
            return 0
        fi
    fi

    if command -v ruby &> /dev/null; then
        local ruby_version=$(ruby --version 2>/dev/null || echo "未知")
        _log_info "   - Ruby 版本: ${COLOR_GREEN}${ruby_version}${COLOR_RESET}"
    else
        _log_warning "Ruby 命令 (ruby) 未在当前 PATH 找到。"
    fi
    return 0
}

# --- 9: 安装 PHP ---
_install_php() {
    _log_info "[9] 开始安装 PHP 及常用扩展..."
    local add_ondrej_ppa=false

    if [[ "$OS_ID" == "ubuntu" ]] && [[ "$g_php_no_ppa" == false ]]; then
        if [[ "$g_non_interactive" == true ]]; then
            _log_info "检测到 Ubuntu，尝试添加 Ondrej PPA (使用 --no-ppa 禁用)..."
            add_ondrej_ppa=true
        else
            local ppa_choice
            _read_prompt "检测到 Ubuntu 系统，是否尝试添加 Ondrej PPA 以获取更新的 PHP 版本? (y/N)" ppa_choice "N"
            if [[ "$ppa_choice" =~ ^[Yy]$ ]]; then
                add_ondrej_ppa=true
            fi
        fi
    elif [[ "$OS_ID" == "ubuntu" ]] && [[ "$g_php_no_ppa" == true ]]; then
         _log_info "根据 --no-ppa 参数，不添加 Ondrej PPA。"
    fi

    if [[ "$add_ondrej_ppa" == true ]]; then
        _log_info "正在添加 ${COLOR_YELLOW}ppa:ondrej/php${COLOR_RESET} ..."
        if ! _install_apt_packages software-properties-common; then
             _log_warning "安装 PPA 依赖 software-properties-common 失败，无法添加 PPA。"
             add_ondrej_ppa=false
        else
            if ! add-apt-repository -y ppa:ondrej/php; then
                _log_warning "添加 Ondrej PPA 失败，将尝试安装系统默认 PHP 版本。"
                rm -f /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list
                add_ondrej_ppa=false
            else
                _run_apt_update
            fi
        fi
    fi

    _log_info "正在安装 PHP (php, php-cli) 及常用扩展 (mbstring, xml, curl, zip, mysql)..."
    local php_packages="php php-cli php-common php-dev php-mbstring php-xml php-curl php-zip php-mysql"
    if ! _install_apt_packages ${php_packages}; then
        _log_error "安装 PHP 软件包失败。"
        if [[ "$add_ondrej_ppa" == true ]]; then
             _log_warning "PHP 安装失败，可能与 Ondrej PPA 有关。考虑移除 PPA 并重试。"
        fi
        return 1
    fi

    _log_success "[9] PHP 安装完成。"
    if command -v php &> /dev/null; then
        local php_version=$(php --version | head -n 1 2>/dev/null || echo "未知")
        _log_info "   - PHP 版本: ${COLOR_GREEN}${php_version}${COLOR_RESET}"
    else
         _log_warning "PHP 命令 (php) 未在当前 PATH 找到。"
    fi
    return 0
}

# --- 10: 安装 Docker CE ---
_install_docker() {
    _log_info "[10] 开始安装 Docker CE (社区版)..."

    _log_info "正在安装 Docker 依赖 (ca-certificates, curl, gnupg, lsb-release)..."
    if ! _install_apt_packages ca-certificates curl gnupg lsb-release; then
        _log_error "安装 Docker 依赖失败。"
        return 1
    fi

    _log_info "正在添加 Docker 官方 GPG 密钥..."
    local keyrings_dir="/etc/apt/keyrings"
    install -m 0755 -d "$keyrings_dir" || { _log_error "无法创建目录 ${keyrings_dir}"; return 1; }
    local docker_gpg_key="${keyrings_dir}/docker.asc"
    if ! curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" -o "$docker_gpg_key"; then
         _log_error "下载 Docker GPG 密钥失败。"
         rm -f "$docker_gpg_key"
         return 1
    fi
    chmod a+r "$docker_gpg_key" || _log_warning "无法设置 Docker GPG 密钥 (${docker_gpg_key}) 的读取权限。"

    _log_info "正在添加 Docker apt 仓库..."
    local docker_repo_list="/etc/apt/sources.list.d/docker.list"
    local arch=$(dpkg --print-architecture)
    local codename=$(lsb_release -cs)
    echo "deb [arch=${arch} signed-by=${docker_gpg_key}] https://download.docker.com/linux/${OS_ID} ${codename} stable" | tee "$docker_repo_list" > /dev/null \
        || { _log_error "无法写入 Docker apt 仓库配置 (${docker_repo_list})。"; return 1; }

    _run_apt_update
    _log_info "正在安装 Docker Engine (docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin)..."
    local docker_packages="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    if ! _install_apt_packages ${docker_packages}; then
        _log_error "安装 Docker Engine 失败。"
        rm -f "$docker_repo_list"; rm -f "$docker_gpg_key"
        apt update || _log_warning "移除 Docker 仓库配置后 apt update 失败。"
        return 1
    fi

    _log_success "[10] Docker CE 安装完成。"

    _log_info "正在尝试将用户 '${COLOR_YELLOW}${CURRENT_USER}${COLOR_RESET}' 添加到 'docker' 组..."
    if ! getent group docker > /dev/null; then
        _log_warning "Docker 组不存在，尝试创建..."
        groupadd docker || _log_warning "创建 docker 组失败。"
    fi
    if usermod -aG docker "$CURRENT_USER"; then
        _log_success "用户 '${COLOR_YELLOW}${CURRENT_USER}${COLOR_RESET}' 已添加到 docker 组。"
        _log_warning "为了使组权限生效，您需要 ${COLOR_YELLOW}重新登录${COLOR_RESET}，或运行 '${COLOR_CYAN}newgrp docker${COLOR_RESET}' 命令。"
    else
        _log_warning "将用户 '${CURRENT_USER}' 添加到 docker 组失败。您可能需要手动执行 'sudo usermod -aG docker ${CURRENT_USER}'。"
    fi

    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version 2>/dev/null || echo "未知")
        _log_info "   - Docker 版本: ${COLOR_GREEN}${docker_version}${COLOR_RESET}"
    else
        _log_warning "Docker 命令 (docker) 未在当前 PATH 找到。"
    fi

    g_docker_installed=true
    return 0
}

# --- 11: 安装 nvm (Node Version Manager) ---
_install_nvm() {
    _log_info "[11] 开始安装 nvm (Node Version Manager) for user '${COLOR_YELLOW}${CURRENT_USER}${COLOR_RESET}'..."
    _log_warning "nvm 会安装到用户 '${COLOR_YELLOW}${CURRENT_USER}${COLOR_RESET}' 的主目录 (${COLOR_YELLOW}${CURRENT_HOME}/.nvm${COLOR_RESET}) 下。"
    _log_warning "安装完成后，您需要关闭当前终端并重新打开，或运行 '${COLOR_CYAN}source ${CURRENT_HOME}/.bashrc${COLOR_RESET}' (或 .zshrc 等) 来加载 nvm。"

    local downloader=""
    if command -v curl &> /dev/null; then
        downloader="curl"
    elif command -v wget &> /dev/null; then
        downloader="wget"
    else
        _log_info "安装 nvm 需要 curl 或 wget，正在尝试安装 curl..."
        if ! _install_apt_packages curl; then
            _log_error "安装 curl 失败，无法继续安装 nvm。"
            return 1
        fi
        downloader="curl"
    fi

    _log_info "正在下载并执行 nvm v${COLOR_YELLOW}${NVM_VERSION}${COLOR_RESET} 安装脚本..."
    local install_cmd=""
    local nvm_install_url="https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh"
    if [[ "$downloader" == "curl" ]]; then
        install_cmd="curl -o- ${nvm_install_url} | bash"
    else # wget
        install_cmd="wget -qO- ${nvm_install_url} | bash"
    fi

    if sudo -u "$CURRENT_USER" bash -c "$install_cmd"; then
        _log_success "nvm 安装脚本执行成功。"
        _log_info "${COLOR_YELLOW}nvm 用法示例:${COLOR_RESET}"
        echo -e "  ${COLOR_CYAN}nvm install node${COLOR_RESET}       # 安装最新 Node 版本"
        echo -e "  ${COLOR_CYAN}nvm install --lts${COLOR_RESET}      # 安装最新 LTS 版本"
        echo -e "  ${COLOR_CYAN}nvm install <version>${COLOR_RESET}  # 安装指定版本 (e.g., nvm install 18.17.1)"
        echo -e "  ${COLOR_CYAN}nvm use <version>${COLOR_RESET}      # 切换到指定版本"
        echo -e "  ${COLOR_CYAN}nvm ls${COLOR_RESET}                 # 列出已安装版本"
        echo -e "  ${COLOR_CYAN}nvm ls-remote${COLOR_RESET}          # 列出可远程安装的版本"
        g_nvm_installed=true
        return 0
    else
        _log_error "nvm 安装脚本执行失败。"
        return 1
    fi
}

# --- 12: 更换 APT 软件源 ---
_change_apt_source() {
    local source_location="$1"

    _log_info "[12] 开始更换 APT 软件源..."

    if ! command -v curl &> /dev/null; then
        _log_info "更换软件源需要 curl，正在尝试安装..."
        if ! _install_apt_packages curl; then
            _log_error "安装 curl 失败，无法继续更换软件源。"
            return 1
        fi
    fi

    local target_script_args=""
    local choice_desc=""

    if [[ "$g_non_interactive" == true ]]; then
        if [[ "$source_location" == "cn" ]]; then
            target_script_args=""
            choice_desc="中国大陆镜像源"
        elif [[ "$source_location" == "abroad" ]]; then
            target_script_args="--abroad"
            choice_desc="国际官方源"
        elif [[ -z "$source_location" ]]; then
             _log_warning "[12] 非交互模式下未指定源位置 (cn 或 abroad)，跳过换源。"
             return 0
        else
            _log_error "[12] 无效的源位置参数 '${COLOR_YELLOW}${source_location}${COLOR_RESET}'。请使用 'cn' 或 'abroad'。"
            return 1
        fi
        _log_info "非交互模式选择: ${COLOR_YELLOW}${choice_desc}${COLOR_RESET}"

    else
        clear
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        echo -e " ${COLOR_BOLD}请选择要使用的 APT 软件源:${COLOR_RESET}"
        echo -e " ${COLOR_DIM}(当默认源下载速度慢时建议更换)${COLOR_RESET}"
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        echo "  1) 中国大陆镜像源 (${COLOR_GREEN}推荐中国大陆用户${COLOR_RESET})"
        echo "  2) 国际官方源"
        echo "  0) ${COLOR_YELLOW}取消更换${COLOR_RESET}"
        echo -e "${COLOR_MAGENTA}----------------------------------${COLOR_RESET}"
        local source_choice
        _read_prompt "请输入选项" source_choice "0"

        case "$source_choice" in
            1)
                target_script_args=""
                choice_desc="中国大陆镜像源"
                _log_info "选择: ${COLOR_YELLOW}${choice_desc}${COLOR_RESET}"
                ;;
            2)
                target_script_args="--abroad"
                choice_desc="国际官方源"
                _log_info "选择: ${COLOR_YELLOW}${choice_desc}${COLOR_RESET}"
                ;;
            0)
                _log_info "用户取消更换软件源。"
                return 0
                ;;
            *)
                _log_warning "[12] 无效的选择，跳过更换软件源。"
                return 0
                ;;
        esac
    fi

    local change_source_cmd="bash <(curl -sSL https://linuxmirrors.cn/main.sh) ${target_script_args}"
    _log_info "准备执行换源命令: ${COLOR_CYAN}${change_source_cmd}${COLOR_RESET}"
    _log_warning "即将执行来自 ${COLOR_YELLOW}linuxmirrors.cn${COLOR_RESET} 的外部脚本来修改您的 APT 源配置。"
    _log_warning "请确保您信任该来源。按 Enter 继续，按 ${COLOR_RED}Ctrl+C${COLOR_RESET} 取消。"
    read -r

    _log_info "正在执行换源脚本..."
    if eval "$change_source_cmd"; then
        _log_success "[12] 软件源更换脚本执行成功。"
        _log_warning "软件源已更换为 ${COLOR_YELLOW}${choice_desc}${COLOR_RESET}。"
        _log_warning "强烈建议在所有安装任务完成后手动运行 '${COLOR_CYAN}sudo apt update && sudo apt upgrade${COLOR_RESET}' 来应用更改并更新系统。"
        g_source_changed=true
        return 0
    else
        _log_error "[12] 软件源更换脚本执行失败。"
        _log_warning "您的软件源配置可能处于不一致状态，请检查 /etc/apt/sources.list 及 /etc/apt/sources.list.d/ 目录下的文件。"
        return 1
    fi
}


# ==============================================================================
# 参数解析 (Argument Parsing)
# ==============================================================================
_parse_arguments() {
    if [[ $# -eq 0 ]]; then
        g_non_interactive=false
        return
    fi

    g_non_interactive=true
    # 在非交互模式下，先不打印禁用颜色的信息，等颜色变量清空后再打印

    declare -gA g_cli_choices=()
    g_php_no_ppa=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --basic-packages) g_cli_choices["basic"]="true"; shift ;;
            --git)            g_cli_choices["git"]="true"; shift ;;
            --c-cpp)          g_cli_choices["c_cpp"]="true"; shift ;;
            --python)
                if [[ -z "$2" || "$2" == --* ]]; then _log_error "--python 需要一个参数 ('apt' 或版本号 X.Y.Z)"; fi
                g_cli_choices["python"]="$2"; shift 2 ;;
            --go)
                if [[ -z "$2" || "$2" == --* ]]; then _log_error "--go 需要一个参数 ('apt' 或 'manual'/'latest')"; fi
                if [[ "$2" != "apt" && "$2" != "manual" && "$2" != "latest" ]]; then _log_error "无效的 --go 参数 '$2'。请使用 'apt' 或 'manual'/'latest'。"; fi
                g_cli_choices["go"]="$2"; shift 2 ;;
            --java)           g_cli_choices["java"]="true"; shift ;;
            --node)
                if [[ -z "$2" || "$2" == --* ]]; then _log_error "--node 需要一个参数 ('lts', 'latest', 或主版本号)"; fi
                g_cli_choices["node"]="$2"; shift 2 ;;
            --rust)           g_cli_choices["rust"]="true"; shift ;;
            --ruby)
                 if [[ -z "$2" || "$2" != "apt" ]]; then _log_error "--ruby 目前仅支持 'apt' 参数"; fi
                 g_cli_choices["ruby"]="$2"; shift 2 ;;
            --php)            g_cli_choices["php"]="true"; shift ;;
            --no-ppa)         g_php_no_ppa=true; shift ;;
            --docker)         g_cli_choices["docker"]="true"; shift ;;
            --nvm)            g_cli_choices["nvm"]="true"; shift ;;
            --change-source)
                if [[ -z "$2" || "$2" == --* ]]; then _log_error "--change-source 需要一个参数 ('cn' 或 'abroad')"; fi
                if [[ "$2" != "cn" && "$2" != "abroad" ]]; then _log_error "无效的 --change-source 参数 '$2'。请使用 'cn' 或 'abroad'。"; fi
                g_cli_choices["change_source"]="$2"; shift 2 ;;
            --all)
                _log_info "选择 --all，将安装所有常用工具（使用默认推荐设置）..."
                g_cli_choices=(
                    ["basic"]="true" ["git"]="true" ["c_cpp"]="true" ["python"]="apt"
                    ["go"]="manual" ["java"]="true" ["node"]="lts" ["rust"]="true"
                    ["ruby"]="apt" ["php"]="true" ["docker"]="true" ["nvm"]="true"
                )
                shift ;;
            --help)           _show_help ;;
            *)                _log_error "未知选项: $1. 使用 --help 查看帮助。" ;;
        esac
    done

    if [[ ${#g_cli_choices[@]} -eq 0 ]] && [[ "$g_php_no_ppa" == false ]]; then
         _log_warning "没有指定任何有效的安装选项。使用 --help 查看可用选项。"
         exit 0
    fi
}

# ==============================================================================
# 初始化检查 (Initial Checks)
# ==============================================================================
_initial_checks() {
    if [[ "$(id -u)" -ne 0 ]]; then _log_error "此脚本必须使用 root 权限 (sudo) 运行。"; fi
    if ! command -v apt &> /dev/null; then _log_error "未检测到 'apt' 命令。此脚本仅支持基于 apt 的系统 (如 Debian, Ubuntu)。"; fi

    if [[ -f /etc/os-release ]]; then
        local os_info
        os_info=$(. /etc/os-release && declare -p ID VERSION_ID PRETTY_NAME)
        eval "${os_info}"
        OS_ID="${ID:-unknown}"
        OS_VERSION_ID="${VERSION_ID:-unknown}"
        OS_PRETTY_NAME="${PRETTY_NAME:-Debian/Ubuntu}"
    else
        OS_ID="unknown"; OS_VERSION_ID="unknown"; OS_PRETTY_NAME="Debian/Ubuntu (os-release not found)"
    fi
    # 初始检查时先不带颜色打印，等确定模式后再决定
    echo "[信息] 检测到系统: ${OS_PRETTY_NAME} (ID: ${OS_ID}, Version: ${OS_VERSION_ID})"

    if [[ -z "$CURRENT_USER" || -z "$CURRENT_HOME" ]]; then _log_error "无法确定目标用户 (${CURRENT_USER}) 或其家目录 (${CURRENT_HOME})。"; fi
     echo "[信息] 将为用户 '${CURRENT_USER}' (主目录: ${CURRENT_HOME}) 安装用户级工具 (nvm, rust) 并添加到 docker 组。"

     if ! command -v dpkg &> /dev/null; then _log_error "未检测到 'dpkg' 命令，无法确定系统架构。"; fi
}

# ==============================================================================
# 主逻辑 (Main Logic)
# ==============================================================================
main() {
    # 先执行初始化检查（不带颜色）
    _initial_checks
    # 解析参数，确定是否为非交互模式
    _parse_arguments "$@"

    # --- 如果是非交互模式，则禁用颜色输出 ---
    if [[ "$g_non_interactive" == true ]]; then
        # 清空颜色变量
        COLOR_RESET=''; COLOR_RED=''; COLOR_GREEN=''; COLOR_YELLOW='';
        COLOR_BLUE=''; COLOR_MAGENTA=''; COLOR_CYAN=''; COLOR_BOLD=''; COLOR_DIM='';
        # 现在可以打印带颜色的信息了（虽然颜色变量为空）
        _log_info "非交互模式，禁用颜色输出。"
    else
        # 交互模式下，用颜色重新打印初始信息
        _log_info "检测到系统: ${COLOR_YELLOW}${OS_PRETTY_NAME}${COLOR_RESET} (ID: ${OS_ID}, Version: ${OS_VERSION_ID})"
        _log_info "将为用户 '${COLOR_YELLOW}${CURRENT_USER}${COLOR_RESET}' (主目录: ${CURRENT_HOME}) 安装用户级工具 (nvm, rust) 并添加到 docker 组。"
    fi


    # --- 根据模式执行安装 ---
    if [[ "$g_non_interactive" == true ]]; then
        # --- 非交互模式执行 ---
        _log_info "开始执行非交互式安装..."
        local failed_installs=()
        local install_count=0

        declare -A tool_to_function=(
            ["change_source"]="_change_apt_source" ["basic"]="_install_basic_packages"
            ["git"]="_install_git" ["c_cpp"]="_install_c_cpp" ["python"]="_install_python"
            ["go"]="_install_go" ["java"]="_install_java" ["node"]="_install_nodejs"
            ["rust"]="_install_rust" ["ruby"]="_install_ruby" ["php"]="_install_php"
            ["docker"]="_install_docker" ["nvm"]="_install_nvm"
        )
        local ordered_tools=(
            "change_source" "basic" "git" "c_cpp" "python" "go" "java" "node" "rust" "ruby" "php" "docker" "nvm"
        )

        for tool_name in "${ordered_tools[@]}"; do
            if [[ -v g_cli_choices["$tool_name"] ]]; then
                install_count=$((install_count + 1))
                local install_arg="${g_cli_choices[$tool_name]}"
                local install_func="${tool_to_function[$tool_name]}"
                local option_desc="$tool_name"

                if [[ -z "$install_func" ]]; then
                     _log_warning "未找到工具 '${COLOR_YELLOW}${tool_name}${COLOR_RESET}' 对应的安装函数，跳过。"
                     continue
                fi

                echo # 添加空行分隔
                _log_info "${COLOR_MAGENTA}--- [非交互] 开始处理: ${option_desc} (参数: ${install_arg}) ---${COLOR_RESET}"

                local call_arg=""
                if [[ "$install_arg" != "true" ]]; then call_arg="$install_arg"; fi

                if "$install_func" "$call_arg"; then
                    _log_success "${COLOR_MAGENTA}--- [非交互] 完成处理: ${option_desc} ---${COLOR_RESET}"
                else
                    _log_warning "${COLOR_YELLOW}--- [非交互] 处理失败或跳过: ${option_desc} (请查看上面的详细错误信息) ---${COLOR_RESET}"
                    failed_installs+=("$option_desc")
                fi
                echo # 添加空行分隔
            fi
        done

        echo -e "${COLOR_MAGENTA}==================================================${COLOR_RESET}"
        if [[ $install_count -gt 0 ]]; then
            _log_info "非交互式安装任务已执行完毕。"
            if [[ ${#failed_installs[@]} -gt 0 ]]; then
                _log_warning "以下选项处理失败或被跳过:"
                for failed in "${failed_installs[@]}"; do
                    echo -e "  - ${COLOR_YELLOW}$failed${COLOR_RESET}"
                done
            fi
        else
             _log_info "没有执行任何安装任务。"
        fi

    else
        # --- 交互模式执行 ---
        _log_info "进入交互式安装菜单..."

        declare -A menu_options
        declare -A install_functions
        menu_options[0]="基础软件包 (${COLOR_GREEN}推荐首次运行安装${COLOR_RESET})" ; install_functions[0]="_install_basic_packages"
        menu_options[1]="Git"                           ; install_functions[1]="_install_git"
        menu_options[2]="C/C++ 开发工具"                ; install_functions[2]="_install_c_cpp"
        menu_options[3]="Python 3 (${COLOR_DIM}apt/源码编译/跳过${COLOR_RESET})" ; install_functions[3]="_install_python"
        menu_options[4]="Go (Golang) (${COLOR_DIM}apt/官网最新版/跳过${COLOR_RESET})" ; install_functions[4]="_install_go"
        menu_options[5]="Java (Microsoft OpenJDK ${DEFAULT_JAVA_VERSION})" ; install_functions[5]="_install_java"
        menu_options[6]="Node.js (${COLOR_DIM}NodeSource LTS/最新${COLOR_RESET})" ; install_functions[6]="_install_nodejs"
        menu_options[7]="Rust (${COLOR_DIM}官方 rustup${COLOR_RESET})"            ; install_functions[7]="_install_rust"
        menu_options[8]="Ruby (${COLOR_DIM}apt/跳过${COLOR_RESET})"                ; install_functions[8]="_install_ruby"
        menu_options[9]="PHP (${COLOR_DIM}及常用扩展, Ubuntu可选PPA${COLOR_RESET})"; install_functions[9]="_install_php"
        menu_options[10]="Docker CE (${COLOR_DIM}官方源${COLOR_RESET})"           ; install_functions[10]="_install_docker"
        menu_options[11]="安装 nvm (${COLOR_DIM}Node 版本管理器${COLOR_RESET})"     ; install_functions[11]="_install_nvm"
        menu_options[12]="更换 APT 源 (${COLOR_YELLOW}当默认源下载慢时使用${COLOR_RESET})" ; install_functions[12]="_change_apt_source"

        while true; do
            clear
            echo -e "${COLOR_MAGENTA}${COLOR_BOLD}==================================================${COLOR_RESET}"
            echo -e " ${COLOR_BOLD}请选择要安装的开发环境/工具 (交互式菜单)${COLOR_RESET}"
            echo -e " ${COLOR_DIM}项目地址: https://github.com/butlanys/code.sh${COLOR_RESET}"
            echo -e "${COLOR_MAGENTA}${COLOR_BOLD}==================================================${COLOR_RESET}"
            local sorted_keys
            sorted_keys=$(printf "%s\n" "${!menu_options[@]}" | sort -n)
            for i in $sorted_keys; do
                printf "  ${COLOR_YELLOW}%2d)${COLOR_RESET} %s\n" "$i" "$(echo -e "${menu_options[$i]}")"
            done
            echo -e "${COLOR_MAGENTA}--------------------------------------------------${COLOR_RESET}"
            echo "输入选项数字，多个选项用逗号或空格分隔 (例如: 0,1,3 或 0 1 3)"
            echo "输入 'q' 退出"
            echo -e "${COLOR_MAGENTA}==================================================${COLOR_RESET}"
            local user_choices
            _read_prompt "请输入选项" user_choices

            if [[ "$user_choices" =~ ^[Qq]$ ]]; then
                _log_info "用户选择退出。"
                break
            fi

            local sanitized_choices
            sanitized_choices=$(echo "$user_choices" | tr ',' ' ')
            local install_count_this_round=0
            local failed_installs_this_round=()
            g_nvm_installed=false; g_python_compiled=false; g_rust_installed=false
            g_docker_installed=false; g_go_manual_installed=false; g_source_changed=false

            for choice in $sanitized_choices; do
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ -v install_functions[$choice] ]]; then
                    install_count_this_round=$((install_count_this_round + 1))
                    local option_desc="${menu_options[$choice]}"
                    local install_func="${install_functions[$choice]}"

                    echo
                    _log_info "${COLOR_MAGENTA}--- [交互] 开始处理: ${choice}) $(echo -e "$option_desc") ---${COLOR_RESET}"

                    if "$install_func"; then
                        _log_success "${COLOR_MAGENTA}--- [交互] 完成处理: ${choice}) $(echo -e "$option_desc") ---${COLOR_RESET}"
                    else
                        _log_warning "${COLOR_YELLOW}--- [交互] 处理失败或跳过: ${choice}) $(echo -e "$option_desc") (请查看上面的详细信息) ---${COLOR_RESET}"
                        # 记录不带颜色的描述，用于失败总结
                        failed_installs_this_round+=("${choice}) $(echo -e "$option_desc" | sed 's/\x1b\[[0-9;]*m//g')")
                    fi
                    echo
                    local dummy_var
                    _read_prompt "按 Enter 继续下一个选项或返回菜单" dummy_var

                elif [[ -n "$choice" ]]; then
                    _log_warning "无效的选项 '${COLOR_YELLOW}$choice${COLOR_RESET}'，已忽略。"
                fi
            done

            echo -e "${COLOR_MAGENTA}--------------------------------------------------${COLOR_RESET}"
            if [[ $install_count_this_round -gt 0 ]]; then
                _log_info "本次选择的任务已执行完毕。"
                if [[ ${#failed_installs_this_round[@]} -gt 0 ]]; then
                    _log_warning "以下选项处理失败或被跳过:"
                    for failed in "${failed_installs_this_round[@]}"; do
                        echo -e "  - ${COLOR_YELLOW}$failed${COLOR_RESET}"
                    done
                fi
            elif [[ -n "$user_choices" ]]; then
                _log_warning "未执行任何有效安装任务。"
            fi

            local final_warnings_this_round=()
            if [[ "$g_source_changed" == true ]]; then final_warnings_this_round+=("APT 源: 已更换，建议运行 '${COLOR_CYAN}sudo apt update && sudo apt upgrade${COLOR_RESET}'。"); fi
            if [[ "$g_rust_installed" == true ]]; then final_warnings_this_round+=("Rust (需要 '${COLOR_CYAN}source \$HOME/.cargo/env${COLOR_RESET}' 或重开终端)"); fi
            if [[ "$g_docker_installed" == true ]]; then final_warnings_this_round+=("Docker (需要 ${COLOR_YELLOW}重新登录${COLOR_RESET} 或 '${COLOR_CYAN}newgrp docker${COLOR_RESET}')"); fi
            if [[ "$g_nvm_installed" == true ]]; then final_warnings_this_round+=("nvm (需要 '${COLOR_CYAN}source \$HOME/.bashrc${COLOR_RESET}' 或重开终端)"); fi
            if [[ "$g_python_compiled" == true ]]; then final_warnings_this_round+=("编译的 Python (已安装到 ${COLOR_YELLOW}/usr/local/bin/pythonX.Y${COLOR_RESET})"); fi
            if [[ "$g_go_manual_installed" == true ]]; then final_warnings_this_round+=("Go (手动安装): 需要 ${COLOR_YELLOW}重新登录${COLOR_RESET} 或 '${COLOR_CYAN}source /etc/profile.d/go.sh${COLOR_RESET}'"); fi
            if [[ ${#final_warnings_this_round[@]} -gt 0 ]]; then
                 _log_warning "请注意以下工具可能需要额外操作或注意:"
                 for warning in "${final_warnings_this_round[@]}"; do
                     echo -e "  - ${COLOR_YELLOW}$warning${COLOR_RESET}"
                 done
             fi
            echo -e "${COLOR_MAGENTA}--------------------------------------------------${COLOR_RESET}"
            local continue_choice
            _read_prompt "按 Enter 返回菜单，或输入 'q' 退出" continue_choice
            if [[ "$continue_choice" =~ ^[Qq]$ ]]; then
                _log_info "用户选择退出。"
                break
            fi
        done
    fi

    # --- 脚本结束前的最终总结 (适用于所有模式) ---
     echo -e "${COLOR_MAGENTA}${COLOR_BOLD}==================================================${COLOR_RESET}"
     local final_warnings=()
     if [[ "$g_source_changed" == true ]]; then final_warnings+=("APT 源: 已更换，建议运行 '${COLOR_CYAN}sudo apt update && sudo apt upgrade${COLOR_RESET}'。"); fi
     if [[ "$g_rust_installed" == true ]]; then final_warnings+=("Rust: 需要 '${COLOR_CYAN}source \$HOME/.cargo/env${COLOR_RESET}' 或重开终端才能使用 cargo/rustc。"); fi
     if [[ "$g_docker_installed" == true ]]; then final_warnings+=("Docker: 需要 ${COLOR_YELLOW}重新登录${COLOR_RESET} 或运行 '${COLOR_CYAN}newgrp docker${COLOR_RESET}' 才能免 sudo 使用 docker 命令。"); fi
     if [[ "$g_nvm_installed" == true ]]; then final_warnings+=("nvm: 需要关闭当前终端并重新打开，或运行 '${COLOR_CYAN}source ${CURRENT_HOME}/.bashrc${COLOR_RESET}' (或 .zshrc) 才能使用 nvm 命令。"); fi
     if [[ "$g_python_compiled" == true ]]; then final_warnings+=("编译的 Python: 已安装到 ${COLOR_YELLOW}/usr/local/bin/pythonX.Y${COLOR_RESET}，使用时需指定完整路径或配置 PATH/别名。"); fi
     if [[ "$g_go_manual_installed" == true ]]; then final_warnings+=("Go (手动安装): 需要 ${COLOR_YELLOW}重新登录${COLOR_RESET} 或运行 '${COLOR_CYAN}source /etc/profile.d/go.sh${COLOR_RESET}' 才能直接使用 go 命令。"); fi

     if [[ ${#final_warnings[@]} -gt 0 ]]; then
         _log_warning "${COLOR_BOLD}重要提示 (请务必阅读):${COLOR_RESET}"
         for warning in "${final_warnings[@]}"; do
             echo -e "  - ${COLOR_YELLOW}$warning${COLOR_RESET}"
         done
         echo -e "${COLOR_MAGENTA}--------------------------------------------------${COLOR_RESET}"
     fi

    _log_success "脚本执行结束。"
    echo -e "${COLOR_MAGENTA}${COLOR_BOLD}==================================================${COLOR_RESET}"
    exit 0
}

# --- 脚本入口 ---
main "$@"
