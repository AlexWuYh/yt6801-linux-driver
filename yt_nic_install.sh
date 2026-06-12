#!/usr/bin/env bash
#
# Motorcomm YT6801 PCIe 千兆网卡 Linux 内核驱动 —— 一键安装/卸载脚本
#
# 项目主页:  https://github.com/AlexWuYh/yt6801-linux-driver
# 许可证:    MIT
# 适用系统:  Linux(在 macOS/BSD 上运行会被拒绝)
#
# 项目结构(适配本仓库的当前布局):
#   .
#   ├── Makefile
#   ├── src/                  # 驱动源码
#   │   ├── fuxi-*.c / .h
#   │   ├── dkms.conf
#   │   └── motorcomm         # initramfs hook(Kylin 系统使用)
#   └── yt_nic_install.sh
#
# 权限:  install / uninstall / reload 子命令需要 root 权限(写入 /lib/modules、
#        加载/卸载内核模块、配置 /etc/modules-load.d 等)。脚本会自动调用 sudo,
#        也可以直接以 root 身份运行:
#            sudo ./yt_nic_install.sh           # 或
#            su -c './yt_nic_install.sh'        # 切换到 root 后
#        仅有 status / help 子命令不需要 root 权限。
#
# 用法:
#   ./yt_nic_install.sh                # 安装驱动(默认,需 root)
#   ./yt_nic_install.sh install        # 等价于不带参数
#   ./yt_nic_install.sh uninstall      # 卸载驱动(需 root)
#   ./yt_nic_install.sh reload         # 重新加载驱动(需 root)
#   ./yt_nic_install.sh status         # 查看驱动加载/网卡状态(无需 root)
#   ./yt_nic_install.sh help           # 显示帮助(无需 root)
#

set -u
# 注意:故意不开 set -e —— 我们要捕获每一步的返回值并给出友好提示,
# 而不是在第一步失败时就直接退出而看不到上下文。

# ============================================================
# 常量
# ============================================================
SCRIPT_NAME="$(basename "$0")"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_PATH}"

DRIVER_NAME="yt6801"
KO_FILE="${DRIVER_NAME}.ko"
SRC_DIR="${PROJECT_ROOT}/src"
MAKEFILE="${PROJECT_ROOT}/Makefile"

KVER="$(uname -r)"
KDIR_MOD="/lib/modules/${KVER}"
KDIR_BUILD="${KDIR_MOD}/build"
MOD_INSTALL_DIR="${KDIR_MOD}/kernel/drivers/net/ethernet/motorcomm/yt6801"
MOD_INSTALL_KO="${MOD_INSTALL_DIR}/${KO_FILE}"

# 开机自启相关(systemd 标准的 modules-load.d 目录)
AUTOLOAD_DIR="/etc/modules-load.d"
AUTOLOAD_FILE="${AUTOLOAD_DIR}/yt6801.conf"

# ============================================================
# 颜色 —— 仅当 stdout 是终端时启用
# ============================================================
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
    C_RED='\033[31m'
    C_GREEN='\033[32m'
    C_YELLOW='\033[33m'
    C_BLUE='\033[34m'
    C_MAGENTA='\033[35m'
    C_CYAN='\033[36m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_RESET='\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
    C_MAGENTA=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_RESET=''
fi

# ============================================================
# 日志函数
# ============================================================
# 顶层 banner
print_banner() {
    printf "${C_BOLD}${C_CYAN}"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║        Motorcomm YT6801 PCIe Gigabit Ethernet Driver            ║
║                     Linux  ·  Build & Install                   ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    printf "${C_RESET}\n"
}

log_step() {
    printf "\n${C_BOLD}${C_MAGENTA}┌──[ %s ]${C_RESET}\n" "$*"
}

log_info()  { printf "  ${C_BLUE}>>>${C_RESET}  %s\n" "$*"; }
log_ok()    { printf "  ${C_GREEN} ✓ ${C_RESET}  %s\n" "$*"; }
log_warn()  { printf "  ${C_YELLOW} ⚠ ${C_RESET}  %s\n" "$*"; }
log_err()   { printf "  ${C_RED} ✗ ${C_RESET}  %s\n" "$*" >&2; }
log_cmd()   { printf "    ${C_DIM}$ %s${C_RESET}\n"  "$*"; }
log_dim()   { printf "    ${C_DIM}%s${C_RESET}\n"    "$*"; }

# 用法
usage() {
    cat <<EOF
${C_BOLD}用法:${C_RESET}
    ${C_GREEN}./${SCRIPT_NAME}${C_RESET} [${C_CYAN}install${C_RESET} | ${C_CYAN}uninstall${C_RESET} | ${C_CYAN}reload${C_RESET} | ${C_CYAN}status${C_RESET} | ${C_CYAN}help${C_RESET}]

${C_BOLD}子命令:${C_RESET}
    ${C_CYAN}install${C_RESET}      编译、安装、加载驱动,并配置开机自启 (默认)
    ${C_CYAN}uninstall${C_RESET}    卸载驱动模块、清理安装文件、移除开机自启
    ${C_CYAN}reload${C_RESET}       重新加载驱动(先 rmmod 再 insmod)
    ${C_CYAN}status${C_RESET}       显示驱动加载/开机自启/网卡状态
    ${C_CYAN}help${C_RESET}         显示本帮助信息

${C_BOLD}环境要求:${C_RESET}
    - Linux 内核(本脚本仅在 Linux 下有意义,macOS/BSD 会直接拒绝)
    - gcc、make、内核头文件(对应 $(uname -r))
    - install / insmod / rmmod / modules-load.d 阶段需要 root 权限(脚本会自动用 sudo)

${C_BOLD}示例:${C_RESET}
    ${C_DIM}# 一键安装(自动写入开机自启配置)${C_RESET}
    ./${SCRIPT_NAME}

    ${C_DIM}# 查看驱动/自启/网卡状态${C_RESET}
    ./${SCRIPT_NAME} status

    ${C_DIM}# 彻底卸载(同时移除开机自启)${C_RESET}
    ./${SCRIPT_NAME} uninstall
EOF
}

# ============================================================
# 工具函数
# ============================================================

# 决定后续是否需要给命令加 sudo
SUDO=""
setup_sudo() {
    if [[ $EUID -eq 0 ]]; then
        SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        log_err "本步骤需要 root 权限,但系统未安装 sudo。请以 root 用户执行本脚本。"
        exit 1
    fi
}

# 运行一条命令,实时打印其输出,最后报告成功/失败
# $1: 描述; $@: 命令及其参数
run_cmd() {
    local desc="$1"
    local rc=0
    shift
    log_cmd "$*"
    if "$@"; then
        log_ok "${desc}"
        return 0
    fi
    rc=$?
    log_err "${desc}  (退出码: ${rc})"
    return $rc
}

# 同 run_cmd,但通过 sudo 执行
run_sudo() {
    local desc="$1"; shift
    run_cmd "${desc}" ${SUDO} "$@"
}

# 询问用户 yes/no
ask_yn() {
    local prompt="$1" ans
    printf "  ${C_YELLOW}?${C_RESET}  %s [y/N] " "${prompt}"
    read -rsn1 ans
    printf "\n"
    [[ "${ans}" =~ ^[Yy]$ ]]
}

# Linux 平台检查
check_linux() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        log_err "本脚本仅支持 Linux 平台,当前系统: $(uname -s)"
        log_info "如果你想在 macOS/BSD 上查看代码或交叉编译,请手动阅读 Makefile。"
        exit 1
    fi
}

# 检测当前系统是否为麒麟(Kylin)系列
is_kylin() {
    [[ -f /etc/kylin-release ]] || { [[ -r /etc/os-release ]] && grep -qi "kylin" /etc/os-release 2>/dev/null; }
}

# ============================================================
# 预检查
# ============================================================
check_layout() {
    log_info "检查项目结构 ……"
    local ok=1
    if [[ -d "${SRC_DIR}" ]]; then
        log_ok "源码目录: ${SRC_DIR}"
    else
        log_err "未找到源码目录: ${SRC_DIR}"
        ok=0
    fi
    if [[ -f "${MAKEFILE}" ]]; then
        log_ok "顶层 Makefile: ${MAKEFILE}"
    else
        log_err "未找到顶层 Makefile: ${MAKEFILE}"
        ok=0
    fi
    # 至少要有一个 .c 源文件,说明 src/ 没被误删
    if compgen -G "${SRC_DIR}/fuxi-*.c" > /dev/null; then
        log_ok "检测到驱动源文件 (fuxi-*.c)"
    else
        log_err "在 ${SRC_DIR}/ 下未找到 fuxi-*.c 源文件"
        ok=0
    fi
    return $((1 - ok))
}

check_build_deps() {
    log_info "检查编译工具链 ……"
    local ok=1
    local cmd
    for cmd in make gcc; do
        if command -v "${cmd}" >/dev/null 2>&1; then
            local ver
            ver="$(${cmd} --version 2>/dev/null | head -n1)"
            log_ok "${cmd} 可用 —— ${ver}"
        else
            log_err "未找到 ${cmd},请先安装(参见 README 的『依赖安装』章节)"
            ok=0
        fi
    done
    return $((1 - ok))
}

check_kernel_headers() {
    log_info "检查内核头文件 (${KVER}) ……"
    if [[ -d "${KDIR_BUILD}" ]] && [[ -f "${KDIR_BUILD}/Makefile" ]]; then
        log_ok "内核构建目录存在: ${KDIR_BUILD}"
        return 0
    fi
    log_err "未找到内核构建目录: ${KDIR_BUILD}"
    log_dim "请安装与当前内核版本匹配的头文件,例如:"
    log_dim "  Debian/Ubuntu : sudo apt install linux-headers-${KVER}"
    log_dim "  RHEL/CentOS   : sudo dnf install kernel-devel-${KVER}  kernel-headers-${KVER}"
    log_dim "  Arch          : sudo pacman -S linux-headers"
    log_dim "  openSUSE      : sudo zypper install kernel-devel"
    return 1
}

# ============================================================
# 动作:安装
# ============================================================
# 配置开机自动加载: 写入 /etc/modules-load.d/yt6801.conf
# (Kylin 系统额外重建 initramfs,让驱动在启动早期阶段可用)
setup_autoload() {
    setup_sudo
    if ! [[ -d "${AUTOLOAD_DIR}" ]]; then
        run_sudo "创建目录 ${AUTOLOAD_DIR}" install -d -m 755 "${AUTOLOAD_DIR}" || return 1
    fi

    local cur=""
    if [[ -f "${AUTOLOAD_FILE}" ]]; then
        cur="$(${SUDO} cat "${AUTOLOAD_FILE}" 2>/dev/null | tr -d '[:space:]')"
    fi
    if [[ "${cur}" == "yt6801" ]]; then
        log_ok "开机自启配置已就绪: ${AUTOLOAD_FILE}"
    else
        if [[ -f "${AUTOLOAD_FILE}" ]]; then
            log_warn "${AUTOLOAD_FILE} 已有内容,将被覆盖为 'yt6801'"
            log_dim "    当前内容: ${cur:-<空>}"
        fi
        log_cmd "echo yt6801 | ${SUDO} tee ${AUTOLOAD_FILE} >/dev/null"
        if echo "yt6801" | ${SUDO} tee "${AUTOLOAD_FILE}" >/dev/null; then
            ${SUDO} chmod 644 "${AUTOLOAD_FILE}" 2>/dev/null || true
            log_ok "已写入 ${AUTOLOAD_FILE},系统启动时会自动 modprobe yt6801"
        else
            log_err "写入 ${AUTOLOAD_FILE} 失败"
            return 1
        fi
    fi

    # Kylin 系列: 重新生成 initramfs,让驱动在网络/IPv4-only 早期阶段可用
    if is_kylin; then
        if command -v update-initramfs >/dev/null 2>&1; then
            log_info "Kylin: 重建 initramfs 以包含 yt6801 (initramfs-tools hook 模式)"
            run_sudo "update-initramfs -u" update-initramfs -u \
                || log_warn "initramfs 重建失败,可稍后手动执行 'sudo update-initramfs -u'"
        else
            log_dim "未找到 update-initramfs,跳过 initramfs 重建"
        fi
    fi
}

do_install() {
    local ko_size=""
    log_step "步骤 1/6  校验项目结构与编译环境"
    check_layout    || { log_err "项目结构不完整,中止。"; exit 1; }
    check_build_deps || { log_err "编译工具链缺失,中止。"; exit 1; }
    check_kernel_headers || { log_err "内核头文件缺失,中止。"; exit 1; }

    log_step "步骤 2/6  编译驱动模块 (在 ${SRC_DIR} 内执行 make)"
    if [[ -f "${SRC_DIR}/${KO_FILE}" ]]; then
        log_warn "检测到已编译产物 ${SRC_DIR}/${KO_FILE},执行 make clean 后重新构建"
        run_cmd "清理旧构建产物" make -C "${SRC_DIR}" -f "${MAKEFILE}" clean || exit 1
    fi
    run_cmd "编译驱动 (实时输出,可能持续数十秒)" \
        make -C "${SRC_DIR}" -f "${MAKEFILE}" || exit 1
    if [[ ! -f "${SRC_DIR}/${KO_FILE}" ]]; then
        log_err "make 执行成功,但未生成预期的 ${KO_FILE},请检查上面的编译输出。"
        exit 1
    fi
    ko_size="$(du -h "${SRC_DIR}/${KO_FILE}" | cut -f1)"
    log_ok "编译完成: ${SRC_DIR}/${KO_FILE}  (大小: ${ko_size})"

    log_step "步骤 3/6  安装驱动到 /lib/modules/${KVER}"
    setup_sudo
    run_sudo "安装驱动 (make modules_install + depmod)" \
        make -C "${SRC_DIR}" -f "${MAKEFILE}" install || exit 1
    if [[ ! -f "${MOD_INSTALL_KO}" ]]; then
        log_err "make install 完成,但未在 ${MOD_INSTALL_KO} 找到驱动文件。"
        exit 1
    fi
    log_ok "已安装到: ${MOD_INSTALL_KO}"

    log_step "步骤 4/6  配置开机自动加载 (${AUTOLOAD_FILE})"
    setup_autoload || { log_err "开机自启配置失败,中止。"; exit 1; }

    log_step "步骤 5/6  加载驱动 (insmod)"
    if lsmod 2>/dev/null | grep -q "^${DRIVER_NAME}[[:space:]]"; then
        log_warn "驱动 ${DRIVER_NAME} 已经在运行,先卸载再加载"
        run_sudo "卸载旧模块" rmmod "${DRIVER_NAME}" || exit 1
    fi
    run_sudo "加载新模块" insmod "${MOD_INSTALL_KO}" || {
        log_err "加载失败,常见原因:"
        log_dim "  1) Secure Boot 开启 —— 内核拒绝未签名模块,需在 BIOS 关闭或自行签名"
        log_dim "  2) 内核版本与编译时用的头文件不匹配"
        log_dim "  3) 硬件未被识别 —— 运行 'lspci | grep -i motorcomm' 检查"
        log_dim "完整诊断请运行: ${SUDO} dmesg | tail -n 50"
        exit 1
    }
    log_ok "驱动 ${DRIVER_NAME} 已成功加载"

    log_step "步骤 6/6  安装后自检"
    do_status

    printf "\n${C_BOLD}${C_GREEN}✔ 安装完成${C_RESET}\n"
    cat <<EOF
  ${C_DIM}接下来你可以:${C_RESET}
    - 用 ${C_CYAN}ip link${C_RESET} 或 ${C_CYAN}ifconfig -a${C_RESET} 查看新增网卡
    - 用 ${C_CYAN}ip addr${C_RESET} 给网卡配置 IP,例如:
        ${C_DIM}sudo ip addr add 192.168.1.100/24 dev ethX${C_RESET}
        ${C_DIM}sudo ip link set ethX up${C_RESET}
    - 用 ${C_CYAN}ethtool ethX${C_RESET} 查看链路状态
    - 开机自启已配置: ${C_CYAN}${AUTOLOAD_FILE}${C_RESET},重启后自动加载
    - 卸载驱动: ${C_CYAN}./${SCRIPT_NAME} uninstall${C_RESET}
EOF
}

# ============================================================
# 动作:卸载
# ============================================================
do_uninstall() {
    log_step "卸载驱动"
    setup_sudo

    if lsmod 2>/dev/null | grep -q "^${DRIVER_NAME}[[:space:]]"; then
        run_sudo "卸载运行中的模块" rmmod "${DRIVER_NAME}" || exit 1
    else
        log_info "驱动未加载,跳过 rmmod"
    fi

    if [[ -f "${MAKEFILE}" ]] && [[ -d "${SRC_DIR}" ]]; then
        run_sudo "清理已安装的驱动文件" \
            make -C "${SRC_DIR}" -f "${MAKEFILE}" uninstall || true
    fi
    if [[ -d "${MOD_INSTALL_DIR}" ]]; then
        run_sudo "删除残留目录" rm -rf "${MOD_INSTALL_DIR}" || true
    fi
    if [[ -f "${AUTOLOAD_FILE}" ]]; then
        run_sudo "删除开机自启配置" rm -f "${AUTOLOAD_FILE}" || true
    fi
    run_sudo "刷新模块依赖" depmod -a || true

    # Kylin: 同步清理 initramfs 中的旧驱动镜像
    if is_kylin && command -v update-initramfs >/dev/null 2>&1; then
        run_sudo "重建 initramfs (Kylin)" update-initramfs -u || true
    fi

    log_ok "卸载完成"
}

# ============================================================
# 动作:重载
# ============================================================
do_reload() {
    log_step "重载驱动"
    setup_sudo
    if lsmod 2>/dev/null | grep -q "^${DRIVER_NAME}[[:space:]]"; then
        run_sudo "卸载旧模块" rmmod "${DRIVER_NAME}" || exit 1
    fi
    if [[ ! -f "${MOD_INSTALL_KO}" ]]; then
        log_warn "未在 ${MOD_INSTALL_KO} 找到已安装的模块,先尝试重新安装"
        do_install
        return $?
    fi
    run_sudo "加载模块" insmod "${MOD_INSTALL_KO}" || exit 1
    log_ok "重载完成"
    do_status
}

# ============================================================
# 动作:状态
# ============================================================
do_status() {
    local devs=""
    local ifaces=""
    local iface=""
    local state=""
    log_step "驱动状态"
    printf "  ${C_BOLD}%-18s${C_RESET} %s\n" "内核版本:"     "${KVER}"
    printf "  ${C_BOLD}%-18s${C_RESET} %s\n" "驱动名:"       "${DRIVER_NAME}"
    printf "  ${C_BOLD}%-18s${C_RESET} "       "是否已加载:"
    if command -v lsmod >/dev/null 2>&1 && lsmod 2>/dev/null | grep -q "^${DRIVER_NAME}[[:space:]]"; then
        printf "${C_GREEN}是${C_RESET}  ("
        lsmod 2>/dev/null | grep "^${DRIVER_NAME}[[:space:]]" | awk '{printf "used_by=%s, size=%s", $3, $2}'
        printf ")\n"
    else
        printf "${C_YELLOW}否${C_RESET}\n"
    fi
    printf "  ${C_BOLD}%-18s${C_RESET} %s\n" "安装路径:"     "${MOD_INSTALL_KO}"
    if [[ -f "${MOD_INSTALL_KO}" ]]; then
        log_ok "已安装的 .ko 文件存在"
    else
        log_warn "已安装的 .ko 文件不存在"
    fi
    printf "  ${C_BOLD}%-18s${C_RESET} " "开机自启:"
    if [[ -f "${AUTOLOAD_FILE}" ]]; then
        printf "${C_GREEN}已配置${C_RESET}  (${AUTOLOAD_FILE})\n"
        if is_kylin; then
            log_dim "  Kylin: 驱动已写入 initramfs(下次内核升级会自动重建)"
        fi
    else
        printf "${C_YELLOW}未配置${C_RESET}  (不会随系统启动自动加载,运行 'install' 子命令可补上)\n"
    fi

    # 网卡信息
    printf "\n  ${C_BOLD}检测到的 YT6801 网卡:${C_RESET}\n"
    if command -v lspci >/dev/null 2>&1; then
        devs="$(lspci 2>/dev/null | grep -i motorcomm || true)"
        if [[ -n "${devs}" ]]; then
            # 按行缩进输出(bash 3.2 兼容写法)
            while IFS= read -r line; do
                [[ -z "${line}" ]] && continue
                printf "    ${C_DIM}%s${C_RESET}\n" "${line}"
            done <<< "${devs}"
        else
            printf "    ${C_DIM}(lspci 未列出 motorcomm 设备,可能被识别为其它厂商)${C_RESET}\n"
        fi
    else
        log_dim "lspci 未安装,跳过 PCI 设备检查"
    fi

    # 接口名
    if command -v ip >/dev/null 2>&1; then
        ifaces="$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v '^lo$' || true)"
        if [[ -n "${ifaces}" ]]; then
            printf "\n  ${C_BOLD}系统中的网络接口:${C_RESET}\n"
            while IFS= read -r iface; do
                [[ -z "${iface}" ]] && continue
                state="$(ip -o link show "${iface}" 2>/dev/null | awk -F'<' '{print $2}' | awk -F'>' '{print $1}')"
                printf "    %s  ${C_DIM}<%s>${C_RESET}\n" "${iface}" "${state:-UNKNOWN}"
            done <<< "${ifaces}"
        fi
    fi
}

# ============================================================
# 入口
# ============================================================
main() {
    local action="install"
    if [[ $# -gt 0 ]]; then
        case "$1" in
            install)   action="install"   ;;
            uninstall) action="uninstall" ;;
            reload)    action="reload"    ;;
            status)    action="status"    ;;
            help|-h|--help)
                usage
                exit 0
                ;;
            *)
                printf "${C_RED}未知子命令:${C_RESET} %s\n\n" "$1" >&2
                usage
                exit 1
                ;;
        esac
    fi

    # status 子命令不需要项目结构
    if [[ "${action}" != "help" && "${action}" != "status" ]]; then
        check_linux
        print_banner
    fi

    case "${action}" in
        install)   do_install   ;;
        uninstall) do_uninstall ;;
        reload)    do_reload    ;;
        status)    do_status    ;;
    esac
}

main "$@"
