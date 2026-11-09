"""Verify pinned references and REA PNG manifests without executing upstream code."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'research/reusable/sources.lock.json').read_text())
assert len(manifest['files']) == 6
for entry in manifest['files']:
    path = (ROOT / entry['local_path']).resolve()
    assert path.is_relative_to(ROOT / 'research/reusable')
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == entry['sha256'], path
    assert len(data) == entry['bytes'], path
    assert entry['commit'] in entry['source_url']
    assert entry['license'] == 'MIT'

evidence = ROOT / 'docs/design-adoption/evidence'
for site in ['crouton', 'umami', 'paprika']:
    shot = json.loads((evidence / f'{site}-screenshot.json').read_text())
    result = shot['normalized_result']
    data = (evidence / result['artifact']['local_file']).read_bytes()
    assert data.startswith(b'\x89PNG\r\n\x1a\n')
    assert hashlib.sha256(data).hexdigest() == result['artifact']['sha256']
    assert len(data) == result['artifact']['bytes']
    assert result['viewport'] == {'width': 1440, 'height': 1000}
    assert shot['evidence_id']
    inspection = json.loads((evidence / f'{site}-inspection.json').read_text())
    assert inspection['operation'] == 'inspect_web_page'
    assert inspection['parameters']['include_script_sources'] is False

print('OK: 3 pinned source files + 3 MIT licenses; 3 verified REA screenshots')
