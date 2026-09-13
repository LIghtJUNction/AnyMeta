#!/system/bin/sh
MODDIR="${0%/*}"
case "${1:-status}" in
  status|list|doctor|log|check-update|update) exec "$MODDIR/anymeta.sh" "$@" ;;
  backup) exec "$MODDIR/anymeta.sh" backup "${2:-}" ;;
  use|fetch|install|repo-install|git-build) [ -n "${2:-}" ] && exec "$MODDIR/anymeta.sh" "$@" ;;
  *) echo "AnyMeta: status | list | use ID | fetch ID | backup | doctor" ;;
esac
