#!/system/bin/sh
ROOT="/data/adb/AnyMeta"
ACTIVE="$(cat "$ROOT/state/active" 2>/dev/null || printf '%s' meta-overlayfs)"
printf '[AnyMeta] active backend: %s\n' "$ACTIVE" > /dev/kmsg
MODDIR="${0%/*}"; tmp="$ROOT/state/update-available.tmp"
if "$MODDIR/anymeta.sh" check-update "$ACTIVE" > "$tmp" 2>/dev/null; then
  mv "$tmp" "$ROOT/state/update-available"
  printf '[AnyMeta] backend update available: %s\n' "$ACTIVE" > /dev/kmsg
else
  rm -f "$tmp" "$ROOT/state/update-available"
fi
