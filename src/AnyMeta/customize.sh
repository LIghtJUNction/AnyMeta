#!/system/bin/sh
ui_print "- Installing AnyMeta..."
[ "${KSU:-false}" = "true" ] || abort "! AnyMeta requires KernelSU metamodule support"
PERSIST="/data/adb/AnyMeta"
mkdir -p "$PERSIST/backups" "$PERSIST/state"
adopted=""
for old in /data/adb/modules/*; do
  [ -f "$old/module.prop" ] || continue
  [ "$old" = "$MODPATH" ] && continue
  [ "$(basename "$old")" = "AnyMeta" ] && continue
  old_meta="$(sed -n 's/^metamodule=//p' "$old/module.prop" | head -n1)"
  case "$old_meta" in
    1|true|TRUE)
      old_id="$(basename "$old")"
      ui_print "- Taking over $old_id"
      tar -czf "$PERSIST/backups/${old_id}-before-anymeta-$(date +%Y%m%d-%H%M%S).tar.gz" -C /data/adb/modules "$old_id" 2>/dev/null || abort "! Cannot back up $old_id"
      touch "$old/remove"
      printf '%s\n' "$old_id" > "$PERSIST/state/previous"
      if [ -z "$adopted" ] && [ -f "$old/metamount.sh" ]; then
        rm -rf "$PERSIST/backends/$old_id" "$PERSIST/runtime"
        mkdir -p "$PERSIST/backends/$old_id"
        cp -a "$old/." "$PERSIST/backends/$old_id/" || abort "! Cannot adopt $old_id"
        cp -a "$PERSIST/backends/$old_id" "$PERSIST/runtime" || abort "! Cannot activate $old_id"
        printf '%s\n' "$old_id" > "$PERSIST/state/active"
        adopted="$old_id"
        ui_print "- Activated existing backend $old_id"
      fi
      ;;
  esac
done
if [ -z "$adopted" ] && [ ! -f "$PERSIST/runtime/metamount.sh" ]; then
  seed="$MODPATH/seed/meta-overlayfs.zip"
  [ -f "$seed" ] || abort "! No mount backend available"
  rm -rf "$PERSIST/backends/meta-overlayfs" "$PERSIST/runtime"
  mkdir -p "$PERSIST/backends/meta-overlayfs"
  unzip -q "$seed" -d "$PERSIST/backends/meta-overlayfs" || abort "! Cannot unpack default backend"
  cp -a "$PERSIST/backends/meta-overlayfs" "$PERSIST/runtime" || abort "! Cannot activate default backend"
  printf '%s\n' meta-overlayfs > "$PERSIST/state/active"
  ui_print "- Activated Meta OverlayFS"
fi
rm -rf "$MODPATH/webroot/backend"
[ -d "$PERSIST/runtime/webroot" ] && cp -a "$PERSIST/runtime/webroot" "$MODPATH/webroot/backend"
ui_print "- Backend data will be kept in $PERSIST"
set_perm_recursive "$MODPATH" 0 0 0755 0644
for script in metamount.sh metainstall.sh metauninstall.sh anymeta.sh post-fs-data.sh service.sh boot-completed.sh action.sh; do
  [ -f "$MODPATH/$script" ] && set_perm "$MODPATH/$script" 0 0 0755
done
[ -f "$MODPATH/backends.json" ] && set_perm "$MODPATH/backends.json" 0 0 0644
[ -d "$MODPATH/webroot" ] && set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
ui_print "- Installation complete"
