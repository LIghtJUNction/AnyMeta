#!/system/bin/sh
ROOT="/data/adb/AnyMeta"
mkdir -p "$ROOT/cache" "$ROOT/backends" "$ROOT/state" "$ROOT/backups"
[ -f "$ROOT/state/active" ] || printf '%s\n' meta-overlayfs > "$ROOT/state/active"
printf '[AnyMeta] persistent state ready; active=%s\n' "$(cat "$ROOT/state/active")" > /dev/kmsg
