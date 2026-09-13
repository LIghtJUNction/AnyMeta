#!/system/bin/sh
ui_print "- Installing AnyMeta..."
[ "${KSU:-false}" = "true" ] || abort "! AnyMeta requires KernelSU metamodule support"
ui_print "- Backend data will be kept in /data/adb/AnyMeta"
set_perm_recursive "$MODPATH" 0 0 0755 0644
for script in metamount.sh metainstall.sh metauninstall.sh anymeta.sh post-fs-data.sh service.sh boot-completed.sh action.sh; do
  [ -f "$MODPATH/$script" ] && set_perm "$MODPATH/$script" 0 0 0755
done
[ -f "$MODPATH/backends.json" ] && set_perm "$MODPATH/backends.json" 0 0 0644
[ -d "$MODPATH/webroot" ] && set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
ui_print "- Installation complete"
