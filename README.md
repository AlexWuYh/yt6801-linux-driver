# Motorcomm YT6801 Linux Driver

> Linux 内核驱动 —— Motorcomm(裕太微)YT6801 系列 PCIe 千兆以太网控制器

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Kernel: 4.x+](https://img.shields.io/badge/Kernel-4.x%2B-blue.svg)]()
[![Platform: x86_64 / arm64](https://img.shields.io/badge/Platform-x86_64%20%2F%20arm64-lightgrey.svg)]()

---

## 目录

- [项目简介](#项目简介)
- [硬件兼容性](#硬件兼容性)
- [仓库结构](#仓库结构)
- [环境要求](#环境要求)
- [安装](#安装)
  - [方法一:一键脚本(推荐)](#方法一一键脚本推荐)
  - [方法二:手动 make 安装](#方法二手动-make-安装)
  - [方法三:DKMS 自动重建](#方法三dkms-自动重建)
- [开机自动加载](#开机自动加载)
- [安装后验证](#安装后验证)
- [内核编译参数](#内核编译参数)
- [卸载](#卸载)
- [常见问题](#常见问题)
- [许可证](#许可证)

---

## 项目简介

本仓库为 Motorcomm **YT6801** 系列 PCIe 千兆以太网控制器提供 Linux 内核态驱动,包含
上游内核尚未合并的部分特性(如增强的中断节流、ASPM、零拷贝等可调开关)。

驱动源码以 `src/fuxi-*.c` 系列文件组织(命名取自 `Fuxi-GMAC`, Motorcomm 内部代号),
通过项目根目录的 `Makefile` 接入 Linux 内核标准 Kbuild 系统。

**典型应用场景:**

- 主板/工控机板载的 YT6801 在较新的 Linux 内核(6.x)下识别但无 `ethtool` 高级功能
- 麒麟/UOS 等国产系统需要厂商驱动
- 容器/虚拟化宿主机中需要驱动支持 SR-IOV 之外的额外功能

---

## 硬件兼容性

| 项目       | 说明                                                       |
| ---------- | ---------------------------------------------------------- |
| 芯片       | Motorcomm YT6801 / YT6801A / YT6801B 系列                  |
| 总线       | PCI Express 2.0 x1 / x4                                   |
| 速率       | 10 / 100 / 1000 Mbps                                       |
| 操作系统   | Linux Kernel 4.4 及以上(在 5.x / 6.x 上验证)               |
| 架构       | x86_64 / aarch64                                           |
| 发行版     | Ubuntu, Debian, RHEL, CentOS, Fedora, Arch, openSUSE, Kylin |

> 在某些主板/较新内核上,内核可能已自带一个最小可用的 `yt6801` 驱动,但版本较旧、功能
> 不全。本仓库的版本是 Motorcomm 官方维护的功能完整版。

---

## 仓库结构

```
yt6801-linux-driver/
├── Makefile                  # 项目级 Makefile,适配 src/ 目录
├── src/                      # 驱动源码
│   ├── fuxi-gmac-common.c
│   ├── fuxi-gmac-desc.c
│   ├── fuxi-gmac-ethtool.c
│   ├── fuxi-gmac-hw.c
│   ├── fuxi-gmac-net.c
│   ├── fuxi-gmac-pci.c
│   ├── fuxi-gmac-phy.c
│   ├── fuxi-efuse.c
│   ├── fuxi-gmac-ioctl.c
│   ├── fuxi-*.h
│   ├── dkms.conf             # DKMS 集成配置
│   └── motorcomm             # 麒麟系统 initramfs hook
├── yt_nic_install.sh         # 一键安装/卸载脚本
├── README.md
└── LICENSE
```

---

## 环境要求

构建与运行驱动需要以下组件:

| 组件                                | 作用                          |
| ----------------------------------- | ----------------------------- |
| `gcc` (≥ 4.8)                       | 编译 C 源文件                 |
| `make` (≥ 3.81)                     | 调用内核 Kbuild 系统          |
| `linux-headers-$(uname -r)`         | 与当前运行内核匹配的头文件    |
| `kmod` (提供 `insmod`/`rmmod`/`depmod`) | 加载/卸载/管理内核模块    |
| `git`                               | 克隆本仓库(下载 release 也可跳过) |
| `sudo` (普通用户运行时)             | 提升权限以安装/加载模块       |

> 内核构建还会用到 `perl`、`bc`、`rsync`、`pkg-config` 等辅助工具。这些在
> 主流发行版默认已预装;极简容器/裁剪系统中如遇 `make` 中途报缺工具,按报错
> 名称补装即可。

### 各发行版安装依赖

#### Debian / Ubuntu / Kali / UOS

```bash
sudo apt update
sudo apt install -y gcc make linux-headers-$(uname -r) kmod git
```

> **为什么不写 `build-essential`?**  `build-essential` 是 Debian/Ubuntu 的元包,
> 内部确实包含 `gcc`、`g++`、`make`、`libc6-dev` 等,但用户常常误以为还需要再单独
> 安装。这里直接列全,所见即所得;若想更精简(只要 `gcc` 头文件与构建工具,不要
> `g++`/Debian 打包工具),去掉 `g++` 的间接依赖即可。

#### RHEL / CentOS Stream / Fedora

```bash
sudo dnf install -y gcc make kernel-devel kernel-headers kmod git
```

> CentOS 7 仍用 `yum`,命令相同: `sudo yum install -y gcc make kernel-devel kernel-headers kmod git`

#### Arch Linux / Manjaro

```bash
sudo pacman -S --needed gcc make linux-headers kmod git
```

#### openSUSE Leap / Tumbleweed

```bash
sudo zypper install -y gcc make kernel-devel kernel-default-devel kmod git
```

#### 银河麒麟 (Kylin)

```bash
sudo yum install -y gcc make kernel-devel kernel-headers kmod git
# Kylin 上的 initramfs hook 还需要
sudo yum install -y initramfs-tools
```

#### 验证依赖已就绪

```bash
gcc --version                       # 应能输出版本号
make --version                      # 应能输出版本号
git --version                       # 应能输出版本号
ls /lib/modules/$(uname -r)/build/Makefile   # 应存在,这是内核头文件是否正确的最直接标志
```

如果 `ls` 那条命令报"文件不存在",说明头文件未装或版本不匹配,请用 `uname -r` 输出版本号
去搜索对应包名。

---

## 安装

> ### 🔐 权限要求
> **脚本安装/卸载/重载** 子命令需要 **root 权限**,因为它们要:
> - 写入 `/lib/modules/<ver>/kernel/drivers/net/ethernet/motorcomm/yt6801/`
> - 加载/卸载内核模块(`insmod` / `rmmod`)
> - 写入 `/etc/modules-load.d/yt6801.conf`(开机自启)
> - Kylin 系统还要重建 `initramfs`
>
> 两种获取 root 权限的方式,二选一即可:
>
> ```bash
> # 方式一:用 sudo(推荐,无需切换账号)
> sudo ./yt_nic_install.sh install
>
> # 方式二:切换到 root 账号
> su -                                # 输入 root 密码
> ./yt_nic_install.sh install         # 此时已是 root,命令前不再需要 sudo
> # 或: su -c './yt_nic_install.sh install'
> ```
>
> 脚本内部对需要 root 的步骤会**自动调用 `sudo`**,所以你直接 `./yt_nic_install.sh` 运行
> 也会在关键时刻弹出密码提示;但**整段以 `sudo` 或 root 启动更省事**。
>
> 仅 `status` 和 `help` 子命令不需要 root,可以普通用户直接跑。

### 方法一:一键脚本(推荐)

适用于 90% 的场景,脚本会依次完成: **环境检查 → 编译 → 安装 → 配置开机自启 → 加载 → 自检**。

```bash
# 1. 克隆仓库
git clone https://github.com/AlexWuYh/yt6801-linux-driver.git
cd yt6801-linux-driver

# 2. 赋予可执行权限(首次使用)
chmod +x yt_nic_install.sh

# 3. 安装(需 root,见上方"权限要求"小节)
sudo ./yt_nic_install.sh
# 或:su - 切到 root 后再 ./yt_nic_install.sh
```

> 如果你已经在 root 账号下(例如 `whoami` 输出 `root`),直接 `./yt_nic_install.sh` 即可,
> 不要再加 `sudo`(会找不到 `sudo` 命令或报"already root")。

脚本执行过程中会在终端实时输出:

- 顶部 ASCII 横幅
- 每一步的标题(`┌──[ 步骤 1/6 ... ]──`)
- 当前正在执行的命令(灰色)
- 该命令原生输出(make 的编译日志等)实时流过
- 最终 ✓/✗/⚠ 状态标记
- 自检结果(模块加载情况、开机自启状态、网卡接口列表)

脚本完成 **6 步**: 环境校验 → 编译 → 安装 → **配置开机自启** → 加载 → 自检。
**Kylin 系统** 会额外重建 initramfs,让驱动在启动早期阶段(PXE / 网络根文件系统等)也可用。

#### 脚本子命令

| 子命令       | 说明                                                       |
| ------------ | ---------------------------------------------------------- |
| `install`    | 编译 + 安装 + 配置开机自启 + 加载(默认)                    |
| `uninstall`  | 卸载模块、清理 `/lib/modules/...` 文件、移除开机自启        |
| `reload`     | 不重编译,仅 rmmod 后再 insmod                              |
| `status`     | 显示驱动加载状态、开机自启、`.ko` 文件、网络接口            |
| `help`       | 显示帮助信息                                               |

使用示例:

```bash
./yt_nic_install.sh status      # 看看驱动、自启、网络是不是都正常
./yt_nic_install.sh reload      # 修改驱动参数后快速重载
./yt_nic_install.sh uninstall   # 彻底卸载(含开机自启)
```

### 方法二:手动 make 安装

如果你想完全掌控每一步(便于排错、CI 集成等),可以直接调用 make:

> **每一步带 `sudo` 的都需要 root 权限**(见上"权限要求"小节)。如果你已经切到 root
> 账号,把所有 `sudo` 去掉即可。

```bash
# 1. 进入源码目录(注意:Makefile 在项目根目录,需要 -f 引用)
cd src

# 2. 清理上次构建(可选,首次跳过)
make -f ../Makefile clean

# 3. 编译(无需 root)
make -f ../Makefile
#   编译产物: src/yt6801.ko

# 4. 安装到 /lib/modules/$(uname -r)/kernel/drivers/net/ethernet/motorcomm/yt6801
#   并刷新模块依赖(需要 root)
sudo make -f ../Makefile install

# 5. 配置开机自动加载(需要 root)
echo "yt6801" | sudo tee /etc/modules-load.d/yt6801.conf
sudo chmod 644 /etc/modules-load.d/yt6801.conf

#   Kylin 系统: 同步把驱动打进 initramfs,让启动早期阶段就能用
#   (需要 Makefile 已把 src/motorcomm 复制到 /usr/share/initramfs-tools/hooks/)
if [[ -f /etc/kylin-release ]]; then
    sudo update-initramfs -u
fi

# 6. 加载模块(需要 root)
sudo insmod /lib/modules/$(uname -r)/kernel/drivers/net/ethernet/motorcomm/yt6801/yt6801.ko

# 或使用 modprobe(自动处理依赖与 modules.dep)
sudo modprobe yt6801
```

#### 关键 Makefile 变量一览

你可以在 `make` 时通过 `变量=值` 覆盖,例如:

```bash
# 关闭调试日志(默认开启,verbose 的 dmesg 看着烦时可以关掉)
make -f ../Makefile FXGMAC_DEBUG=OFF

# 关闭 ASPM 节能(部分主板 ASPM 兼容性差)
make -f ../Makefile FXGMAC_ASPM_ENABLED=ON

# 调整中断节流
make -f ../Makefile moderation_en=1 moderation_param=100
```

完整参数见 [`Makefile`](Makefile) 与 [内核编译参数](#内核编译参数)一节。

### 方法三:DKMS 自动重建

`src/dkms.conf` 已经为 DKMS 做好准备。**强烈推荐在长期运行的生产机器上使用**——
内核升级时,DKMS 会自动重新编译驱动,无需人工介入。

```bash
# 安装 DKMS
sudo apt install -y dkms            # Debian/Ubuntu
sudo dnf install -y dkms            # RHEL/Fedora

# 注册并构建
sudo dkms add src/
sudo dkms build yt6801/1.0.32
sudo dkms install yt6801/1.0.32

# 加载
sudo modprobe yt6801
```

> 版本号 `1.0.32` 取自 `src/dkms.conf` 的 `PACKAGE_VERSION`,请以你的实际值为准。

之后每次升级内核:

```bash
sudo dkms autoinstall
```

---

## 开机自动加载

安装脚本/手动安装完成后,默认已经配置好开机自启,下次重启无需手动加载。

### 实现原理

驱动通过 **systemd modules-load.d** 机制随系统启动:

- 配置文件: `/etc/modules-load.d/yt6801.conf`
- 文件内容: 一行 `yt6801`
- 加载时机: systemd 启动早期,早于网络服务

```bash
$ cat /etc/modules-load.d/yt6801.conf
yt6801
```

### 验证

```bash
# 1. 配置文件是否存在
ls -l /etc/modules-load.d/yt6801.conf

# 2. 配置文件内容是否正确
cat /etc/modules-load.d/yt6801.conf    # 应为 yt6801

# 3. 立即验证 systemd 能识别(systemd 系统)
systemctl cat systemd-modules-load.service | head -n 5

# 4. 重启后模块应已自动加载(关键证据)
sudo reboot
lsmod | grep yt6801    # 应当有输出
```

### 临时关闭自启

```bash
sudo rm /etc/modules-load.d/yt6801.conf
sudo depmod -a
```

> 删除后,内核仍然能找到 `.ko`(因为 `depmod` 建立了 `modules.dep`),
> 但需要手动 `sudo modprobe yt6801` 才会加载。

### 重新启用自启

```bash
echo "yt6801" | sudo tee /etc/modules-load.d/yt6801.conf
sudo chmod 644 /etc/modules-load.d/yt6801.conf
```

### Kylin 系统的特殊处理

Kylin(以及所有用 `initramfs-tools` 的 Debian 系发行版)有更进一步的
`initramfs` 钩子机制: `src/motorcomm` 会被复制到 `/usr/share/initramfs-tools/hooks/`,
在 `update-initramfs` 时把驱动打进 initramfs 镜像。

这意味着:

- 启动早期(挂载根文件系统之前)就可用,适用于 **PXE 启动**、**网络根文件系统** 等场景
- 不必担心根目录还没挂载时模块就不可用

```bash
# Kylin 系统额外检查
cat /usr/share/initramfs-tools/hooks/motorcomm
lsinitramfs /boot/initrd.img-$(uname -r) 2>/dev/null | grep yt6801
```

### 非 systemd 系统

`/etc/modules-load.d/` 由 systemd 读取。如果你的系统未使用 systemd
(老版本 CentOS 6、嵌入式 BusyBox 等),改为写入 `/etc/modules`:

```bash
# SysV init / BusyBox 风格
grep -qxF "yt6801" /etc/modules || echo "yt6801" | sudo tee -a /etc/modules
```

---

## 安装后验证

按下面 **从轻到重** 的顺序依次检查,任何一步失败都先看 [常见问题](#常见问题)。

### 1. 模块是否已加载

```bash
lsmod | grep yt6801
# 期望输出(数字不重要):
#   yt6801  147456  0
```

如果无输出,说明 `insmod`/`modprobe` 没成功,执行:

```bash
sudo dmesg | tail -n 50
```

查看内核最后的错误日志。

### 2. 设备是否被识别

```bash
lspci | grep -i motorcomm
# 期望输出形如:
#   03:00.0 Ethernet controller: Device 1d6a:6801 (rev ff)
```

如果 `lspci` 看不到,先确认网卡是否插紧、BIOS 是否启用对应 PCIe 槽位。

### 3. 网卡接口是否出现

```bash
ip -br link show
# 或
ifconfig -a
```

应能看到形如 `eth0` / `enp3s0` / `eno1` 的新接口(命名规则由 systemd/udev 决定)。

### 4. 驱动与固件版本

```bash
sudo ethtool -i eth0
```

输出应包含:

```
driver: yt6801
version: ...
firmware-version: ...
bus-info: 0000:03:00.0
```

### 5. 链路状态与速率

```bash
sudo ethtool eth0
```

重点看:

```
Supported ports: [ TP ]
Speed: 1000Mb/s
Duplex: Full
Link detected: yes
```

### 6. 内核日志(probe 流程)

```bash
dmesg | grep -i yt6801 | tail -n 30
```

正常会看到一串 probe 成功、PHY 识别、ring buffer 初始化的信息。

### 7. 端到端连通性

```bash
# 假设接口名是 enp3s0
sudo ip link set enp3s0 up
sudo ip addr add 192.168.1.100/24 dev enp3s0
ping 192.168.1.1
```

### 8. (可选)吞吐性能压测

```bash
sudo apt install -y iperf3
# A 机器(服务端): iperf3 -s
# B 机器(客户端): iperf3 -c <A 的 IP>
```

千兆网卡的合理预期: 940 Mbps 左右(去除 TCP/IP 开销)。

### 一键检查清单

| 检查项 | 命令                                       | 健康标志                              |
| ------ | ------------------------------------------ | ------------------------------------- |
| 模块   | `lsmod \| grep yt6801`                     | 有输出                                |
| 自启   | `cat /etc/modules-load.d/yt6801.conf`      | 输出 `yt6801`                         |
| 设备   | `lspci \| grep -i motorcomm`               | 有输出                                |
| 接口   | `ip link`                                  | 多了一个非 lo 接口                    |
| 驱动   | `ethtool -i <iface>`                       | `driver: yt6801`                      |
| 链路   | `ethtool <iface>`                          | `Link detected: yes`                  |
| 日志   | `dmesg \| grep -i yt6801`                  | 无 ERROR 行                           |
| 通信   | `ping <gateway>`                           | 有响应                                |
| 重启   | `sudo reboot && lsmod \| grep yt6801`      | 重启后模块仍在(`✓` 验证自启生效)   |

---

## 内核编译参数

`Makefile` 顶部定义的所有 `FXGMAC_*` 开关:

| 参数                            | 默认值 | 含义                                                |
| ------------------------------- | ------ | --------------------------------------------------- |
| `moderation_en`                 | 1      | 中断节流(Interrupt Moderation)开关                 |
| `moderation_param`              | 200    | 中断节流触发间隔(微秒)                              |
| `FXGMAC_DOWNGRADE_DISABLE`      | OFF    | 关闭速率降级(协商失败时不再尝试更低速率)            |
| `FXGMAC_PHY_SLEEP_ENABLE`       | OFF    | 启用 PHY 低功耗睡眠                                 |
| `FXGMAC_ASPM_ENABLED`           | OFF    | 启用 PCIe ASPM 节能(部分主板不兼容,谨慎开启)       |
| `FXGMAC_NOT_USE_PAGE_MAPPING`   | OFF    | 不使用大页映射(可降低对透明大页的依赖)             |
| `FXGMAC_ZERO_COPY`              | OFF    | 启用零拷贝收发(需要 `NOT_USE_PAGE_MAPPING=ON`)      |
| `FXGMAC_DEBUG`                  | ON     | 输出调试日志(`dmesg` 刷屏,生产环境可关)             |
| `FXGMAC_TX_DMA_MAP_SINGLE`      | OFF    | TX DMA 映射使用单段(可能在某些架构上更稳定)        |
| `FXGMAC_EPHY_LOOPBACK_DETECT_ENABLED` | OFF | 启用内部 PHY 回环检测                             |
| `FXGMAC_USE_STATIC_ALLOC`       | ON     | 使用静态分配(降低运行时分配失败风险)                |

> ⚠️ 修改任一开关后,必须 `make clean && make` 才会重新生效。

---

## 卸载

### 脚本方式

```bash
./yt_nic_install.sh uninstall
```

脚本会自动:
- `rmmod yt6801` 卸载运行中的模块
- 删除 `/lib/modules/<ver>/kernel/drivers/net/ethernet/motorcomm/yt6801`
- 删除开机自启文件 `/etc/modules-load.d/yt6801.conf`
- 重建 initramfs(Kylin 系统)
- `depmod -a` 刷新模块依赖

### 手动方式

```bash
# 1. 卸载模块
sudo rmmod yt6801

# 2. 删除安装文件
sudo rm -rf /lib/modules/$(uname -r)/kernel/drivers/net/ethernet/motorcomm/yt6801

# 3. 移除开机自启
sudo rm -f /etc/modules-load.d/yt6801.conf

# 4. Kylin 系统重建 initramfs(去掉 initramfs 里的旧驱动)
[[ -f /etc/kylin-release ]] && sudo update-initramfs -u

# 5. 刷新模块依赖数据库
sudo depmod -a

# (DKMS 用户)
sudo dkms remove yt6801/1.0.32 --all
```

---

## 常见问题

### Q1: `insmod` 报 `Required key not available`

**原因:** BIOS 开启了 Secure Boot,内核拒绝未签名的第三方模块。

**先看状态:**

```bash
mokutil --sb-state
# SecureBoot enabled     ← 表示 Secure Boot 是开着的
# SecureBoot disabled    ← 表示已经关闭
```

`mokutil` 不在系统里时(Debian/Ubuntu)用 `sudo apt install -y mokutil` 装一个;
RHEL 自带无需安装。

**解决(任选其一):**

1. **关闭 Secure Boot**(最简单): 重启进入 BIOS → Security → Secure Boot → Disabled
2. **用 MOK 签名模块**(保留 Secure Boot):

   ```bash
   # 已有 MOK 密钥就跳过生成步骤
   sudo apt install -y mokutil openssl
   # 生成自签名密钥(仅一次)
   sudo mkdir -p /var/lib/shim-signed/mok
   sudo openssl req -new -x509 -newkey rsa:2048 \
       -keyout /var/lib/shim-signed/mok/MOK.priv \
       -outform DER -out /var/lib/shim-signed/mok/MOK.der \
       -nodes -days 36500 -subj "/CN=YT6801/"
   # 签名
   sudo kmodsign sha512 \
       /var/lib/shim-signed/mok/MOK.priv \
       /var/lib/shim-signed/mok/MOK.der \
       /lib/modules/$(uname -r)/kernel/drivers/net/ethernet/motorcomm/yt6801/yt6801.ko
   # 重启时选择"Enroll MOK"导入密钥
   # 之后再跑一次 mokutil --sb-state 确认状态
   ```

### Q2: 编译报 `fatal error: linux/xxx.h: No such file or directory`

**原因:** 内核头文件缺失或与运行内核版本不匹配。

```bash
uname -r   # 记下版本号,例如 6.1.0-18-amd64

# Debian/Ubuntu —— 版本号必须严格一致
sudo apt install -y linux-headers-$(uname -r)

# 如果 apt 找不到包,说明你的内核是手动安装的,需要装对应版本的 linux-headers
apt-cache search linux-headers   # 查看可用版本
```

### Q3: 加载后 `ip link` 看不到新接口

按顺序排查:

```bash
# 1. 设备是否在 PCI 总线里
lspci | grep -i motorcomm

# 2. 内核是否成功 probe
sudo dmesg | grep -i yt6801 | tail -n 20

# 3. 是否有 udev 重命名(把 eth0 改成 enpXsY)
sudo journalctl -u systemd-udevd --since "10 minutes ago" | tail -n 20

# 4. 极端情况:关闭 ASPM 试试
sudo setpci -s <B:D.F> CAP_EXP+10.b=0
```

`<B:D.F>` 从 `lspci -nn | grep motorcomm` 的第一列获取,例如 `03:00.0` 对应 `03:00.0`。

### Q4: 升级内核后驱动失效

每次内核升级后,`/lib/modules/<新版本>/kernel/drivers/...` 下不会有旧版本编译的 `.ko`,
所以新内核下必须重新编译。

**临时方案:**

```bash
cd <仓库目录>
./yt_nic_install.sh
```

**长期方案:** 改用 DKMS 方式安装(见 [方法三](#方法三dkms-自动重建)),内核升级时会自动重建。

### Q5: `make` 报 `No rule to make target` 或类似

通常原因是当前目录不在 `src/`,或者 Makefile 路径传错。

```bash
# 一定要先 cd 进去
cd src
make -f ../Makefile
```

或直接用脚本(脚本内部已处理):

```bash
./yt_nic_install.sh
```

### Q6: 能识别网卡但完全不通(物理层无 Link)

1. 检查网线/光模块指示灯
2. 换一根网线或换一个交换机端口排除物理故障
3. 查看协商速率:

   ```bash
   sudo ethtool eth0 | grep -E "Speed|Link|Auto"
   ```
4. 强制速率/双工:

   ```bash
   sudo ethtool -s eth0 speed 1000 duplex full autoneg on
   ```

### Q7: `dkms build` 失败

最常见原因是内核头文件不匹配。DKMS 用的内核源码路径:

```bash
ls -la /lib/modules/$(uname -r)/build   # 必须是软链接且指向正确的源码目录
```

如果指向错误,修复:

```bash
sudo ln -sf /usr/src/linux-headers-$(uname -r) /lib/modules/$(uname -r)/build
```

---

## 许可证

本项目以 [MIT 许可证](LICENSE) 发布。

驱动源码中包含的 `src/Notice.txt` 注明了 Motorcomm 公司的版权与商标声明。

---

## 相关链接

- Motorcomm(裕太微): <https://www.motor-comm.com/>
- 内核自带 `yt6801` 驱动: `drivers/net/ethernet/motorcomm/`
