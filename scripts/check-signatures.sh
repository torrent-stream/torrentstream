#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Checks the code signatures of a build: the app, every executable in it (the FFmpeg sidecar
# included), and the installers. Writes a table to the workflow's step summary.
#
# Usage: scripts/check-signatures.sh <rust-target-triple> <signed|unsigned>
#
# signed:   every file must carry a valid, timestamped signature from a trusted certificate:
#           Developer ID with the hardened runtime, notarized and stapled (macOS), or Authenticode
#           (Windows).
# unsigned: macOS apps must still be signed ad hoc, which Apple silicon requires; Windows files
#           are only reported.
#
# Linux packages are not code signed; they are verified with SHA256SUMS.txt and the build
# provenance attestation (see docs/release.md).
set -euo pipefail

target=${1:?usage: check-signatures.sh <rust-target-triple> <signed|unsigned>}
expected=${2:?usage: check-signatures.sh <rust-target-triple> <signed|unsigned>}
release="target/$target/release"
failed=0
rows=()

report() { # file, signature, ok
  rows+=("| \`$1\` | $2 | $3 |")
  if [ "$3" != ✅ ]; then failed=1; fi
}

case "$target" in
  *-apple-darwin)
    app=$(find "$release/bundle/macos" -maxdepth 1 -name '*.app' | head -n 1)
    [ -n "$app" ] || { echo "no .app bundle in $release/bundle/macos" >&2; exit 1; }
    for bin in "$app"/Contents/MacOS/*; do
      details=$(codesign -dvv "$bin" 2>&1 || true)
      name="Contents/MacOS/$(basename "$bin")"
      if grep -q '^Signature=adhoc' <<<"$details"; then
        signature="ad hoc"
      else
        signature=$(sed -n 's/^Authority=//p' <<<"$details" | head -n 1)
        signature=${signature:-none}
      fi
      if [ "$expected" = signed ]; then
        ok=❌
        if [[ $signature == "Developer ID Application:"* ]] &&
          grep -q '^Timestamp=' <<<"$details" &&
          grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"$details"; then
          ok=✅
        fi
      else
        ok=❌
        if [ "$signature" = "ad hoc" ] || [[ $signature == "Developer ID Application:"* ]]; then
          ok=✅
        fi
      fi
      report "$name" "$signature" "$ok"
    done
    if codesign --verify --deep --strict "$app" 2>/dev/null; then
      report "$(basename "$app")" "seal intact" ✅
    else
      report "$(basename "$app")" "seal broken or missing" ❌
    fi
    if [ "$expected" = signed ]; then
      if spctl --assess --type execute "$app" 2>/dev/null; then
        report "$(basename "$app")" "accepted by Gatekeeper" ✅
      else
        report "$(basename "$app")" "rejected by Gatekeeper" ❌
      fi
      if xcrun stapler validate "$app" >/dev/null 2>&1; then
        report "$(basename "$app")" "notarization ticket stapled" ✅
      else
        report "$(basename "$app")" "no notarization ticket" ❌
      fi
    fi
    ;;
  *-windows-*)
    files=("$release"/*.exe)
    while IFS= read -r installer; do files+=("$installer"); done < <(
      find "$release/bundle/nsis" "$release/bundle/msi" -maxdepth 1 \( -name '*.exe' -o -name '*.msi' \) 2>/dev/null
    )
    for file in "${files[@]}"; do
      [ -f "$file" ] || continue
      # Status, signer, and whether it is timestamped, separated by "|" (a whitespace separator
      # would merge with an empty signer).
      line=$(pwsh -NoProfile -NonInteractive -Command "\$s = Get-AuthenticodeSignature -LiteralPath '$(cygpath -w "$file")'; \"\$(\$s.Status)|\$(\$s.SignerCertificate.Subject)|\$([bool]\$s.TimeStamperCertificate)\"" | tr -d '\r')
      IFS='|' read -r status subject timestamped <<<"$line"
      if [ -z "$status" ]; then
        echo "could not read the signature of $file" >&2
        exit 1
      fi
      signature=${subject:-none}
      [ "$status" = Valid ] || signature="$status${subject:+ ($subject)}"
      if [ "$expected" = signed ]; then
        ok=❌
        if [ "$status" = Valid ] && [ "$timestamped" = True ]; then ok=✅; fi
      else
        ok=➖
        [ "$status" = Valid ] && ok=✅
      fi
      report "$(basename "$file")" "$signature" "$ok"
    done
    # Unsigned Windows builds are reported, not failed.
    [ "$expected" = signed ] || failed=0
    ;;
  *)
    echo "Linux packages are not code signed; see docs/release.md."
    exit 0
    ;;
esac

{
  echo "### Signatures ($target, expected: $expected)"
  echo
  echo "| File | Signature | OK |"
  echo "| --- | --- | --- |"
  printf '%s\n' "${rows[@]}"
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ "$failed" -ne 0 ]; then
  echo "::error::The $target build is not signed as expected ($expected)."
  exit 1
fi
