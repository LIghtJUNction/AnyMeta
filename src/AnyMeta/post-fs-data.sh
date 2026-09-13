#!/system/bin/sh
ROOT="/data/adb/AnyMeta"
mkdir -p "$ROOT/cache" "$ROOT/backends" "$ROOT/state" "$ROOT/backups"
[ -f "$ROOT/state/active" ] || printf '%s\n' meta-overlayfs > "$ROOT/state/active"
METAMODULE_LINK="/data/adb/metamodule"
if [ -L "$METAMODULE_LINK" ]; then
  current="$(readlink "$METAMODULE_LINK" 2>/dev/null || true)"
  if [ "$current" != "/data/adb/modules/AnyMeta" ]; then rm -f "$METAMODULE_LINK"; fi
fi
[ -e "$METAMODULE_LINK" ] || ln -s /data/adb/modules/AnyMeta "$METAMODULE_LINK"
for old in /data/adb/modules/*; do
  [ -f "$old/module.prop" ] || continue
  [ "$(basename "$old")" = "AnyMeta" ] && continue
  case "$(sed -n 's/^metamodule=//p' "$old/module.prop" | head -n1)" in
    1|true|TRUE)
      old_id="$(basename "$old")"
      if [ ! -f "$ROOT/runtime/metamount.sh" ] && [ -f "$old/metamount.sh" ]; then
        rm -rf "$ROOT/backends/$old_id" "$ROOT/runtime"; mkdir -p "$ROOT/backends/$old_id"
        cp -a "$old/." "$ROOT/backends/$old_id/" && cp -a "$ROOT/backends/$old_id" "$ROOT/runtime" && printf '%s\n' "$old_id" > "$ROOT/state/active"
      fi
      touch "$old/remove"; printf '%s\n' "$old_id" > "$ROOT/state/previous"
      ;;
  esac
done
printf '[AnyMeta] persistent state ready; active=%s\n' "$(cat "$ROOT/state/active")" > /dev/kmsg
