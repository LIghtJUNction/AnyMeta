#!/system/bin/sh
# AnyMeta is the stable KernelSU metamodule entrypoint. The selected backend
# lives outside /data/adb/modules and is executed with its original directory.
MODDIR="${0%/*}"
ROOT="/data/adb/AnyMeta"
ACTIVE="$(cat "$ROOT/state/active" 2>/dev/null || printf '%s' meta-overlayfs)"
BACKEND="$ROOT/runtime/metamount.sh"
printf '[AnyMeta] delegating mount to %s\n' "$ACTIVE" > /dev/kmsg
if [ -r "$BACKEND" ]; then
  export ANYMETA_ROOT="$ROOT" ANYMETA_ACTIVE="$ACTIVE" KSU_METAMODULE="AnyMeta" MODDIR="$ROOT/runtime"
  sh "$BACKEND"
else
  printf '[AnyMeta] backend %s is unavailable; refusing an unsafe fallback mount\n' "$ACTIVE" > /dev/kmsg
fi
