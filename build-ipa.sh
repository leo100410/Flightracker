#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if ! mkdir .skynear-build-lock 2>/dev/null; then
    echo 'Es läuft bereits ein Build oder die Build-Sperre eines abgebrochenen Builds existiert.' >&2
    echo 'Keinen zweiten Build starten. Erst prüfen, ob der vorherige Prozess beendet ist.' >&2
    exit 1
fi
marker="$(mktemp)"
trap 'rm -f -- "$marker"; rmdir .skynear-build-lock 2>/dev/null || true' EXIT
printf 'Projekt: %s\n' "$PWD"
xtool dev build --ipa 2>&1 | tee build.log
python3 - "$marker" <<'PY'
import pathlib, subprocess, sys
stamp = pathlib.Path(sys.argv[1]).stat().st_mtime
candidates = [p for p in pathlib.Path('.').rglob('*.ipa') if p.stat().st_mtime >= stamp]
if not candidates:
    raise SystemExit('Kein frisch erzeugtes IPA gefunden. build.log prüfen. Eine ältere IPA wird nicht als erfolgreich ausgegeben.')
ipa = max(candidates, key=lambda p: p.stat().st_mtime)
for verifier in ('verify-ipa.py', 'verify-widget-ipa.py', 'verify-signing-space.py'):
    subprocess.run([sys.executable, verifier, str(ipa)], check=True)
subprocess.run([sys.executable, 'verify-update.py', '--ipa', str(ipa)], check=True)
print('\nNeue, strukturell geprüfte IPA:', ipa.resolve())
PY
