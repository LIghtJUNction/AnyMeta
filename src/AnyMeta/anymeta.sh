#!/system/bin/sh
# AnyMeta controller. Persistent state lives outside /data/adb/modules so a
# backend can be replaced without touching installed modules or their data.
set -u

MODDIR="${0%/*}"
ROOT="${ANYMETA_ROOT:-/data/adb/AnyMeta}"
CACHE="$ROOT/cache"
BACKENDS="$ROOT/backends"
RUNTIME="$ROOT/runtime"
STATE="$ROOT/state"
ACTIVE="$STATE/active"
LOG="$STATE/anymeta.log"
MANIFEST="$MODDIR/backends.json"
PROXY_BASE="${ANYMETA_PROXY_BASE:-https://ghproxy.net/}"
KAM_BIN="$MODDIR/bin/kam"
MODULES_DIR="${ANYMETA_MODULES_DIR:-/data/adb/modules}"

mkdir -p "$CACHE" "$BACKENDS" "$STATE"
log() { mkdir -p "$STATE"; printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG"; }
json_field() { awk -v id="$2" -v key="$3" 'index($0,"\"id\": \"" id "\"") { found=1 } found && index($0,"\"" key "\"") { gsub(/.*"[^"]+"[[:space:]]*:[[:space:]]*"/,""); gsub(/".*/,""); print; exit }' "$1"; }
manifest_ids() { sed -n 's/.*"id": "\([^"]*\)".*/\1/p' "$MANIFEST"; }
known_id() { manifest_ids | grep -Fxq "$1"; }
backend_url() {
  id="$1"; repo="$(json_field "$MANIFEST" "$id" repo)"; release="$(json_field "$MANIFEST" "$id" release)"; asset="$(json_field "$MANIFEST" "$id" asset)"
  printf '%s/releases/download/%s/%s' "$repo" "$release" "$asset"
}
backend_version() { sed -n 's/^version=//p' "$BACKENDS/$1/module.prop" 2>/dev/null | head -n1; }
verify_sha() {
  id="$1"; file="$2"; expected="$(json_field "$MANIFEST" "$id" sha256)"
  [ -z "$expected" ] && return 0
  command -v sha256sum >/dev/null 2>&1 || { log "sha256sum unavailable; refusing unverifiable backend $id"; return 1; }
  actual="$(sha256sum "$file" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || { log "checksum mismatch for $id: $actual != $expected"; return 1; }
}
download() {
  id="$1"; file="$CACHE/$id.zip"; url="$(backend_url "$id")"
  [ -s "$file" ] && verify_sha "$id" "$file" && { printf '%s\n' "$file"; return 0; }
  rm -f "$file"
  log "downloading $id from $url"
  if ! curl -fL --retry 2 --connect-timeout 12 -o "$file.tmp" "$url"; then
    proxy="${PROXY_BASE%/}/$url"
    log "direct download failed; trying proxy $proxy"
    curl -fL --retry 2 --connect-timeout 12 -o "$file.tmp" "$proxy" || { rm -f "$file.tmp"; return 1; }
  fi
  mv "$file.tmp" "$file"
  verify_sha "$id" "$file" || { rm -f "$file"; return 1; }
  printf '%s\n' "$file"
}
unpack() {
  id="$1"; zip="$2"; dest="${3:-$BACKENDS/$id}"; tmp="$ROOT/.extract-$id-$$"
  rm -rf "$tmp" "$dest"; mkdir -p "$tmp" "$dest"
  unzip -q "$zip" -d "$tmp" || { rm -rf "$tmp" "$dest"; return 1; }
  root="$(find "$tmp" -type f -name module.prop -print -quit)"
  [ -n "$root" ] || { log "backend $id has no module.prop"; rm -rf "$tmp" "$dest"; return 1; }
  root="$(dirname "$root")"
  cp -a "$root/." "$dest/"
  printf '%s\n' "$(date +%s)" > "$dest/.installed"
  rm -rf "$tmp"
}
activate_runtime() {
  id="$1"; src="$BACKENDS/$id"; next="$ROOT/.runtime-next-$$"; old="$ROOT/.runtime-old-$$"
  [ -f "$src/metamount.sh" ] || { log "backend $id has no metamount.sh"; return 1; }
  rm -rf "$next" "$old"; cp -a "$src" "$next"
  if [ -d "$RUNTIME" ]; then mv "$RUNTIME" "$old"; fi
  mv "$next" "$RUNTIME"; rm -rf "$old"
  if [ -d "$MODDIR/webroot" ]; then
    rm -rf "$MODDIR/webroot/backend"
    [ -d "$RUNTIME/webroot" ] && cp -a "$RUNTIME/webroot" "$MODDIR/webroot/backend"
  fi
  printf '%s\n' "$id" > "$ACTIVE"; log "runtime activated: $id"
}
module_prop() { sed -n "s/^$2=//p" "$1/module.prop" 2>/dev/null | head -n1; }
registry_url() {
  local id
  id="$1"
  [ -s "$ROOT/registry.json" ] || return 1
  awk -v id="$id" 'index($0,"\"" id "\"") { found=1 } found && /"url"[[:space:]]*:/ { gsub(/.*"url"[[:space:]]*:[[:space:]]*"/,""); gsub(/".*/,""); print; exit }' "$ROOT/registry.json"
}
fetch_dependency() {
  local id stage file url tmp proxy prop_nested root_nested api official path slug asset asset_block digest actual
  id="$1"; stage="$2"; file="$ROOT/cache/modules/$id.zip"; mkdir -p "$(dirname "$file")"
  if [ ! -s "$file" ]; then
    official=0; url="$(registry_url "$id" 2>/dev/null || true)"
    if [ -z "$url" ]; then
      api="$STATE/registry-$id.$$.json"
      curl -fsSL --connect-timeout 12 "https://modules.kernelsu.org/module/$id.json" -o "$api" || { rm -f "$api"; log "dependency $id is not in the KernelSU repository"; return 1; }
      url="$(awk -F'"downloadUrl":"' '{ for (i=2; i<=NF; i++) { split($i, value, "\""); if (value[1] ~ /\.zip$/) { print value[1]; exit } } }' "$api")"; rm -f "$api"; official=1
    fi
    printf '%s' "$url" | grep -Eq '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/releases/download/[^/]+/[^/]+\.zip$|^file://' || { log "invalid dependency URL for $id"; return 1; }
    tmp="$file.tmp.$$"; rm -f "$tmp"
    curl -fL --retry 2 --connect-timeout 12 -o "$tmp" "$url" || {
      proxy="${PROXY_BASE%/}/$url"
      curl -fL --retry 2 --connect-timeout 12 -o "$tmp" "$proxy" || { rm -f "$tmp"; return 1; }
    }
    if [ "$official" = 1 ]; then
      path="${url#https://github.com/}"; slug="${path%%/releases/download/*}"; asset="${url##*/}"; api="$STATE/dependency-$id.$$.json"
      curl -fsSL --connect-timeout 12 "https://api.github.com/repos/$slug/releases/latest" -o "$api" || { rm -f "$api" "$tmp"; return 1; }
      asset_block="$(awk -v asset="$asset" 'BEGIN { RS="\n    }," } index($0,"\"name\": \"" asset "\"") { print; exit }' "$api")"
      digest="$(printf '%s\n' "$asset_block" | sed -n 's/.*"digest": "sha256:\([0-9a-fA-F]\{64\}\)".*/\1/p' | head -n1)"; rm -f "$api"
      [ -n "$digest" ] || { rm -f "$tmp"; log "dependency $id has no trusted digest"; return 1; }
      actual="$(sha256sum "$tmp" | awk '{print $1}')"; [ "$actual" = "$digest" ] || { rm -f "$tmp"; log "dependency checksum mismatch for $id"; return 1; }
    fi
    mv "$tmp" "$file"
  fi
  rm -rf "$stage/$id"; mkdir -p "$stage/$id"
  unzip -q "$file" -d "$stage/$id" || { rm -f "$file"; rm -rf "$stage/$id"; return 1; }
  prop_nested="$(find "$stage/$id" -name module.prop -print -quit)"; [ -n "$prop_nested" ] || return 1
  root_nested="$(dirname "$prop_nested")"; [ "$root_nested" = "$stage/$id" ] || cp -a "$root_nested/." "$stage/$id/"
  cp -f "$file" "$ROOT/state/install-files-$$/$id.zip"
}
install_zip() {
  local file
  file="$1"; [ -f "$file" ] || return 1
  command -v ksud >/dev/null 2>&1 || { log "ksud unavailable; downloaded package kept at $file"; return 2; }
  # KernelSU versions expose the same module install operation with either
  # positional or --zip syntax; try the positional form first.
  ksud module install "$file" 2>/dev/null || ksud module install --zip "$file"
}
resolve_dependencies() {
  local root visiting done_file prop id deps dep dep_root
  root="$1"; visiting="$2"; done_file="$3"; prop="$root/module.prop"
  [ -f "$prop" ] || return 0
  id="$(module_prop "$root" id)"; case " $(cat "$done_file" 2>/dev/null) " in *" $id "*) return 0 ;; esac
  case " $visiting " in *" $id "*) log "dependency cycle detected at $id"; return 3 ;; esac
  deps="$(module_prop "$root" depends | tr ',;' '  ')"
  for dep in $deps; do
    printf '%s' "$dep" | grep -Eq '^[A-Za-z0-9_.-]+$' || { log "invalid dependency id $dep"; return 4; }
    [ -f "$MODULES_DIR/$dep/module.prop" ] && continue
    dep_root="$ROOT/dependency-staging/$dep"
    [ -d "$dep_root" ] || fetch_dependency "$dep" "$ROOT/dependency-staging" || { log "missing dependency $dep for $id"; return 4; }
    resolve_dependencies "$dep_root" "$visiting $id" "$done_file" || return
  done
  printf '%s\n' "$id" >> "$done_file"
}
install_package() {
  local file stage files nested dep prop_nested root_nested prop root order dep_file main_id embedded embedded_id
  file="$1"; stage="$ROOT/dependency-staging"; files="$ROOT/state/install-files-$$"
  rm -rf "$stage"; mkdir -p "$stage/main"
  rm -rf "$files"; mkdir -p "$files"; cp -f "$file" "$files/main.zip"
  unzip -q "$file" -d "$stage/main" || return 1
  for nested in "$stage/main"/dependencies/*.zip; do
    [ -f "$nested" ] || continue
    embedded="$stage/.embedded-$$"; rm -rf "$embedded"; mkdir -p "$embedded"
    unzip -q "$nested" -d "$embedded" || return 1
    prop_nested="$(find "$embedded" -name module.prop -print -quit)"; [ -n "$prop_nested" ] || return 1
    root_nested="$(dirname "$prop_nested")"; embedded_id="$(module_prop "$root_nested" id)"
    printf '%s' "$embedded_id" | grep -Eq '^[A-Za-z0-9_.-]+$' || return 1
    rm -rf "$stage/$embedded_id"; mkdir -p "$stage/$embedded_id"; cp -a "$root_nested/." "$stage/$embedded_id/"
    cp -f "$nested" "$files/$embedded_id.zip"; rm -rf "$embedded"
  done
  prop="$(find "$stage/main" -name module.prop -print -quit)"; [ -n "$prop" ] || return 1
  root="$(dirname "$prop")"; main_id="$(module_prop "$root" id)"; [ -n "$main_id" ] || return 1
  if [ "$main_id" != main ]; then rm -rf "$stage/$main_id"; ln -s main "$stage/$main_id" || return 1; fi
  order="$ROOT/state/install-order.$$"; : > "$order"
  resolve_dependencies "$root" "" "$order" || { rm -f "$order"; return 1; }
  while IFS= read -r dep; do
    [ "$dep" != "$main_id" ] && [ -f "$MODULES_DIR/$dep/module.prop" ] && continue
    if [ "$dep" = "$main_id" ]; then dep_file="$files/main.zip"; else dep_file="$files/$dep.zip"; fi
    [ -f "$dep_file" ] || { log "dependency $dep resolved but package is unavailable"; rm -rf "$stage" "$files"; rm -f "$order"; return 1; }
    install_zip "$dep_file" || { rm -rf "$stage" "$files"; rm -f "$order"; return 1; }
  done < "$order"
  rm -f "$order"; rm -rf "$stage" "$files"
}
install_registry() {
  local id stage files package
  id="$1"; printf '%s' "$id" | grep -Eq '^[A-Za-z0-9_.-]+$' || return 2
  stage="$ROOT/dependency-staging"; files="$ROOT/state/install-files-$$"; package="$ROOT/cache/modules/$id.zip"
  rm -rf "$stage" "$files"; mkdir -p "$stage" "$files"
  fetch_dependency "$id" "$stage" || { rm -rf "$stage" "$files"; return 1; }
  rm -rf "$stage" "$files"
  install_package "$package"
}
git_build() {
  repo="$1"; ref="${2:-HEAD}"; work="$ROOT/state/git-build-$$"; mkdir -p "$work/src"
  if command -v git >/dev/null 2>&1; then
    if [ -n "${2:-}" ]; then git clone --depth 1 --branch "$2" "$repo" "$work/src"; else git clone --depth 1 "$repo" "$work/src"; fi || { rm -rf "$work"; return 1; }
  else
    slug="${repo#https://github.com/}"; slug="${slug%.git}"
    printf '%s' "$slug" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || { log "git unavailable and repository is not a GitHub HTTPS URL"; rm -rf "$work"; return 2; }
    printf '%s' "$ref" | grep -Eq '^[A-Za-z0-9_./-]+$' || { rm -rf "$work"; return 2; }
    archive="$work/source.tar.gz"; url="https://codeload.github.com/$slug/tar.gz/$ref"
    curl -fL --retry 2 --connect-timeout 12 -o "$archive" "$url" || { rm -rf "$work"; return 1; }
    tar -xzf "$archive" --strip-components=1 -C "$work/src" || { rm -rf "$work"; return 1; }
  fi
  if [ -x "$KAM_BIN" ]; then kam="$KAM_BIN"; else kam="$(command -v kam 2>/dev/null || true)"; fi
  [ -n "$kam" ] || { log "kam unavailable on device; clone retained at $work/src"; return 2; }
  (cd "$work/src" && "$kam" build) || { rm -rf "$work"; return 1; }
  artifact="$(find "$work/src/dist" -type f -name '*.zip' -print -quit)"; [ -n "$artifact" ] || return 1
  install_package "$artifact"; rm -rf "$work"
}
ensure_backend() {
  id="$1"; known_id "$id" || { log "unknown backend $id"; return 2; }
  [ -f "$BACKENDS/$id/metamount.sh" ] && return 0
  zip="$(download "$id")" || return 1
  staged="$ROOT/.backend-$id-$$"
  unpack "$id" "$zip" "$staged" || { rm -rf "$staged"; return 1; }
  [ -f "$staged/metamount.sh" ] || { rm -rf "$staged"; return 1; }
  old="$ROOT/.backend-old-$id-$$"; rm -rf "$old"
  [ -d "$BACKENDS/$id" ] && mv "$BACKENDS/$id" "$old"
  mv "$staged" "$BACKENDS/$id" || { rm -rf "$staged"; [ -d "$old" ] && mv "$old" "$BACKENDS/$id"; return 1; }
  rm -rf "$old"
}
status() {
  active="$(cat "$ACTIVE" 2>/dev/null || printf '%s' meta-overlayfs)"
  printf 'active=%s\nroot=%s\ncache=%s\n' "$active" "$ROOT" "$(du -sh "$CACHE" 2>/dev/null | awk '{print $1}')"
}
list() {
  active="$(cat "$ACTIVE" 2>/dev/null || true)"
  ids="$STATE/manifest-ids.$$"; manifest_ids > "$ids"
  while IFS= read -r id; do
    name="$(json_field "$MANIFEST" "$id" name)"; desc="$(json_field "$MANIFEST" "$id" description)"
    installed=0; [ -f "$BACKENDS/$id/metamount.sh" ] && installed=1
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "$installed" "$([ "$active" = "$id" ] && echo 1 || echo 0)" "$desc"
  done < "$ids"
  rm -f "$ids"
}
use_backend() {
  id="$1"; ensure_backend "$id" || return 1
  activate_runtime "$id" || return 1
  printf 'active=%s\nruntime=%s\n' "$id" "$RUNTIME"
}
check_update() {
  id="${1:-$(cat "$ACTIVE" 2>/dev/null || printf '%s' meta-overlayfs)}"; known_id "$id" || return 2
  repo="$(json_field "$MANIFEST" "$id" repo)"; current="$(backend_version "$id")"
  latest="$(curl -fsSL --connect-timeout 8 "https://api.github.com/repos/${repo#https://github.com/}/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -n1 || true)"
  printf 'id=%s\ncurrent=%s\nlatest=%s\n' "$id" "$current" "$latest"
  [ -n "$latest" ] && [ "${latest#v}" != "${current#v}" ]
}
update_backend() {
  local id repo api new_zip current_asset want asset_block url digest actual proxy staged old
  id="${1:-$(cat "$ACTIVE" 2>/dev/null || printf '%s' meta-overlayfs)}"; known_id "$id" || return 2
  repo="$(json_field "$MANIFEST" "$id" repo)"; api="$STATE/latest-$id.$$.json"; new_zip="$CACHE/$id.update.$$"
  curl -fsSL --connect-timeout 12 "https://api.github.com/repos/${repo#https://github.com/}/releases/latest" -o "$api" || { rm -f "$api"; return 1; }
  current_asset="$(json_field "$MANIFEST" "$id" asset)"; want=""
  case "$current_asset" in *arm64*) want=arm64 ;; *universal*) want=universal ;; esac
  asset_block="$(awk -v want="$want" 'BEGIN { RS="\n    }," } /"browser_download_url": "[^"]*\.zip"/ { if ($0 ~ /-debug\.zip"/) next; if (want == "" || index($0,want)) { print; found=1; exit } if (fallback == "") fallback=$0 } END { if (!found && fallback != "") print fallback }' "$api")"
  url="$(printf '%s\n' "$asset_block" | sed -n 's/.*"browser_download_url": "\([^"]*\.zip\)".*/\1/p' | head -n1)"
  digest="$(printf '%s\n' "$asset_block" | sed -n 's/.*"digest": "sha256:\([0-9a-fA-F]\{64\}\)".*/\1/p' | head -n1)"; rm -f "$api"
  [ -n "$url" ] && [ -n "$digest" ] || { log "latest release for $id has no verifiable ZIP asset"; return 1; }
  if ! curl -fL --retry 2 --connect-timeout 12 -o "$new_zip" "$url"; then
    proxy="${PROXY_BASE%/}/$url"
    curl -fL --retry 2 --connect-timeout 12 -o "$new_zip" "$proxy" || { rm -f "$new_zip"; return 1; }
  fi
  actual="$(sha256sum "$new_zip" | awk '{print $1}')"
  [ "$actual" = "$digest" ] || { log "latest backend checksum mismatch for $id"; rm -f "$new_zip"; return 1; }
  staged="$ROOT/.backend-update-$id-$$"; unpack "$id" "$new_zip" "$staged" || { rm -rf "$staged"; rm -f "$new_zip"; return 1; }
  [ -f "$staged/metamount.sh" ] || { rm -rf "$staged"; rm -f "$new_zip"; return 1; }
  old="$ROOT/.backend-old-$id-$$"; rm -rf "$old"; mv "$BACKENDS/$id" "$old" || return 1
  if mv "$staged" "$BACKENDS/$id" && activate_runtime "$id"; then
    mv "$new_zip" "$CACHE/$id.zip"; rm -rf "$old"; return 0
  fi
  rm -rf "$BACKENDS/$id"; mv "$old" "$BACKENDS/$id"; rm -rf "$staged"; rm -f "$new_zip"
  log "update failed; retained previous backend/runtime for $id"
  return 1
}
backup() {
  out="${1:-$ROOT/backups/AnyMeta-$(date +%Y%m%d-%H%M%S).tar.gz}"; mkdir -p "$(dirname "$out")"
  tar -czf "$out" -C "$ROOT" state backends 2>/dev/null || return 1; printf '%s\n' "$out"
}
restore() { archive="$1"; [ -f "$archive" ] || return 1; tar -xzf "$archive" -C "$ROOT"; }
doctor() {
  printf 'controller=%s\n' "$([ -x "$MODDIR/anymeta.sh" ] && echo ok || echo broken)"
  printf 'manifest=%s\n' "$([ -s "$MANIFEST" ] && echo ok || echo missing)"
  printf 'curl=%s unzip=%s\n' "$(command -v curl >/dev/null && echo ok || echo missing)" "$(command -v unzip >/dev/null && echo ok || echo missing)"
  status
}
case "${1:-status}" in
  status) status ;;
  list) list ;;
  use) [ -n "${2:-}" ] && use_backend "$2" ;;
  check-update) check_update "${2:-}" ;;
  update) update_backend "${2:-}" ;;
  fetch) [ -n "${2:-}" ] && ensure_backend "$2" ;;
  install) [ -n "${2:-}" ] && install_package "$2" ;;
  repo-install) [ -n "${2:-}" ] && install_registry "$2" ;;
  git-build) [ -n "${2:-}" ] && git_build "$2" "${3:-}" ;;
  backup) backup "${2:-}" ;;
  restore) restore "${2:-}" ;;
  doctor) doctor ;;
  log) tail -n "${2:-80}" "$LOG" 2>/dev/null ;;
  *) printf 'usage: anymeta.sh {status|list|use ID|fetch ID|install ZIP|repo-install ID|git-build REPO [REF]|backup [FILE]|restore FILE|doctor|log [N]}\n' >&2; exit 2 ;;
esac
