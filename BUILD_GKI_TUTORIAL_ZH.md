# 编译 Android GKI (通用内核镜像) 教程

本教程将指导您如何编译 Android 13 GKI (5.15) 内核。

## 1. 项目分析

- **内核版本**: Android 13 GKI (5.15)
- **目标架构**: AArch64 (ARM64)
- **必需工具链**: Clang `r547379` (由 `build.config.constants` 指定)
- **当前状态**: 您已拥有内核源码 (`common` 目录)，但为了生成符合 Google 标准的 GKI 镜像（保证 ABI 兼容性），必须使用 Android 通用内核构建系统（包括预构建的工具链和构建脚本）。

---

## 2. 准备工作 (Prerequisites)

在开始之前，请确保您的 Linux 环境（推荐 Ubuntu 20.04/22.04）已安装必要的构建依赖。

### 安装依赖包
打开终端并运行以下命令：

```bash
sudo apt-get update
sudo apt-get install git ccache automake flex lzop bison gperf \
    build-essential zip curl zlib1g-dev g++-multilib libxml2-utils \
    bzip2 libbz2-dev libbz2-1.0 libghc-bzlib-dev squashfs-tools \
    pngcrush schedtool dpkg-dev liblz4-tool make optipng maven \
    libssl-dev bc wget
```

### 安装 Repo 工具
Android 内核开发使用 `repo` 工具管理多个 Git 仓库。

```bash
mkdir -p ~/.bin
PATH="${HOME}/.bin:${PATH}"
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo
chmod a+rx ~/.bin/repo
```

---

## 3. 搭建编译环境

要成功编译 GKI，您需要一个完整的 Android 内核构建环境，而不仅仅是内核源码。推荐使用 **方案 A**。

### 方案 A: 标准 Google/AOSP 流程 (强烈推荐)

此方法将下载完整的构建环境（包括工具链、构建脚本等），确保与官方构建一致。

1. **创建工作目录**：
   ```bash
   mkdir android-kernel-5.15
   cd android-kernel-5.15
   ```

2. **初始化 Repo**：
   我们需要同步 `common-android13-5.15` 分支。
   ```bash
   repo init -u https://android.googlesource.com/kernel/manifest -b common-android13-5.15
   ```

3. **同步代码**：
   这一步会下载几个 G (包括工具链和预构建文件)，请耐心等待。
   ```bash
   repo sync
   ```
   *注意：如果您已经有了 `android_gki_kernel_5.15_common` 源码，可以将您的源码替换到 `common` 目录中，或者使用软链接。*

### 方案 B: 手动搭建 (仅供参考)

如果您不想下载整个 repo 环境，您需要手动模拟目录结构，但这很容易出错。你需要：
1. 确保当前目录名为 `common`。
2. 在 `common` 的上级目录，创建 `prebuilts` 和 `build` 目录。
3. 下载对应的 Clang 工具链 (`r547379`) 到 `prebuilts/clang/host/linux-x86/`。
4. 克隆 `build` 仓库到上级目录。
5. **不推荐此方法**，因为 GKI 对工具链版本和构建环境非常敏感。

---

## 4. 编译内核

进入 Repo 工作目录的根目录（即 `common` 目录的 **上一级**）。

### 方法 1: 使用 Bazel (现代/默认方式)

Google 目前推荐使用 Bazel 进行构建，速度更快且更可靠。

```bash
# 构建 GKI 内核及分发包
tools/bazel build //common:kernel_aarch64_dist
```

### 方法 2: 使用 build.sh (传统脚本方式)

这是传统的构建方式，通过环境变量配置。

```bash
# 设置构建配置为 GKI AArch64
BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh
```

---

## 5. 输出产物 (Output)

编译成功后，产物通常位于 `out/` 目录下。

- **内核镜像 (Image)**: 
  `out/android13-5.15/dist/Image`
- **压缩内核 (Image.lz4 / Image.gz)**:
  `out/android13-5.15/dist/Image.lz4`
- **内核模块 (Modules)**:
  `out/android13-5.15/dist/*.ko`

### 常见问题
- **ABI 差异**: 如果您修改了内核源码导致 ABI 变化，构建可能会失败。GKI 严格检查 ABI 兼容性。如果是用于开发/调试，可以尝试在 `build/build.sh` 命令前添加 `BPF_KO_CONF_CHECK=0` 或修改相关配置来绕过检查（仅限开发）。

祝编译顺利！







