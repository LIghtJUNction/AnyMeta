#!/system/bin/sh
# Delegate KernelSU's single metamodule mount hook to the selected backend.
MODDIR="${0%/*}"
ROOT="/data/adb/AnyMeta"
ACTIVE="$(cat "$ROOT/state/active" 2>/dev/null || printf '%s' meta-overlayfs)"
BACKEND="$ROOT/backends/$ACTIVE/metamount.sh"
printf '[AnyMeta] delegating mount to %s\n' "$ACTIVE" > /dev/kmsg
if [ -r "$BACKEND" ]; then
  export ANYMETA_ROOT="$ROOT" ANYMETA_ACTIVE="$ACTIVE" KSU_METAMODULE="AnyMeta"
  MODDIR="$ROOT/backends/$ACTIVE"; export MODDIR
  . "$BACKEND"
else
  printf '[AnyMeta] backend %s is not installed; modules remain unmounted\n' "$ACTIVE" > /dev/kmsg
fi
