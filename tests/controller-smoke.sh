#!/bin/sh
set -eu

unset CDPATH
PROJECT_ROOT=$(cd -- "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/anymeta-controller.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir -p "$WORK/root" "$WORK/bin" "$WORK/packages/main" "$WORK/packages/dep"
mkdir -p "$WORK/modules/application"
printf 'id=application\n' > "$WORK/modules/application/module.prop"

cat > "$WORK/bin/ksud" <<'EOF'
#!/bin/sh
for argument do last=$argument; done
printf '%s\n' "$last" >> "$ANYMETA_TEST_INSTALL_LOG"
EOF
chmod 0755 "$WORK/bin/ksud"

printf 'id=dep\n' > "$WORK/packages/dep/module.prop"
(cd "$WORK/packages/dep" && zip -q "$WORK/dep.zip" module.prop)
printf 'id=application\ndepends=dep\n' > "$WORK/packages/main/module.prop"
(cd "$WORK/packages/main" && zip -q "$WORK/main.zip" module.prop)
printf '{"dep":{"url":"file://%s/dep.zip"}}\n' "$WORK" > "$WORK/root/registry.json"

ANYMETA_ROOT="$WORK/root" ANYMETA_MODULES_DIR="$WORK/modules" ANYMETA_TEST_INSTALL_LOG="$WORK/install.log" PATH="$WORK/bin:$PATH" \
  sh "$PROJECT_ROOT/src/AnyMeta/anymeta.sh" install "$WORK/main.zip"
sed -n '1p' "$WORK/install.log" | grep -F '/dep.zip' >/dev/null
sed -n '2p' "$WORK/install.log" | grep -F '/main.zip' >/dev/null

rm -f "$WORK/install.log"
rm -f "$WORK/root/cache/modules/dep.zip"
rm -rf "$WORK/modules/application"
printf 'id=dep\ndepends=application\n' > "$WORK/packages/dep/module.prop"
(cd "$WORK/packages/dep" && zip -q -FS "$WORK/dep.zip" module.prop)
if ANYMETA_ROOT="$WORK/root" ANYMETA_MODULES_DIR="$WORK/modules" ANYMETA_TEST_INSTALL_LOG="$WORK/install.log" PATH="$WORK/bin:$PATH" \
  sh "$PROJECT_ROOT/src/AnyMeta/anymeta.sh" install "$WORK/main.zip"; then
  echo 'cycle was accepted' >&2
  exit 1
fi
[ ! -s "$WORK/install.log" ]
grep -F 'dependency cycle detected at application' "$WORK/root/state/anymeta.log" >/dev/null
echo 'controller smoke: ok'
