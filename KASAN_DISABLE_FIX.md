# KASAN 禁用修复说明

## 问题描述

禁用 KASAN 后刷入内核导致**无限重启**的问题。

## 根本原因

1. **符号依赖问题**: 某些 vendor 模块（厂商驱动模块）依赖 `kasan_flag_enabled` 符号
2. **符号缺失**: 当 `CONFIG_KASAN_HW_TAGS` 被禁用时，`mm/kasan/hw_tags.c` 不会被编译
3. **模块加载失败**: vendor 模块尝试加载时找不到 `kasan_flag_enabled` 符号，导致系统无法正常启动

## 解决方案

### 1. 创建 Stub 实现

创建了 `mm/kasan/stub.c` 文件，即使 KASAN 被禁用也提供 `kasan_flag_enabled` 符号：

```c
DEFINE_STATIC_KEY_FALSE(kasan_flag_enabled);
EXPORT_SYMBOL(kasan_flag_enabled);
```

### 2. 修改 Makefile

修改 `mm/kasan/Makefile`，当 KASAN 被禁用时编译 stub 文件：

```makefile
# Provide stub symbols for vendor modules even when KASAN is disabled
ifeq ($(CONFIG_KASAN),)
obj-y += stub.o
endif
```

### 3. 恢复 ABI 符号

将 `kasan_flag_enabled` 重新添加到所有 ABI 符号列表中，确保 KMI 兼容性。

## 技术细节

### 为什么需要这个符号？

- **Vendor 模块兼容性**: 某些厂商的驱动模块在编译时链接了 `kasan_flag_enabled` 符号
- **GKI 要求**: Android GKI 内核需要保持 ABI 兼容性，即使某些功能被禁用
- **向后兼容**: 确保旧版本的 vendor 模块可以在新内核上正常工作

### Stub 实现的工作原理

- `DEFINE_STATIC_KEY_FALSE`: 定义一个始终为 `false` 的静态键
- `EXPORT_SYMBOL`: 导出符号供模块使用
- 当 KASAN 被禁用时，这个符号始终返回 `false`，不会影响系统行为

## 验证方法

### 1. 检查符号是否存在

```bash
# 在构建后的内核中检查
nm vmlinux | grep kasan_flag_enabled
```

### 2. 检查模块依赖

```bash
# 检查哪些模块依赖这个符号
modinfo <module.ko> | grep kasan
```

### 3. 测试启动

刷入修复后的内核，验证：
- ✅ 系统能正常启动
- ✅ 所有 vendor 模块能正常加载
- ✅ 无无限重启问题

## 注意事项

1. **性能影响**: Stub 实现非常轻量，几乎无性能影响
2. **内存占用**: 只是一个静态键定义，占用内存极小
3. **兼容性**: 这个修复确保了与现有 vendor 模块的兼容性

## 相关文件

- `mm/kasan/stub.c` - Stub 实现
- `mm/kasan/Makefile` - 构建配置
- `android/abi_gki_aarch64*` - ABI 符号列表

## 总结

这个修复确保了：
- ✅ KASAN 可以被安全禁用
- ✅ Vendor 模块可以正常加载
- ✅ 系统可以正常启动
- ✅ 保持 GKI ABI 兼容性

**重要**: 禁用 KASAN 后必须使用修复后的内核，否则会导致无限重启。

