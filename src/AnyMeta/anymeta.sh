#!/system/bin/sh
# AnyMeta controller. Persistent state lives outside /data/adb/modules so a
# backend can be replaced without touching installed modules or their data.
set -u

MODDIR="${0%/*}"
ROOT="${ANYMETA_ROOT:-/data/adb/AnyMeta}"
CACHE="$ROOT/cache"
BACKENDS="$ROOT/backends"
STATE="$ROOT/state"
ACTIVE="$STATE/active"
LOG="$STATE/anymeta.log"
MANIFEST="$MODDIR/backends.json"
PROXY_BASE="${ANYMETA_PROXY_BASE:-https://ghproxy.net/}"

mkdir -p "$CACHE" "$BACKENDS" "$STATE"
log() { mkdir -p "$STATE"; printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG"; }
json_field() { awk -v id="$2" -v key="$3" 'index($0,"\"id\": \"" id "\"") { found=1 } found && index($0,"\"" key "\"") { gsub(/.*"[^"]+"[[:space:]]*:[[:space:]]*"/,""); gsub(/".*/,""); print; exit }' "$1"; }
manifest_ids() { sed -n 's/.*"id": "\([^"]*\)".*/\1/p' "$MANIFEST"; }
known_id() { manifest_ids | grep -Fxq "$1"; }
backend_url() {
  id="$1"; repo="$(json_field "$MANIFEST" "$id" repo)"; release="$(json_field "$MANIFEST" "$id" release)"; asset="$(json_field "$MANIFEST" "$id" asset)"
  printf '%s/releases/download/%s/%s' "$repo" "$release" "$asset"
}
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
  id="$1"; zip="$2"; dest="$BACKENDS/$id"; tmp="$ROOT/.extract-$id-$$"
  rm -rf "$tmp" "$dest"; mkdir -p "$tmp" "$dest"
  unzip -q "$zip" -d "$tmp" || { rm -rf "$tmp" "$dest"; return 1; }
  root="$(find "$tmp" -type f -name module.prop -print -quit)"
  [ -n "$root" ] || { log "backend $id has no module.prop"; rm -rf "$tmp" "$dest"; return 1; }
  root="$(dirname "$root")"
  cp -a "$root/." "$dest/"
  printf '%s\n' "$(date +%s)" > "$dest/.installed"
  rm -rf "$tmp"
}
module_prop() { sed -n "s/^$2=//p" "$1/module.prop" 2>/dev/null | head -n1; }
install_zip() {
  file="$1"; [ -f "$file" ] || return 1
  command -v ksud >/dev/null 2>&1 || { log "ksud unavailable; downloaded package kept at $file"; return 2; }
  # KernelSU versions expose the same module install operation with either
  # positional or --zip syntax; try the positional form first.
  ksud module install "$file" 2>/dev/null || ksud module install --zip "$file"
}
resolve_dependencies() {
  root="$1"; visiting="$2"; done_file="$3"; prop="$root/module.prop"
  [ -f "$prop" ] || return 0
  id="$(module_prop "$root" id)"; case " $(cat "$done_file" 2>/dev/null) " in *" $id "*) return 0 ;; esac
  case " $visiting " in *" $id "*) log "dependency cycle detected at $id"; return 3 ;; esac
  deps="$(module_prop "$root" depends | tr ',;' '  ')"
  for dep in $deps; do
    dep_root="$ROOT/dependency-staging/$dep"
    [ -d "$dep_root" ] || { log "missing dependency $dep for $id"; return 4; }
    resolve_dependencies "$dep_root" "$visiting $id" "$done_file" || return
  done
  printf '%s\n' "$id" >> "$done_file"
}
install_package() {
  file="$1"; stage="$ROOT/dependency-staging"
  rm -rf "$stage"; mkdir -p "$stage/main"
  unzip -q "$file" -d "$stage/main" || return 1
  prop="$(find "$stage/main" -name module.prop -print -quit)"; [ -n "$prop" ] || return 1
  root="$(dirname "$prop")"; order="$ROOT/state/install-order.$$"; : > "$order"
  resolve_dependencies "$root" "" "$order" || { rm -f "$order"; return 1; }
  while IFS= read -r dep; do
    [ "$dep" = "$(module_prop "$root" id)" ] && install_zip "$file" || log "dependency $dep resolved; install it from registry before $file"
  done < "$order"
  rm -f "$order"; rm -rf "$stage"
}
git_build() {
  repo="$1"; ref="${2:-}"; work="$ROOT/state/git-build-$$"; mkdir -p "$work"
  command -v git >/dev/null 2>&1 || return 2
  git clone --depth 1 ${ref:+--branch "$ref"} "$repo" "$work/src" || { rm -rf "$work"; return 1; }
  command -v kam >/dev/null 2>&1 || { log "kam unavailable on device; clone retained at $work/src"; return 2; }
  (cd "$work/src" && kam build) || { rm -rf "$work"; return 1; }
  artifact="$(find "$work/src/dist" -type f -name '*.zip' -print -quit)"; [ -n "$artifact" ] || return 1
  install_package "$artifact"; rm -rf "$work"
}
ensure_backend() {
  id="$1"; known_id "$id" || { log "unknown backend $id"; return 2; }
  [ -f "$BACKENDS/$id/metamount.sh" ] && return 0
  zip="$(download "$id")" || return 1
  unpack "$id" "$zip"
}
status() {
  active="$(cat "$ACTIVE" 2>/dev/null || printf '%s' meta-overlayfs)"
  printf 'active=%s\nroot=%s\ncache=%s\n' "$active" "$ROOT" "$(du -sh "$CACHE" 2>/dev/null | awk '{print $1}')"
}
list() {
  active="$(cat "$ACTIVE" 2>/dev/null || true)"
  while IFS= read -r id; do
    name="$(json_field "$MANIFEST" "$id" name)"; desc="$(json_field "$MANIFEST" "$id" description)"
    installed=0; [ -f "$BACKENDS/$id/metamount.sh" ] && installed=1
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "$installed" "$([ "$active" = "$id" ] && echo 1 || echo 0)" "$desc"
  done < <(manifest_ids)
}
use_backend() {
  id="$1"; ensure_backend "$id" || return 1
  printf '%s\n' "$id" > "$ACTIVE"; log "active backend changed to $id"; printf 'active=%s\n' "$id"
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
  fetch) [ -n "${2:-}" ] && ensure_backend "$2" ;;
  install) [ -n "${2:-}" ] && install_package "$2" ;;
  git-build) [ -n "${2:-}" ] && git_build "$2" "${3:-}" ;;
  backup) backup "${2:-}" ;;
  restore) restore "${2:-}" ;;
  doctor) doctor ;;
  log) tail -n "${2:-80}" "$LOG" 2>/dev/null ;;
  *) printf 'usage: anymeta.sh {status|list|use ID|fetch ID|install ZIP|git-build REPO [REF]|backup [FILE]|restore FILE|doctor|log [N]}\n' >&2; exit 2 ;;
esac
