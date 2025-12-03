# Android GKI 通用内核镜像

## 项目简介

本项目是基于 **Linux 5.15.194** 的 **Android GKI (Generic Kernel Image)** 通用内核镜像源码。GKI 是 Google 为 Android 设备设计的统一内核架构，旨在实现内核与硬件驱动分离，提高内核的可维护性和兼容性。

### 内核版本信息

- **内核版本**: Linux 5.15.194 (Trick or Treat)
- **Android 版本**: Android 13 (API 33)
- **目标架构**: AArch64 (ARM64)
- **KMI 版本**: Generation 8
- **构建工具链**: Clang r547379 (LLVM)

---

## 核心特性

### Android 特定功能

- ✅ **Binder IPC**: Android 进程间通信机制
  - 支持 `binder`, `hwbinder`, `vndbinder` 设备节点
- ✅ **Ashmem**: Android 共享内存管理器
- ✅ **Low Memory Killer**: Android 低内存杀手机制
- ✅ **Android 电源管理**: 支持 wakelocks 和 autosleep
- ✅ **USB Gadget**: 支持 USB 配置功能 (ConfigFS)
  - MIDI 功能支持
  - FunctionFS 支持

### 安全特性

- ✅ **SELinux**: 强制访问控制 (MAC) 安全框架
- ✅ **Hardened User Copy**: 防止用户空间内存拷贝漏洞
- ✅ **Stack Protector Strong**: 强化栈保护
- ✅ **CPU SW Domain PAN**: ARM64 用户空间访问保护
- ✅ **ARM64 SW TTBR0 PAN**: 地址空间隔离保护
- ✅ **Strict Kernel RWX**: 内核代码段保护
- ✅ **Seccomp**: 系统调用过滤
- ✅ **Audit**: 系统审计功能
- ✅ **FIPS 140**: 支持 FIPS 140-2 加密标准（可选配置）

### 网络功能

- ✅ **IPv4/IPv6**: 完整的双栈网络支持
- ✅ **Netfilter**: Linux 防火墙框架
  - IPTables 和 IP6Tables 支持
  - 连接跟踪 (Conntrack)
  - NAT 支持
  - 多种匹配规则和目标
- ✅ **IPSec**: IP 安全协议支持
  - ESP (封装安全载荷)
  - AH (认证头)
  - 隧道模式支持
- ✅ **XFRM**: IP 安全框架
- ✅ **网络调度**: HTB (Hierarchical Token Bucket) 队列规则
- ✅ **网络分类**: U32 分类器和动作

### 文件系统支持

- ✅ **EXT4**: 带安全扩展的 EXT4 文件系统
- ✅ **FUSE**: 用户空间文件系统
- ✅ **TMPFS**: 临时文件系统（支持 POSIX ACL）
- ✅ **VFAT**: FAT32 文件系统
- ✅ **MSDOS**: DOS 文件系统
- ✅ **Device Mapper**: 设备映射框架
  - DM-Crypt: 磁盘加密
  - DM-Verity: 完整性验证
  - DM-Verity FEC: 前向纠错

### 模块化支持

- ✅ **内核模块**: 完整的模块加载/卸载支持
- ✅ **模块版本控制**: MODVERSIONS 支持
- ✅ **System DLKM**: 系统可加载内核模块支持
- ✅ **GKI 模块**: 符合 GKI 规范的模块化驱动

### 设备支持

本项目支持多个设备厂商的 ABI 兼容性，包括但不限于：

- **Google**: Pixel 系列
- **Samsung**: Galaxy 系列、Exynos 平台
- **Xiaomi**: 小米系列设备
- **OnePlus**: OnePlus 设备
- **MediaTek**: MTK 平台
- **Qualcomm**: Snapdragon 平台
- **Unisoc**: 展讯平台
- **其他厂商**: Honor、Vivo、Oppo、Sony、Motorola、Lenovo、Nothing、Honda、Volvo 等

### 调试与性能分析

- ✅ **KASAN**: 内核地址消毒器（可选）
- ✅ **KProbes**: 内核动态探测（可选）
- ✅ **Ftrace**: 内核函数跟踪
- ✅ **Perf Events**: 性能事件分析
- ✅ **Kallsyms**: 内核符号表（支持所有符号）
- ✅ **Pstore**: 持久化存储（支持控制台和 RAM）
- ✅ **调度统计**: 进程调度统计信息
- ✅ **任务统计**: 任务延迟和 I/O 统计

### 其他特性

- ✅ **BPF**: Berkeley Packet Filter 支持
- ✅ **Cgroups**: 控制组支持（CPU、内存、调度等）
- ✅ **实时调度**: RT 组调度支持
- ✅ **高精度定时器**: High Resolution Timers
- ✅ **随机化基址**: KASLR (Kernel Address Space Layout Randomization)
- ✅ **USB HID**: USB 人机接口设备支持
- ✅ **输入子系统**: 支持多种输入设备（游戏手柄、触摸板等）
- ✅ **媒体支持**: 基础媒体框架
- ✅ **声音支持**: ALSA 音频框架

---

## 构建系统

### 构建配置

项目使用 Android 内核构建系统，支持以下构建方式：

1. **Bazel 构建** (推荐): 使用 Google Bazel 构建系统
2. **传统构建**: 使用 `build.sh` 脚本构建

### 主要构建配置文件

- `build.config.gki.aarch64`: GKI AArch64 主配置
- `build.config.gki`: GKI 通用配置
- `build.config.common`: 通用构建配置
- `arch/arm64/configs/gki_defconfig`: GKI 默认内核配置

### 构建产物

- **内核镜像**: `Image`, `Image.gz`, `Image.lz4`
- **内核模块**: `*.ko` 文件
- **Boot 镜像**: `boot.img` (可选)
- **GKI 认证工具**: ABI 兼容性检查工具

---

## 快速开始

### 环境要求

- **操作系统**: Linux (推荐 Ubuntu 20.04/22.04 或 Arch Linux)
- **构建工具**: 
  - Clang r547379
  - Bazel (用于 Bazel 构建)
  - Android 构建工具链
- **依赖包**: 参见 `BUILD_GKI_TUTORIAL_ZH.md`

### 构建步骤

#### 方法 1: 使用 Bazel 构建 (推荐)

```bash
# 在 repo 工作目录根目录执行
tools/bazel build //common:kernel_aarch64_dist
```

#### 方法 2: 使用传统构建脚本

```bash
# 设置构建配置
BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh
```

#### 方法 3: 使用自定义构建脚本

项目包含 `build_gki.sh` 脚本，提供了完整的构建流程，包括：
- 自动环境检查
- 温度监控（防止过热）
- 版本自定义
- 自动生成构建产物（Image.gz, boot.img, anykernel.zip）

```bash
./build_gki.sh
```

详细构建教程请参考: `BUILD_GKI_TUTORIAL_ZH.md`

---

## 项目结构

```
android_gki_kernel_5.15_common/
├── android/                    # Android 特定文件
│   ├── abi_gki_aarch64*        # KMI 符号列表（各厂商）
│   ├── gki_aarch64_modules     # GKI 模块列表
│   └── gki_system_dlkm_modules # System DLKM 模块列表
├── arch/                       # 架构相关代码
│   └── arm64/                  # ARM64 架构支持
├── build.config.*              # 构建配置文件
├── drivers/                    # 设备驱动
├── kernel/                     # 内核核心代码
├── fs/                         # 文件系统
├── net/                        # 网络协议栈
├── security/                   # 安全框架
└── Documentation/              # 内核文档
```

---

## ABI 兼容性

GKI 内核严格遵循 **KMI (Kernel Module Interface)** 规范，确保：

- ✅ **ABI 稳定性**: 内核与模块之间的接口保持稳定
- ✅ **向后兼容**: 新版本内核兼容旧版本模块
- ✅ **符号导出控制**: 仅导出允许的符号
- ✅ **类型可见性**: 控制结构体类型的可见性

### KMI 符号管理

- `android/abi_gki_aarch64`: 基础 KMI 符号列表
- `android/abi_gki_aarch64_*.xml`: 各厂商特定的 ABI 定义
- `android/abi_gki_aarch64_type_visibility`: 类型可见性控制

---

## 配置选项

### Android 基础配置

基础 Android 功能配置位于 `kernel/configs/android-base.config`，包括：
- Android Binder IPC
- Ashmem
- Low Memory Killer
- SELinux
- 网络功能

### Android 推荐配置

推荐配置位于 `kernel/configs/android-recommended.config`，包括：
- 文件系统支持（EXT4, FUSE, TMPFS）
- 设备映射（DM-Crypt, DM-Verity）
- 输入设备支持
- 调试功能

---

## 开发指南

### 提交补丁

如需向本项目提交补丁，请遵循以下规范（详见 `README.md` 英文版）：

1. **最佳方式**: 向上游 Linux 内核提交补丁
2. **补丁标签**: 
   - `UPSTREAM:`: 来自上游的补丁
   - `BACKPORT:`: 需要修改的上游补丁
   - `FROMGIT:`: 来自维护者树的补丁
   - `FROMLIST:`: 来自邮件列表的补丁
   - `ANDROID:`: Android 特定补丁
3. **必需标签**:
   - `Change-Id:`: Gerrit Change-Id
   - `Signed-off-by:`: 签名
   - `Bug:`: Android Bug ID（如适用）

### 代码规范

- 遵循 Linux 内核编码规范
- 通过 `scripts/checkpatch.pl` 检查
- 不破坏 `gki_defconfig` 或 `allmodconfig` 构建

---

## 许可证

本项目遵循 **GPL-2.0** 许可证。详见 `COPYING` 文件。

---

## 相关资源

- **官方文档**: https://source.android.com/docs/core/architecture/kernel
- **GKI 规范**: https://source.android.com/docs/core/architecture/kernel/generic-kernel-image
- **内核文档**: `Documentation/` 目录
- **构建教程**: `BUILD_GKI_TUTORIAL_ZH.md`
- **上游内核**: https://www.kernel.org/

---

## 贡献者

本项目基于 Linux 内核社区和 Android 开源项目的贡献。感谢所有贡献者！

---

## 更新日志

- **5.15.194**: 当前版本
- 支持 Android 13 GKI 规范
- KMI Generation 8
- 多厂商 ABI 兼容性支持

---

## 注意事项

⚠️ **重要提示**:

1. **ABI 兼容性**: 修改内核代码时需注意保持 KMI 兼容性，否则可能导致模块加载失败
2. **构建环境**: 建议使用官方推荐的构建环境，避免工具链版本不匹配
3. **测试**: 在设备上刷入内核前，请确保已备份原始内核
4. **FIPS 140**: 如需 FIPS 140 认证，请使用 `build.config.gki.aarch64.fips140` 配置

---

## 支持

如有问题或建议，请：
- 查看 `Documentation/` 目录下的文档
- 参考 `BUILD_GKI_TUTORIAL_ZH.md` 构建教程
- 查看上游 Linux 内核文档: https://www.kernel.org/doc/html/latest/

---

**最后更新**: 2024年
