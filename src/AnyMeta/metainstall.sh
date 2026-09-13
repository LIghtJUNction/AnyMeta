#!/system/bin/sh
ui_print "- AnyMeta: preserving module data and delegating installation"
export KSU_HAS_METAMODULE="true" KSU_METAMODULE="AnyMeta"
ROOT="/data/adb/AnyMeta"
ACTIVE="$(cat "$ROOT/state/active" 2>/dev/null || printf '%s' meta-overlayfs)"
BACKEND="$ROOT/runtime/metainstall.sh"
if [ -r "$BACKEND" ]; then
  export ANYMETA_ROOT="$ROOT" ANYMETA_ACTIVE="$ACTIVE" MODDIR="$ROOT/runtime"
  . "$BACKEND"
else
  install_module
fi
