// SPDX-License-Identifier: GPL-2.0
/*
 * KASAN stub symbols for compatibility when KASAN is disabled.
 * Some vendor modules may depend on these symbols even when KASAN is not enabled.
 */

#include <linux/export.h>
#include <linux/static_key.h>

/*
 * Stub for kasan_flag_enabled when KASAN is disabled.
 * This ensures vendor modules that reference this symbol can still load.
 */
DEFINE_STATIC_KEY_FALSE(kasan_flag_enabled);
EXPORT_SYMBOL(kasan_flag_enabled);

