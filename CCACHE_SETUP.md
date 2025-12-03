# CCache 配置说明

## 概述

本项目已集成 **ccache** 编译器缓存，可以显著加速重复构建。ccache 会缓存编译结果，当相同的源文件被编译时，直接使用缓存结果，避免重复编译。

## 预期效果

- **首次构建**: 无缓存，正常速度（会填充缓存）
- **增量构建**: 缓存命中率通常可达 70-90%，构建时间减少 50-80%
- **清理后重建**: 缓存命中率 60-80%，构建时间减少 40-70%

## 配置说明

### 自动配置

ccache 已自动集成到构建系统中：

1. **build.config.common**: 自动检测并配置 ccache
2. **build_gki.sh**: 显示 ccache 状态和统计信息

### 缓存位置

- **缓存目录**: `../gki_build_workspace/.ccache`
- **默认大小**: 10GB（可通过 `CCACHE_MAXSIZE` 环境变量调整）

### 环境变量

可以通过设置以下环境变量来自定义 ccache 行为：

```bash
# 最大缓存大小（默认 10GB）
export CCACHE_MAXSIZE=10G

# 启用压缩（节省磁盘空间，略微增加 CPU 使用）
export CCACHE_COMPRESS=1

# 压缩级别（1-9，6 是平衡点）
export CCACHE_COMPRESSLEVEL=6

# 缓存策略（允许时间相关的差异）
export CCACHE_SLOPPINESS="pch_defines,time_macros,include_file_mtime,include_file_ctime"

# 禁用统计（设为 1 可略微提升性能）
export CCACHE_NOSTATS=0
```

### 禁用 ccache

如果不想使用 ccache，可以设置：

```bash
export DISABLE_CCACHE=1
```

## 使用方法

### 正常构建

直接运行构建脚本，ccache 会自动启用：

```bash
./build_gki.sh
```

### 查看缓存统计

构建前后会自动显示缓存统计信息。也可以手动查看：

```bash
ccache -s
```

### 清理缓存

如果需要清理缓存（例如磁盘空间不足）：

```bash
ccache -C
```

### 查看缓存详细信息

```bash
# 查看统计信息
ccache -s

# 查看配置
ccache -p

# 查看缓存内容
ccache -z
```

## 性能优化建议

1. **首次构建**: 让构建完成，填充缓存（可能需要正常时间）
2. **增量构建**: 享受缓存带来的速度提升
3. **缓存大小**: 根据磁盘空间调整 `CCACHE_MAXSIZE`
4. **压缩**: 如果磁盘空间有限，保持 `CCACHE_COMPRESS=1`

## 故障排除

### ccache 未生效

1. 检查是否安装了 ccache：
   ```bash
   which ccache
   ccache --version
   ```

2. 检查环境变量：
   ```bash
   echo $CCACHE_DIR
   echo $CCACHE_MAXSIZE
   ```

3. 查看构建日志中的 ccache 状态信息

### 缓存命中率低

- 确保缓存目录有足够的空间
- 检查 `CCACHE_SLOPPINESS` 设置
- 清理缓存后重新构建

### 磁盘空间不足

- 减小 `CCACHE_MAXSIZE`
- 启用压缩：`CCACHE_COMPRESS=1`
- 清理旧缓存：`ccache -C`

## 技术细节

### 构建系统集成

- **传统构建**: 通过 `build.config.common` 中的 `CC` 和 `CXX` 环境变量
- **Bazel 构建**: 通过 `--action_env` 标志传递环境变量

### 缓存键

ccache 使用以下信息生成缓存键：
- 源文件内容
- 编译器版本和路径
- 编译选项
- 预处理器定义

### 兼容性

- ✅ 支持 Clang（LLVM）
- ✅ 支持增量构建
- ✅ 支持清理后重建
- ⚠️ 修改编译选项会降低缓存命中率

## 参考

- [ccache 官方文档](https://ccache.dev/)
- [ccache 手册](https://ccache.dev/manual/latest.html)

