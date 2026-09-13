#!/system/bin/sh
# Sourced before a regular module is removed. Backend cleanup is optional.
MODULE_ID="${1:-}"
ROOT="/data/adb/AnyMeta"
ACTIVE="$(cat "$ROOT/state/active" 2>/dev/null || printf '%s' meta-overlayfs)"
BACKEND="$ROOT/runtime/metauninstall.sh"
if [ -n "$MODULE_ID" ] && [ -r "$BACKEND" ]; then
  export ANYMETA_ROOT="$ROOT" ANYMETA_ACTIVE="$ACTIVE" MODULE_ID
  . "$BACKEND"
fi
printf '[AnyMeta] preserved state for %s\n' "$MODULE_ID" > /dev/kmsg
