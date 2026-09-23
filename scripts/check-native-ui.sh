#!/usr/bin/env bash
# Enforce the product-facing parts of docs/UI_GUIDELINES.md.
# This intentionally checks only for high-signal regressions; SwiftLint and
# human review remain responsible for nuanced native-UI decisions.
set -euo pipefail
cd "$(dirname "$0")/.."

violations=0

scan() {
  local label="$1"
  local pattern="$2"
  shift 2
  local matches
  matches="$(grep -RInE --include='*.swift' "$pattern" "$@" || true)"
  if [[ -n "$matches" ]]; then
    printf 'Native UI violation: %s\n%s\n' "$label" "$matches" >&2
    violations=1
  fi
}

scan "forced app appearance" 'preferredColorScheme[[:space:]]*\(' App/iOS App/macOS
scan "fixed app color" 'Color\(0x|Color\.init\([^)]*red:' App/iOS App/macOS
scan "fixed ordinary text scale" '\.font\(\.system\(size:' App/iOS App/macOS
scan "custom app typography helper" '(Theme|MacTheme)\.mono|struct SectionLabel' App/iOS App/macOS
scan "custom navigation replacement" 'navigationBarBackButtonHidden|toolbar\(\.hidden,[[:space:]]*for:[[:space:]]*\.navigationBar' App/iOS
scan "custom corner treatment" '\.cornerRadius\(' App/iOS App/macOS

if [[ "$violations" -ne 0 ]]; then
  printf '\nSee docs/UI_GUIDELINES.md before changing product UI.\n' >&2
  exit 1
fi

printf 'Native UI contract: OK\n'
