#!/system/bin/sh
ROOT="/data/adb/AnyMeta"
ACTIVE="$(cat "$ROOT/state/active" 2>/dev/null || printf '%s' meta-overlayfs)"
printf '[AnyMeta] active backend: %s\n' "$ACTIVE" > /dev/kmsg
