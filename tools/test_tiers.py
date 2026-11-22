#!/usr/bin/env python3
"""Deterministic tier classifier, batch chunker, and XML/log summarizer for gdUnit4."""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

TIERS = ("fast", "medium", "slow")
DEFAULT_MAX_BATCH_CHARS = 20_000
DEFAULT_MAX_BATCH_SUITES = 150
# Conservative Windows CreateProcessW budget for Godot executable + fixed gdUnit4 flags + -rd path.
DEFAULT_BASE_CMD_OVERHEAD = 512
# Space separator + '-a ' + optional quotes around both tokens.
PER_SUITE_ARG_OVERHEAD = 8

SLOW_FILENAME_RE = re.compile(
    r"(_tuning|_balance|_deadline|_snapshot|_saves?|_load)\.gd$"
)
SLOW_CONTENT_RES = (
    re.compile(r"main\.tscn"),
    re.compile(r"\bGroundPlannerKit\b"),
    re.compile(r"PassengerViews"),
    re.compile(r"SaveGame|SaveTestKit|save_game|load_game|user://"),
)
MEDIUM_CONTENT_RES = (
    re.compile(r"SubViewport"),
    re.compile(r"\bawait\b"),
    re.compile(r"\badd_child\b"),
    re.compile(r"\w*TestWorld\b|GateWalkWorld|MajorTestBase|SettlementWagesKit"),
    re.compile(r"\.(tscn|glb|gltf)\b"),
    re.compile(
        r"PassengerRig|CharacterRig|CarryRig|Skeleton3D|"
        r"AnimationPlayer|MeshInstance3D|CarryWorn|CarryPose"
    ),
    re.compile(
        r"\b(BuildGrid|SiteGrid|SiteDefinition|ReferenceTerminal|"
        r"StarterShell|GroundPlanner|RepairPlan|FlightSim)\b|terminal_site\.tres"
    ),
)

ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
OVERALL_SUMMARY_RE = re.compile(
    r"Overall Summary:\s*(\d+)\s+test cases\s*\|\s*(\d+)\s+errors\s*\|\s*"
    r"(\d+)\s+failures\s*\|\s*(\d+)\s+flaky\s*\|\s*(\d+)\s+skipped\s*\|\s*"
    r"(\d+)\s+orphans\s*\|"
)
SUITE_STATS_RE = re.compile(
    r"Statistics:\s*(\d+)\s+test cases\s*\|\s*(\d+)\s+errors\s*\|\s*"
    r"(\d+)\s+failures\s*\|\s*(\d+)\s+flaky\s*\|\s*(\d+)\s+skipped\s*\|\s*"
    r"(\d+)\s+orphans\s*\|"
)

EXIT_CODE_NOTES = {
    100: "failures/errors",
    101: "orphans/warnings",
    103: "headless flag missing or misplaced (--ignoreHeadlessMode)",
    104: "Godot version not supported",
    105: "script parse error",
    124: "timeout (GODOT_TIMEOUT)",
}


def discover_test_suites(tests_dir: Path) -> list[str]:
    """Return sorted POSIX paths relative to tests_dir, skipping .gdignore dirs."""
    if not tests_dir.is_dir():
        raise FileNotFoundError(f"tests directory not found: {tests_dir}")

    suites: list[str] = []
    for dirpath, dirnames, filenames in os.walk(tests_dir):
        if ".gdignore" in filenames:
            dirnames[:] = []
            continue
        dirnames.sort()
        for fn in sorted(filenames):
            if fn.startswith("test_") and fn.endswith(".gd"):
                rel = (Path(dirpath) / fn).relative_to(tests_dir).as_posix()
                suites.append(rel)
    suites.sort()
    return suites


def classify_suite(rel_path: str, content: str) -> str:
    """Classify a single test suite into slow, medium, or fast (Slow -> Medium -> Fast)."""
    filename = Path(rel_path).name
    if SLOW_FILENAME_RE.search(filename) or any(r.search(content) for r in SLOW_CONTENT_RES):
        return "slow"
    if any(r.search(content) for r in MEDIUM_CONTENT_RES):
        return "medium"
    return "fast"


def classify_all(tests_dir: Path) -> dict[str, list[str]]:
    """Discover and partition all test_*.gd files under tests_dir into fast/medium/slow."""
    buckets: dict[str, list[str]] = {"fast": [], "medium": [], "slow": []}
    for rel_path in discover_test_suites(tests_dir):
        content = (tests_dir / rel_path).read_text(encoding="utf-8", errors="replace")
        tier = classify_suite(rel_path, content)
        buckets[tier].append(rel_path)
    return buckets


def to_res_path(rel_or_res_path: str) -> str:
    if rel_or_res_path.startswith("res://"):
        return rel_or_res_path
    return f"res://tests/{rel_or_res_path.lstrip('/')}"


def to_rel_path(rel_or_res_path: str) -> str:
    cleaned = rel_or_res_path.strip()
    if cleaned.startswith("res://tests/"):
        return cleaned[len("res://tests/"):]
    if cleaned.startswith("tests/"):
        return cleaned[len("tests/"):]
    return cleaned.lstrip("/")


def suite_rel_from_xml(ts: ET.Element) -> str:
    """Normalize a JUnit <testsuite> element to a tests/-relative POSIX .gd path."""
    pkg = ts.attrib.get("package", "").strip()
    name = ts.attrib.get("name", "").strip()
    clean_pkg = pkg.removeprefix("res://").strip("/")
    if clean_pkg == "tests":
        rel_dir = ""
    elif clean_pkg.startswith("tests/"):
        rel_dir = clean_pkg[len("tests/"):]
    else:
        rel_dir = clean_pkg
    stem = name[:-3] if name.endswith(".gd") else name
    if not stem:
        return "<unknown>"
    return f"{rel_dir}/{stem}.gd" if rel_dir else f"{stem}.gd"


def chunk_suites(
    rel_paths: list[str],
    max_chars: int = DEFAULT_MAX_BATCH_CHARS,
    max_suites: int | None = DEFAULT_MAX_BATCH_SUITES,
    base_overhead: int = DEFAULT_BASE_CMD_OVERHEAD,
) -> list[list[str]]:
    """Group suite paths so complete command lines fit <= max_chars and <= max_suites."""
    if not rel_paths:
        return []
    if max_chars <= 0:
        raise ValueError(f"max_chars must be positive, got {max_chars}")
    if base_overhead < 0 or base_overhead >= max_chars:
        raise ValueError(
            f"base_overhead must be in [0, max_chars), got {base_overhead} vs {max_chars}"
        )
    if max_suites is not None and max_suites <= 0:
        raise ValueError(f"max_suites must be positive, got {max_suites}")

    batches: list[list[str]] = []
    current_batch: list[str] = []
    current_len = base_overhead

    for path in rel_paths:
        res_path = to_res_path(path)
        token_len = len(res_path) + PER_SUITE_ARG_OVERHEAD
        exceeds_chars = (current_len + token_len) > max_chars
        exceeds_suites = max_suites is not None and len(current_batch) >= max_suites
        if current_batch and (exceeds_chars or exceeds_suites):
            batches.append(current_batch)
            current_batch = [res_path]
            current_len = base_overhead + token_len
        else:
            current_batch.append(res_path)
            current_len += token_len

    if current_batch:
        batches.append(current_batch)
    return batches


@dataclass
class RunSummary:
    tier: str
    run_id: str
    batches_expected: int
    batch_codes: list[int]
    suites_expected: int = 0
    suites_executed: int = 0
    total_tests: int = 0
    passed: int = 0
    failures: int = 0
    errors: int = 0
    skipped: int = 0
    orphans: int = 0
    wall_seconds: float | None = None
    slowest_suites: list[tuple[float, str]] = field(default_factory=list)
    missing_xml_batches: list[int] = field(default_factory=list)
    multiple_xml_batches: dict[int, int] = field(default_factory=dict)
    missing_suites: list[str] = field(default_factory=list)
    duplicate_suites: list[str] = field(default_factory=list)
    unexpected_suites: list[str] = field(default_factory=list)
    xml_parse_errors: list[str] = field(default_factory=list)
    log_path: str = ""
    reports_dir: str = ""
    failure_reasons: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return len(self.failure_reasons) == 0


def parse_orphans_from_log(log_text: str) -> int:
    clean = ANSI_ESCAPE_RE.sub("", log_text)
    overall_matches = OVERALL_SUMMARY_RE.findall(clean)
    if overall_matches:
        return sum(int(m[5]) for m in overall_matches)
    suite_matches = SUITE_STATS_RE.findall(clean)
    if suite_matches:
        return sum(int(m[5]) for m in suite_matches)
    return 0


def _collect_batch_xmls(reports_dir: Path, batch_idx: int) -> list[Path]:
    batch_dir = reports_dir / f"b{batch_idx}"
    if not batch_dir.is_dir():
        return []
    return sorted(batch_dir.glob("report_*/results.xml"))


def _format_suite_sample(items: list[str], limit: int = 5) -> str:
    shown = ", ".join(items[:limit])
    if len(items) > limit:
        return f"{shown} (+{len(items) - limit} more)"
    return shown


def _is_allowed_zero_test_helper(tier: str, suite_rel: str, tests_count: int) -> bool:
    return (
        tier == "all"
        and tests_count == 0
        and not Path(suite_rel).name.startswith("test_")
    )


def summarize_run(
    tier: str,
    run_id: str,
    reports_dir: Path,
    log_file: Path,
    batch_codes: list[int],
    wall_seconds: float | None = None,
    expected_batches: list[list[str]] | None = None,
) -> RunSummary:
    summary = RunSummary(
        tier=tier,
        run_id=run_id,
        batches_expected=len(batch_codes),
        batch_codes=list(batch_codes),
        wall_seconds=wall_seconds,
        log_path=str(log_file),
        reports_dir=str(reports_dir),
    )

    normalized_expected: list[list[str]] | None = None
    if expected_batches is not None:
        normalized_expected = [[to_rel_path(s) for s in batch] for batch in expected_batches]
        summary.suites_expected = sum(len(b) for b in normalized_expected)

    seen_globally: set[str] = set()
    suite_timings: list[tuple[float, str]] = []

    for batch_idx in range(len(batch_codes)):
        xml_files = _collect_batch_xmls(reports_dir, batch_idx)
        if not xml_files:
            summary.missing_xml_batches.append(batch_idx)
            continue
        if len(xml_files) > 1:
            summary.multiple_xml_batches[batch_idx] = len(xml_files)
            continue

        xml_path = xml_files[0]
        try:
            tree = ET.parse(xml_path)
        except ET.ParseError as exc:
            summary.xml_parse_errors.append(f"{xml_path}: {exc}")
            continue

        root = tree.getroot()
        suite_nodes = root.findall("testsuite")
        batch_executed: list[tuple[str, int]] = []

        if suite_nodes:
            for ts in suite_nodes:
                suite_rel = suite_rel_from_xml(ts)
                tests_count = int(ts.attrib.get("tests", 0))
                if _is_allowed_zero_test_helper(tier, suite_rel, tests_count):
                    continue
                summary.suites_executed += 1
                summary.total_tests += tests_count
                summary.failures += int(ts.attrib.get("failures", 0))
                summary.errors += int(ts.attrib.get("errors", 0))
                summary.skipped += int(ts.attrib.get("skipped", 0))
                duration = float(ts.attrib.get("time", 0.0))
                label = suite_rel[:-3] if suite_rel.endswith(".gd") else suite_rel
                suite_timings.append((duration, f"tests/{label}"))
                batch_executed.append((suite_rel, tests_count))
                if suite_rel in seen_globally:
                    summary.duplicate_suites.append(suite_rel)
                else:
                    seen_globally.add(suite_rel)
        else:
            summary.total_tests += int(root.attrib.get("tests", 0))
            summary.failures += int(root.attrib.get("failures", 0))
            summary.errors += int(root.attrib.get("errors", 0))
            summary.skipped += int(root.attrib.get("skipped", 0))

        if normalized_expected is not None and batch_idx < len(normalized_expected):
            expected_set = set(normalized_expected[batch_idx])
            executed_set = {s for s, _ in batch_executed}
            for missing in sorted(expected_set - executed_set):
                summary.missing_suites.append(missing)
            for extra in sorted(executed_set - expected_set):
                summary.unexpected_suites.append(extra)

    summary.passed = max(
        0,
        summary.total_tests - summary.failures - summary.errors - summary.skipped,
    )
    suite_timings.sort(key=lambda item: (-item[0], item[1]))
    summary.slowest_suites = suite_timings[:5]

    if log_file.is_file():
        log_text = log_file.read_text(encoding="utf-8", errors="replace")
        summary.orphans = parse_orphans_from_log(log_text)

    reasons: list[str] = []
    if normalized_expected is not None and len(normalized_expected) != len(batch_codes):
        reasons.append(
            f"batch count mismatch: expected {len(normalized_expected)}, got {len(batch_codes)}"
        )
    for batch_idx, code in enumerate(batch_codes):
        if code != 0:
            note = EXIT_CODE_NOTES.get(code, "non-zero exit")
            reasons.append(f"batch {batch_idx} exited with {code} ({note})")
    if summary.missing_xml_batches:
        missing_str = ", ".join(f"b{i}" for i in summary.missing_xml_batches)
        reasons.append(f"missing results.xml for batch(es): {missing_str}")
    if summary.multiple_xml_batches:
        multi_str = ", ".join(
            f"b{i} ({count})" for i, count in sorted(summary.multiple_xml_batches.items())
        )
        reasons.append(f"multiple results.xml files in batch(es): {multi_str}")
    if summary.xml_parse_errors:
        reasons.append(f"XML parse error(s): {'; '.join(summary.xml_parse_errors)}")
    if summary.missing_suites:
        reasons.append(
            f"missing expected suite(s) ({len(summary.missing_suites)}): "
            f"{_format_suite_sample(summary.missing_suites)}"
        )
    if summary.duplicate_suites:
        unique_dups = sorted(set(summary.duplicate_suites))
        reasons.append(
            f"duplicate executed suite(s) ({len(summary.duplicate_suites)}): "
            f"{_format_suite_sample(unique_dups)}"
        )
    if summary.unexpected_suites:
        reasons.append(
            f"unexpected executed suite(s) ({len(summary.unexpected_suites)}): "
            f"{_format_suite_sample(summary.unexpected_suites)}"
        )
    if summary.total_tests == 0:
        reasons.append("total_tests == 0 (no test cases executed)")
    if summary.failures > 0:
        reasons.append(f"failures == {summary.failures}")
    if summary.errors > 0:
        reasons.append(f"errors == {summary.errors}")
    if summary.orphans > 0:
        reasons.append(f"orphans == {summary.orphans}")

    summary.failure_reasons = reasons
    return summary


def format_summary(summary: RunSummary) -> str:
    wall_str = f"{summary.wall_seconds:.2f}s" if summary.wall_seconds is not None else "n/a"
    suites_str = (
        f"{summary.suites_executed}/{summary.suites_expected}"
        if summary.suites_expected > 0
        else str(summary.suites_executed)
    )
    lines = [
        f"=== gdUnit4 Tier Summary ({summary.tier}) ===",
        f"Run ID          : {summary.run_id}",
        f"Suites executed : {suites_str}",
        f"Total test cases: {summary.total_tests}",
        f"Passed          : {summary.passed}",
        f"Failures        : {summary.failures}",
        f"Errors          : {summary.errors}",
        f"Skipped         : {summary.skipped}",
        f"Orphans         : {summary.orphans}",
        f"Wall time       : {wall_str}",
        f"Log path        : {summary.log_path}",
        f"Report dir      : {summary.reports_dir}",
    ]
    if summary.slowest_suites:
        lines.append("Slowest 5 suites:")
        for duration, label in summary.slowest_suites:
            lines.append(f"  {duration:7.3f}s  {label}")
    else:
        lines.append("Slowest 5 suites: none")

    if summary.ok:
        lines.append("Verdict         : PASS")
    else:
        lines.append(f"Verdict         : FAIL ({'; '.join(summary.failure_reasons)})")
    return "\n".join(lines)


def _cmd_list(args: argparse.Namespace) -> int:
    buckets = classify_all(Path(args.tests_dir))
    total = sum(len(v) for v in buckets.values())
    print(
        f"Total suites: {total} "
        f"(fast={len(buckets['fast'])}, medium={len(buckets['medium'])}, slow={len(buckets['slow'])})"
    )
    selected = TIERS if args.tier in (None, "all") else (args.tier,)
    for tier in selected:
        items = buckets[tier]
        print(f"\n[{tier}] ({len(items)} suites)")
        for rel in items:
            print(f"  res://tests/{rel}")
    return 0


def build_batches(
    tests_dir: Path,
    tier: str,
    max_chars: int = DEFAULT_MAX_BATCH_CHARS,
    max_suites: int | None = DEFAULT_MAX_BATCH_SUITES,
    base_overhead: int = DEFAULT_BASE_CMD_OVERHEAD,
) -> list[list[str]]:
    """Discover suites for a tier ('fast', 'medium', 'slow', or 'all') and chunk into batches."""
    if tier == "all":
        suites = discover_test_suites(tests_dir)
    elif tier in TIERS:
        suites = classify_all(tests_dir)[tier]
    else:
        raise ValueError(f"unknown tier: {tier!r}")
    return chunk_suites(
        suites,
        max_chars=max_chars,
        max_suites=max_suites,
        base_overhead=base_overhead,
    )


def _cmd_batches(args: argparse.Namespace) -> int:
    batches = build_batches(
        Path(args.tests_dir),
        args.tier,
        max_chars=args.max_chars,
        max_suites=args.max_suites,
        base_overhead=args.base_overhead,
    )
    if args.manifest_out:
        expected_batches = [[to_rel_path(p) for p in batch] for batch in batches]
        Path(args.manifest_out).write_text(
            json.dumps(expected_batches), encoding="utf-8"
        )
    for batch in batches:
        print("\t".join(batch))
    return 0


def _cmd_summarize(args: argparse.Namespace) -> int:
    codes = [int(c) for c in args.batch_codes.split(",") if c != ""]
    expected_batches: list[list[str]] | None = None
    if args.expected_batches:
        expected_batches = json.loads(
            Path(args.expected_batches).read_text(encoding="utf-8")
        )
    summary = summarize_run(
        tier=args.tier,
        run_id=args.run_id,
        reports_dir=Path(args.reports_dir),
        log_file=Path(args.log_file),
        batch_codes=codes,
        wall_seconds=args.wall_seconds,
        expected_batches=expected_batches,
    )
    print(format_summary(summary))
    return 0 if summary.ok else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="gdUnit4 test tier helper")
    sub = parser.add_subparsers(dest="command", required=True)

    p_list = sub.add_parser("list", help="List suite counts and files by tier")
    p_list.add_argument("--tests-dir", default="game/tests")
    p_list.add_argument("--tier", choices=("fast", "medium", "slow", "all"), default=None)
    p_list.set_defaults(func=_cmd_list)

    p_batches = sub.add_parser("batches", help="Emit tab-separated res:// batches")
    p_batches.add_argument("--tests-dir", default="game/tests")
    p_batches.add_argument("--tier", choices=("fast", "medium", "slow", "all"), required=True)
    p_batches.add_argument("--max-chars", type=int, default=DEFAULT_MAX_BATCH_CHARS)
    p_batches.add_argument("--max-suites", type=int, default=DEFAULT_MAX_BATCH_SUITES)
    p_batches.add_argument("--base-overhead", type=int, default=DEFAULT_BASE_CMD_OVERHEAD)
    p_batches.add_argument("--manifest-out", default=None)
    p_batches.set_defaults(func=_cmd_batches)

    p_sum = sub.add_parser("summarize", help="Parse XML reports + log and print verdict")
    p_sum.add_argument("--tier", choices=("fast", "medium", "slow", "all"), required=True)
    p_sum.add_argument("--run-id", required=True)
    p_sum.add_argument("--reports-dir", required=True)
    p_sum.add_argument("--log-file", required=True)
    p_sum.add_argument("--batch-codes", required=True)
    p_sum.add_argument("--wall-seconds", type=float, default=None)
    p_sum.add_argument("--expected-batches", default=None)
    p_sum.set_defaults(func=_cmd_summarize)

    return parser


def main(argv: list[str] | None = None) -> int:
    if hasattr(signal, "SIGPIPE"):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
