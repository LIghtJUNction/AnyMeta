SKIPUNZIP=1
[ "${BOOTMODE:-false}" = true ] || abort '! Install from the running Android system'
[ "${KSU:-false}" = true ] || abort '! AnyMeta requires KernelSU'
[ "${ARCH:-}" = arm64 ] || abort '! This downloader requires Android arm64'
unzip -o "$ZIPFILE" module.prop download.json 'bin/*' -d "$MODPATH" >&2 || abort '! Cannot extract downloader'
chmod 0755 "$MODPATH/bin/module-downloader" || abort '! Cannot set executable permission'
ui_print '- Checking network and latest release...'
(
  set -eu
  umask 077
  work=$(mktemp -d "${MODPATH}.download.XXXXXX") || exit 1
  trap 'rm -rf "$work"' 0
  trap 'exit 130' 2
  trap 'exit 143' 1 15
  unset LD_LIBRARY_PATH LD_PRELOAD
  "$MODPATH/bin/module-downloader" -config "$MODPATH/download.json" -out "$work/module.zip" || exit $?
  ui_print '- Verified. Preparing AnyMeta...'
  target="$work/AnyMeta"
  mkdir -p "$target"
  unzip -q "$work/module.zip" -d "$target" || exit 1
  [ "$(sed -n 's/^id=//p' "$target/module.prop" | head -n1)" = AnyMeta ] || exit 1
  (
    MODPATH="$target"
    ZIPFILE="$work/module.zip"
    export MODPATH ZIPFILE
    set +eu
    . "$target/customize.sh"
  ) || exit $?

  # KernelSU rejects a second metamodule before its customize.sh runs. Stage
  # the verified target exactly as KernelSU does, after AnyMeta has backed up
  # and marked the previous metamodule for removal.
  update_dir=/data/adb/modules_update/AnyMeta
  record_dir=/data/adb/modules/AnyMeta
  rm -rf "$update_dir"
  mkdir -p "$update_dir" "$record_dir"
  cp -a "$target/." "$update_dir/" || exit 1
  cp -f "$target/module.prop" "$record_dir/module.prop" || exit 1
  touch "$record_dir/update"
  set_perm_recursive "$update_dir" 0 0 0755 0644
  for script in metamount.sh metainstall.sh metauninstall.sh anymeta.sh post-fs-data.sh service.sh boot-completed.sh action.sh; do
    [ -f "$update_dir/$script" ] && set_perm "$update_dir/$script" 0 0 0755
  done
  metamodule_link=/data/adb/metamodule
  if [ -L "$metamodule_link" ]; then
    rm -f "$metamodule_link"
  elif [ -e "$metamodule_link" ]; then
    ui_print '! Refusing to replace a non-symlink /data/adb/metamodule'
    exit 1
  fi
  ln -s "$record_dir" "$metamodule_link" || exit 1
) || abort '! Download or installation failed; see the error above'
touch "$MODPATH/skip_mount"
ui_print '- AnyMeta will take over after reboot.'
