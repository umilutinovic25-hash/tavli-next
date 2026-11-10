#!/usr/bin/env python3
"""Validate feature coverage and provenance without executing upstream code."""

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate(partial=False):
    errors = []
    summary = {"features": 0, "streams": 0, "sources": 0, "reference_files": 0}

    def check(condition, message):
        if not condition:
            errors.append(message)

    def read_json(path):
        try:
            return json.loads(path.read_text())
        except (OSError, ValueError) as exc:
            errors.append(f"{path.relative_to(ROOT)}: {exc}")
            return None

    register = read_json(ROOT / "research/feature-register.json")
    streams = read_json(ROOT / "research/streams.json")
    if register is None or streams is None:
        return summary, errors
    features = register.get("features", [])
    ids = [f.get("id") for f in features]
    expected = {f"F{n:03d}" for n in range(1, 91)}
    check(len(ids) == 90 and set(ids) == expected, "Register must contain exactly F001–F090 once")
    check(set(streams) == set("ABCDEF"), "Exactly six streams A–F are required")
    assigned = [fid for stream in streams.values() for fid in stream.get("feature_ids", [])]
    check(len(assigned) == 90 and set(assigned) == expected, "Stream ownership must cover all 90 IDs exactly once")
    for feature in features:
        check(feature.get("status") == "planned", f"{feature.get('id')}: blueprint cannot claim implemented status")
        check(feature.get("implementation_verified") is False, f"{feature.get('id')}: no implementation verified in this delivery")
        owner = feature.get("owner_stream")
        check(owner in streams and feature.get("id") in streams.get(owner, {}).get("feature_ids", []), f"{feature.get('id')}: owner mismatch")
    summary["features"] = len(features)

    for letter, ownership in streams.items():
        path = ROOT / ownership["manifest"]
        report = ROOT / ownership["report"]
        check(len(ownership["feature_ids"]) == 15, f"{letter}: expected 15 assigned features")
        if partial and not path.exists():
            continue
        manifest = read_json(path)
        if manifest is None:
            continue
        summary["streams"] += 1
        check(report.is_file() and report.stat().st_size > 500, f"{letter}: substantive report is missing")
        check(manifest.get("stream") == letter, f"{letter}: manifest stream mismatch")
        entries = manifest.get("features", [])
        actual = [f.get("id") for f in entries if isinstance(f, dict)]
        check(len(actual) == 15 and set(actual) == set(ownership["feature_ids"]), f"{letter}: expected exactly its 15 owned features")
        for feature in entries:
            if not isinstance(feature, dict):
                errors.append(f"{letter}: feature must be an object")
                continue
            for key in ("current_state", "proposed_changes", "acceptance_criteria", "verification", "phase", "scope_slices"):
                check(bool(feature.get(key)), f"{letter}/{feature.get('id')}: missing {key}")
            check("dependencies" in feature, f"{letter}/{feature.get('id')}: missing dependencies")
            for dependency in re.findall(r"\bF\d{3}\b", json.dumps(feature.get("dependencies", []))):
                check(dependency in expected, f"{feature.get('id')}: unknown dependency {dependency}")
        sources = manifest.get("sources", [])
        check(bool(sources), f"{letter}: no upstream source evidence")
        summary["sources"] += len(sources)
        for source in sources:
            check(bool(source.get("repo_url")), f"{letter}: source URL missing")
            check(bool(re.fullmatch(r"[a-fA-F0-9]{40}", source.get("commit", ""))), f"{letter}: source commit must be a full SHA")
            check(bool(source.get("license_spdx_or_unknown")), f"{letter}: license observation missing")
            check(bool(source.get("inspected_files")), f"{letter}: inspected source paths missing")
            check(bool(source.get("reuse_decision")), f"{letter}: reuse decision missing")
        for item in manifest.get("copied_files", []):
            candidate = Path(item.get("local_path", ""))
            candidate = (ROOT / candidate).resolve() if not candidate.is_absolute() else candidate.resolve()
            allowed = (ROOT / "research/reference-code" / letter).resolve()
            check(candidate.is_relative_to(allowed), f"{letter}: reference file escaped its owned directory")
            check(candidate.is_file(), f"{letter}: reference file is missing: {candidate.name}")
            if candidate.is_file() and candidate.is_relative_to(allowed):
                observed = hashlib.sha256(candidate.read_bytes()).hexdigest()
                check(observed == item.get("sha256"), f"{letter}: SHA-256 mismatch: {candidate.name}")
                summary["reference_files"] += 1
            license_path = Path(item.get("license_path", ""))
            license_path = (ROOT / license_path).resolve() if not license_path.is_absolute() else license_path.resolve()
            check(license_path.is_relative_to(allowed) and license_path.is_file(), f"{letter}: license file missing or outside owned directory")
            check(bool(item.get("source_url")) and bool(item.get("upstream_path")), f"{letter}: copied file provenance missing")

    for required in ("ARCHITECTURE.md", "tasks/plan.md", "tasks/todo.md", "tasks/FEATURE-PLAN.md", "research/YOUTUBE.md", "research/youtube-search.json", "docs/expansion/UPSTREAM.md", "docs/expansion/CONTRACTS.md"):
        check((ROOT / required).is_file(), f"Required document missing: {required}")
    todo = ROOT / "tasks/todo.md"
    if todo.exists():
        todo_ids = re.findall(r"^- \[ \] (F\d{3})\b", todo.read_text(), re.MULTILINE)
        check(len(todo_ids) == 90 and set(todo_ids) == expected, "Task index must contain all 90 planned IDs once")
    detail = ROOT / "tasks/FEATURE-PLAN.md"
    if detail.exists():
        detail_ids = re.findall(r"^## (F\d{3})\b", detail.read_text(), re.MULTILINE)
        check(len(detail_ids) == 90 and set(detail_ids) == expected, "Detailed feature plan must cover all 90 IDs once")
    dependency_path = ROOT / "research/dependency-order.json"
    if dependency_path.exists():
        dependencies = read_json(dependency_path)
        if dependencies:
            check(not dependencies.get("cycles"), "Feature dependencies contain cycles")
            order = dependencies.get("feature_order", [])
            check(len(order) == 90 and set(order) == expected, "Dependency order must contain all 90 IDs")
    youtube = read_json(ROOT / "research/youtube-search.json")
    if youtube:
        check(bool(youtube.get("results")) and bool(youtube.get("limitations")), "YouTube observations need results and evidence limitations")
    return summary, errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--partial", action="store_true", help="Allow stream manifests that have not arrived yet")
    args = parser.parse_args()
    counts, problems = validate(partial=args.partial)
    print(json.dumps({"ok": not problems, **counts, "errors": problems}, ensure_ascii=False, indent=2))
    raise SystemExit(1 if problems else 0)
