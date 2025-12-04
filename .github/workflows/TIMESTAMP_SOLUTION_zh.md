# 内核构建时间戳问题解决方案

## 问题描述

在构建 Android GKI 内核时，默认情况下内核版本字符串会显示错误的构建时间：

```
Linux version 5.15.194 (...) #1 SMP PREEMPT Thu Jan 1 00:00:00 UTC 1970
```

这是因为为了实现可重现构建（reproducible builds），构建系统会使用固定的时间戳（Unix 纪元时间）。

## 期望结果

内核版本字符串应该显示实际的构建时间：

```
Linux version 5.15.194 (...) #1 SMP PREEMPT Wed Dec 4 12:34:56 UTC 2024
```

## 解决方案

### 方法对比

| 方法 | 说明 | 效果 |
|------|------|------|
| **默认构建** | 使用固定的 `SOURCE_DATE_EPOCH=0` | ❌ 显示 1970-01-01 |
| **本地脚本** | `build_gki.sh` 设置环境变量 | ✅ 显示正确时间 |
| **新工作流** | `build_gki.yml` 传递时间戳给 Bazel | ✅ 显示正确时间 |

### 实现细节

#### 1. 设置环境变量

```bash
# 当前 UTC 时间（可读格式）
KBUILD_BUILD_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Unix 时间戳
SOURCE_DATE_EPOCH=$(date +%s)
```

#### 2. 传递给构建系统

**Bazel 构建（工作流方式）**:
```bash
tools/bazel build \
  --action_env=KBUILD_BUILD_TIMESTAMP="$KBUILD_BUILD_TIMESTAMP" \
  --action_env=SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
  //common:kernel_aarch64_dist
```

**传统构建（脚本方式）**:
```bash
export KBUILD_BUILD_TIMESTAMP="$BUILD_TIMESTAMP"
export SOURCE_DATE_EPOCH=$(date +%s)
tools/bazel build //common:kernel_aarch64_dist
```

#### 3. 验证结果

```bash
# 从内核镜像中提取版本字符串
strings Image | grep "Linux version"
```

预期输出应包含实际构建时间，而不是 1970 年。

## 工作流实现

### 关键步骤

我们的 `build_gki.yml` 工作流在以下步骤中处理时间戳：

#### Step 1: Configure Build Timestamps
```yaml
- name: Configure Build Timestamps
  run: |
    BUILD_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    BUILD_TIMESTAMP_UNIX=$(date +%s)
    
    echo "KBUILD_BUILD_TIMESTAMP=$BUILD_TIMESTAMP" >> $GITHUB_ENV
    echo "SOURCE_DATE_EPOCH=$BUILD_TIMESTAMP_UNIX" >> $GITHUB_ENV
```

#### Step 2: Build Kernel
```yaml
- name: Build Kernel
  run: |
    tools/bazel build \
      --action_env=KBUILD_BUILD_TIMESTAMP="$KBUILD_BUILD_TIMESTAMP" \
      --action_env=SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
      --config=fast \
      //common:kernel_aarch64_dist
```

#### Step 3: Verify Kernel Image
```yaml
- name: Extract Kernel Version
  run: |
    VERSION_STRING=$(strings "$KERNEL_IMAGE" | grep "Linux version" | head -n 1)
    
    if echo "$VERSION_STRING" | grep -q "1970"; then
        echo "WARNING: Kernel still has epoch timestamp!"
    else
        echo "SUCCESS: Kernel has correct build timestamp!"
    fi
```

## 技术背景

### 为什么默认使用固定时间戳？

1. **可重现构建**：确保相同的源码生成相同的二进制文件
2. **验证完整性**：便于验证构建产物的一致性
3. **安全考虑**：防止时间戳泄露构建环境信息

### 我们为什么需要实际时间戳？

1. **版本识别**：方便识别内核构建的具体时间
2. **问题追踪**：便于追踪特定版本的问题
3. **用户体验**：用户可以看到内核的实际构建日期

### 环境变量说明

| 变量 | 用途 | 格式 | 示例 |
|------|------|------|------|
| `KBUILD_BUILD_TIMESTAMP` | 内核版本字符串 | 可读日期时间 | `2024-12-04 12:34:56 UTC` |
| `SOURCE_DATE_EPOCH` | 构建系统时间戳 | Unix 时间戳 | `1701691696` |

## 与其他构建方法的兼容性

### Bazel 构建（推荐）

✅ **完全支持** - 使用 `--action_env` 传递环境变量

### 传统 build.sh 构建

✅ **支持** - 通过 export 设置环境变量

### 本地构建脚本 (build_gki.sh)

✅ **已实现** - 脚本内部已处理时间戳

## 验证方法

### 方法 1: 查看内核版本字符串

```bash
strings Image | grep "Linux version"
```

### 方法 2: 启动设备后检查

```bash
adb shell uname -a
# 或
adb shell cat /proc/version
```

### 方法 3: 工作流日志

查看 "Extract Kernel Version" 步骤的输出。

## 常见问题

### Q1: 时间戳为什么还是 1970？

**可能原因**:
- 环境变量未正确设置
- Bazel 构建时未传递 `--action_env`
- `stamp.bzl` 文件覆盖了设置

**解决方法**:
- 检查工作流日志中的环境变量
- 确认 Bazel 命令包含 `--action_env` 参数
- 确认 `stamp.bzl` 补丁已应用

### Q2: 每次构建时间戳都不同，影响可重现构建吗？

**答**: 是的，这会影响可重现构建。但对于个人使用或调试版本，显示实际构建时间更有意义。如果需要可重现构建，可以设置固定的 `SOURCE_DATE_EPOCH` 值。

### Q3: 可以自定义时间戳格式吗？

**答**: 可以。修改工作流中的 date 命令格式即可：

```bash
# 自定义格式
KBUILD_BUILD_TIMESTAMP=$(date -u +"%Y/%m/%d %H:%M")
```

### Q4: 本地构建如何应用相同的时间戳处理？

**答**: 使用项目提供的 `build_gki.sh` 脚本，它已经包含了时间戳处理逻辑。

## 相关文件

- **工作流**: `.github/workflows/build_gki.yml`
- **本地脚本**: `build_gki.sh`
- **文档**: `.github/workflows/README_zh.md`
- **验证清单**: `.github/workflows/VERIFICATION.md`

## 总结

通过正确设置 `KBUILD_BUILD_TIMESTAMP` 和 `SOURCE_DATE_EPOCH` 环境变量，并将它们传递给 Bazel 构建系统，我们成功解决了内核构建时间戳显示错误的问题。这个解决方案已集成到我们的 GitHub Actions 工作流中，确保每次自动构建都使用正确的时间戳。

---

**参考资源**:
- [Reproducible Builds](https://reproducible-builds.org/)
- [SOURCE_DATE_EPOCH Specification](https://reproducible-builds.org/specs/source-date-epoch/)
- [Linux Kernel Build System](https://www.kernel.org/doc/html/latest/kbuild/index.html)

**最后更新**: 2024-12-04
