# 快速参考卡 - GKI 内核构建工作流

## 🚀 快速开始

### 触发构建

```bash
# 方式 1: 推送代码（自动触发）
git push origin copilot/create-workflow-script-for-kernel

# 方式 2: 手动触发
# GitHub UI > Actions > Build GKI Kernel > Run workflow

# 方式 3: 本地构建
./build_gki.sh
```

### 查看构建结果

1. 访问 GitHub Actions 页面
2. 选择最新的工作流运行
3. 查看 "Build Summary" 部分
4. 下载 "Artifacts" 中的内核文件

---

## 📋 关键命令

### 验证时间戳

```bash
# 从内核镜像提取版本
strings Image | grep "Linux version"

# 应该显示实际日期，而不是 1970-01-01
# 正确: Wed Dec  4 12:34:56 UTC 2024
# 错误: Thu Jan  1 00:00:00 UTC 1970
```

### 刷入内核

**方法 1: Fastboot**
```bash
adb reboot bootloader
fastboot flash boot boot.img
fastboot reboot
```

**方法 2: AnyKernel3 (TWRP)**
1. 重启到 Recovery
2. 刷入 AnyKernel3-GKI-5.15.zip
3. 重启系统

### 检查设备上的内核

```bash
adb shell uname -a
adb shell cat /proc/version
```

---

## 📦 构建产物

| 文件 | 描述 | 用途 |
|------|------|------|
| **Image** | 未压缩内核 | 调试/分析 |
| **Image.gz** | Gzip 压缩 | 标准刷机 |
| **Image.lz4** | LZ4 压缩 | 快速启动 |
| **boot.img** | 启动镜像 | Fastboot 刷写 |
| **AnyKernel3-GKI-5.15.zip** | 刷机包 | Recovery 刷写 |
| **build_info.txt** | 构建信息 | 版本追踪 |
| **RELEASE_NOTES.md** | 发布说明 | 文档参考 |

---

## 🔧 工作流配置

### 环境变量

```bash
# 构建时间（可读格式）
KBUILD_BUILD_TIMESTAMP="2024-12-04 12:34:56 UTC"

# Unix 时间戳
SOURCE_DATE_EPOCH="1701691696"
```

### Bazel 命令

```bash
tools/bazel build \
  --action_env=KBUILD_BUILD_TIMESTAMP="$KBUILD_BUILD_TIMESTAMP" \
  --action_env=SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
  --config=fast \
  //common:kernel_aarch64_dist
```

---

## 🛠️ 自动配置修复

工作流自动应用以下修复：

### 1. ZRAM 模块化
```bash
CONFIG_ZRAM=y → CONFIG_ZRAM=m
CONFIG_ZSMALLOC=y → CONFIG_ZSMALLOC=m
```

### 2. 符号导出
```bash
# 添加到 kernel/cgroup/cpuset.c
EXPORT_SYMBOL_GPL(task_is_booster);

# 添加到 android/abi_gki_aarch64
task_is_booster
```

### 3. 版本字符串清理
```bash
# 修改 build/kernel/kleaf/impl/stamp.bzl
export LOCALVERSION="-maybe-dirty" → export LOCALVERSION=""
```

---

## ⏱️ 构建时间

| 阶段 | 预计时间 |
|------|----------|
| 依赖安装 | 3-5 分钟 |
| 环境设置 | 5-10 分钟 |
| Repo 同步 | 15-20 分钟 |
| 内核编译 | 30-40 分钟 |
| 打包产物 | 5-10 分钟 |
| **总计** | **60-90 分钟** |

---

## 🐛 故障排除

### 问题 1: 时间戳仍然是 1970

**解决方案**:
1. 检查 "Configure Build Timestamps" 步骤的日志
2. 确认环境变量正确设置
3. 验证 Bazel 命令包含 `--action_env` 参数

### 问题 2: 构建失败 - 磁盘空间不足

**解决方案**:
- 工作流已包含磁盘清理步骤
- GitHub Actions 提供足够空间
- 如仍有问题，检查 "Free Disk Space" 步骤

### 问题 3: ABI 兼容性检查失败

**解决方案**:
- 配置修复已自动应用
- 确认所有必需的符号都在 KMI 列表中
- 开发版本可考虑跳过 ABI 检查

### 问题 4: Repo 同步失败

**解决方案**:
- 网络超时，重新运行工作流
- Repo 工具已包含完整性验证
- 使用 `--depth=1` 减少下载量

---

## 📚 文档索引

| 文档 | 内容 |
|------|------|
| **README_zh.md** | 完整用户指南 |
| **VERIFICATION.md** | 验证清单 |
| **TIMESTAMP_SOLUTION_zh.md** | 技术实现 |
| **PROJECT_SUMMARY_zh.md** | 项目总结 |
| **QUICK_REFERENCE.md** | 本文档 |

---

## 🔗 相关链接

- **仓库**: https://github.com/serein-213/android_gki_kernel_5.15_common
- **分支**: `copilot/create-workflow-script-for-kernel`
- **Actions**: https://github.com/serein-213/android_gki_kernel_5.15_common/actions
- **Android GKI 文档**: https://source.android.com/docs/core/architecture/kernel/generic-kernel-image

---

## ✅ 检查清单

构建前检查：
- [ ] GitHub Actions 可用
- [ ] 分支正确 (`copilot/create-workflow-script-for-kernel`)
- [ ] 有足够的 Actions 分钟数

构建后检查：
- [ ] 所有步骤成功完成
- [ ] 产物已上传
- [ ] 时间戳正确（不是 1970）
- [ ] 所有预期文件都存在

刷机前检查：
- [ ] 已备份原始内核
- [ ] 确认设备兼容性
- [ ] 电池电量充足（>50%）
- [ ] 已安装 ADB/Fastboot 工具

---

## 💡 提示

- **首次构建**: 预计 60-90 分钟
- **产物保留**: 30 天后自动删除
- **测试建议**: 先在非主力设备上测试
- **备份重要**: 刷机前务必备份

---

**最后更新**: 2024-12-04  
**版本**: 1.0  
**状态**: ✅ 生产就绪
