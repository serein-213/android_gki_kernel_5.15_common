# GKI 内核构建工作流说明

## 概述

本目录包含用于自动构建 Android GKI（通用内核镜像）的 GitHub Actions 工作流脚本。

## 工作流文件

### 1. `build_gki.yml` - 标准 GKI 内核构建

这是主要的内核构建工作流，用于构建带有正确时间戳的 GKI 内核。

**特性：**
- ✅ 自动化完整构建流程
- ✅ 使用正确的构建时间戳（非 1970 年纪元时间）
- ✅ 生成多种内核镜像格式（Image、Image.gz、Image.lz4）
- ✅ 创建可刷写的 boot.img
- ✅ 生成 AnyKernel3 刷机包
- ✅ 自动应用必要的配置修复
- ✅ 生成详细的构建报告

**触发条件：**
- 推送到 `copilot/create-workflow-script-for-kernel` 分支
- 创建针对该分支的 Pull Request
- 手动触发（workflow_dispatch）

**构建产物：**
- `Image` - 未压缩的内核镜像
- `Image.gz` - Gzip 压缩的内核镜像
- `Image.lz4` - LZ4 压缩的内核镜像
- `boot.img` - 可刷写的启动镜像（header version 4）
- `AnyKernel3-GKI-5.15.zip` - AnyKernel3 刷机包
- `*.ko` - 内核模块（如果有）
- `build_info.txt` - 构建信息
- `RELEASE_NOTES.md` - 发布说明

### 2. `build_gki_ksu.yml` - KernelSU 集成构建

这是包含 KernelSU 的内核构建工作流。

**特性：**
- ✅ 集成 KernelSU
- ✅ 自动化构建流程
- ✅ 定时构建（每天一次）

**触发条件：**
- 每天自动构建（UTC 00:00）
- 手动触发（workflow_dispatch）

## 时间戳处理

### 问题背景

默认情况下，为了实现可重现构建（reproducible builds），内核构建系统会使用固定的时间戳（通常是 Unix 纪元时间 1970-01-01）。这会导致内核版本字符串显示错误的构建时间。

### 解决方案

我们的工作流通过以下方式确保使用正确的构建时间戳：

1. **设置环境变量**：
   ```bash
   KBUILD_BUILD_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
   SOURCE_DATE_EPOCH=$(date +%s)
   ```

2. **传递给 Bazel 构建**：
   ```bash
   tools/bazel build \
     --action_env=KBUILD_BUILD_TIMESTAMP="$KBUILD_BUILD_TIMESTAMP" \
     --action_env=SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
     //common:kernel_aarch64_dist
   ```

3. **验证时间戳**：
   构建完成后，工作流会自动检查内核版本字符串，确保时间戳正确。

## 使用方法

### 方法 1: 自动构建

当您推送代码到配置的分支时，工作流会自动触发。

### 方法 2: 手动触发

1. 在 GitHub 上打开仓库
2. 点击 "Actions" 标签
3. 选择 "Build GKI Kernel" 工作流
4. 点击 "Run workflow" 按钮
5. 选择分支并确认

### 方法 3: 本地构建

如果您想在本地使用相同的配置构建：

```bash
# 克隆仓库
git clone <repository-url>
cd android_gki_kernel_5.15_common

# 使用构建脚本（已包含时间戳处理）
./build_gki.sh
```

## 配置修复

工作流自动应用以下配置修复：

1. **ZRAM 模块化**
   - 将 `CONFIG_ZRAM=y` 改为 `CONFIG_ZRAM=m`
   - 将 `CONFIG_ZSMALLOC=y` 改为 `CONFIG_ZSMALLOC=m`
   - 添加到 `gki_system_dlkm_modules` 列表

2. **符号导出**
   - 导出 `task_is_booster` 符号
   - 添加到 KMI 符号列表

3. **版本字符串清理**
   - 移除 `-maybe-dirty` 后缀

## 刷机说明

### 方法 1: 使用 Fastboot 刷写 boot.img

```bash
# 进入 fastboot 模式
adb reboot bootloader

# 刷写内核
fastboot flash boot boot.img

# 重启设备
fastboot reboot
```

### 方法 2: 使用 AnyKernel3 刷机包

1. 将设备重启到 Recovery 模式（推荐使用 TWRP）
2. 在 Recovery 中选择 "Install" 或 "安装"
3. 选择 `AnyKernel3-GKI-5.15.zip` 文件
4. 滑动确认刷入
5. 重启设备

## 构建环境

- **操作系统**: Ubuntu Latest (GitHub Actions)
- **内核版本**: Linux 5.15.194
- **Android 版本**: Android 13
- **目标架构**: AArch64 (ARM64)
- **工具链**: Clang r547379
- **构建系统**: Bazel

## 故障排除

### 构建失败

如果构建失败，请检查：

1. **磁盘空间**: 工作流会自动清理空间，但某些情况下可能不够
2. **依赖项**: 确保所有必需的包都已安装
3. **配置冲突**: 检查是否有本地配置与工作流冲突

### 时间戳仍然显示 1970

如果构建的内核仍然显示纪元时间：

1. 检查 `KBUILD_BUILD_TIMESTAMP` 环境变量是否正确设置
2. 确认 Bazel 构建时使用了 `--action_env` 参数
3. 查看构建日志中的时间戳相关信息

### ABI 兼容性问题

如果遇到 ABI 检查失败：

1. 确保所有必需的符号都在 KMI 列表中
2. 检查是否有不兼容的内核修改
3. 考虑使用 `BPF_KO_CONF_CHECK=0` 跳过检查（仅用于开发）

## 自定义配置

如需自定义构建配置，可以修改：

- `.github/workflows/build_gki.yml` - 工作流配置
- `build.config.gki.aarch64` - GKI 构建配置
- `arch/arm64/configs/gki_defconfig` - 内核配置
- `build_gki.sh` - 本地构建脚本

## 贡献

如果您想改进工作流或报告问题：

1. Fork 仓库
2. 创建功能分支
3. 提交更改
4. 创建 Pull Request

## 许可证

本项目遵循 GPL-2.0 许可证。

## 相关资源

- [Android GKI 官方文档](https://source.android.com/docs/core/architecture/kernel/generic-kernel-image)
- [内核构建教程](../../BUILD_GKI_TUTORIAL_ZH.md)
- [Bazel 构建系统](https://bazel.build/)
- [AnyKernel3 项目](https://github.com/osm0sis/AnyKernel3)

## 更新日志

### 2024-12-04
- ✅ 创建标准 GKI 构建工作流
- ✅ 实现正确的时间戳处理
- ✅ 添加自动配置修复
- ✅ 生成多种格式的构建产物
- ✅ 创建详细的构建文档

---

**最后更新**: 2024-12-04
