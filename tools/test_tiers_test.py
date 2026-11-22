#!/usr/bin/env python3
"""Unit tests for tools/test_tiers.py."""

from __future__ import annotations

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_tiers  # noqa: E402


REPO_ROOT = Path(__file__).resolve().parent.parent
LIVE_TESTS_DIR = REPO_ROOT / "game" / "tests"


def _write_file(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def _write_results_xml(
    reports_dir: Path,
    batch_idx: int,
    suites: list[tuple[str, int, int, int, int, float]],
) -> None:
    """Create a JUnit results.xml matching GdUnit4's JUnitXmlReportWriter format."""
    total_tests = sum(s[1] for s in suites)
    total_failures = sum(s[2] for s in suites)
    total_skipped = sum(s[4] for s in suites)
    total_time = sum(s[5] for s in suites)
    lines = [
        '<?xml version="1.0" encoding="UTF-8" ?>',
        (
            f'<testsuites id="2026-11-22" name="report_1" tests="{total_tests}" '
            f'failures="{total_failures}" skipped="{total_skipped}" flaky="0" '
            f'time="{total_time:.3f}">'
        ),
    ]
    for idx, (pkg, tests, failures, errors, skipped, duration) in enumerate(suites):
        clean_pkg = pkg.removeprefix("res://")
        suite_name = Path(clean_pkg).stem
        pkg_dir = Path(clean_pkg).parent.as_posix()
        lines.append(
            f'  <testsuite id="{idx}" name="{suite_name}" package="{pkg_dir}" '
            f'timestamp="2026-11-22T00:00:00" hostname="localhost" '
            f'tests="{tests}" failures="{failures}" errors="{errors}" '
            f'skipped="{skipped}" flaky="0" time="{duration:.3f}" />'
        )
    lines.append("</testsuites>")
    xml_path = reports_dir / f"b{batch_idx}" / "report_1" / "results.xml"
    _write_file(xml_path, "\n".join(lines) + "\n")


class TestTiersClassification(unittest.TestCase):
    def test_live_tree_full_partition_and_disjointness(self) -> None:
        all_suites = test_tiers.discover_test_suites(LIVE_TESTS_DIR)
        self.assertGreater(len(all_suites), 0)

        buckets = test_tiers.classify_all(LIVE_TESTS_DIR)
        fast_set = set(buckets["fast"])
        medium_set = set(buckets["medium"])
        slow_set = set(buckets["slow"])
        all_set = set(all_suites)

        self.assertEqual(fast_set | medium_set | slow_set, all_set)
        self.assertEqual(fast_set & medium_set, set())
        self.assertEqual(fast_set & slow_set, set())
        self.assertEqual(medium_set & slow_set, set())
        self.assertEqual(
            len(buckets["fast"]) + len(buckets["medium"]) + len(buckets["slow"]),
            len(all_suites),
        )

    def test_gdignore_directory_and_non_test_files_excluded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_file(root / "core" / "test_alpha.gd", "extends GdUnitTestSuite\n")
            _write_file(root / "core" / "helper_kit.gd", "extends RefCounted\n")
            _write_file(root / "ignored" / ".gdignore", "")
            _write_file(root / "ignored" / "test_hidden.gd", "extends GdUnitTestSuite\n")
            _write_file(
                root / "ignored" / "nested" / "test_nested_hidden.gd",
                "extends GdUnitTestSuite\n",
            )

            discovered = test_tiers.discover_test_suites(root)
            self.assertEqual(discovered, ["core/test_alpha.gd"])

    def test_classification_rules_and_precedence(self) -> None:
        cases = [
            ("ui/test_hud.gd", 'var s = load("res://main/main.tscn")', "slow"),
            ("pax/test_views.gd", "var v: PassengerViews", "slow"),
            ("save/test_x.gd", "var k := SaveTestKit.run_path('a')", "slow"),
            ("save/test_y.gd", 'var f := "user://foo.dat"', "slow"),
            ("pax/test_flow_tuning.gd", "func test_ok(): pass", "slow"),
            ("pax/test_economy_balance.gd", "func test_ok(): pass", "slow"),
            ("pax/test_flight_deadline.gd", "func test_ok(): pass", "slow"),
            ("pax/test_state_snapshot.gd", "func test_ok(): pass", "slow"),
            ("pax/test_world_save.gd", "func test_ok(): pass", "slow"),
            ("land/test_slot_saves.gd", "func test_ok(): pass", "slow"),
            ("pax/test_world_load.gd", "func test_ok(): pass", "slow"),
            ("flt/test_gp_kit.gd", "var k := GroundPlannerKit.new()", "slow"),
            # Slow beats Medium if both match
            (
                "ui/test_combo.gd",
                "await get_tree().process_frame\nvar p = PassengerViews.new()",
                "slow",
            ),
            # Medium rules
            ("ui/test_vp.gd", "var vp := SubViewport.new()", "medium"),
            ("core/test_async.gd", "func test_a(): await get_tree().process_frame", "medium"),
            ("ui/test_tree.gd", "func test_t(): add_child(Node.new())", "medium"),
            ("pax/test_world.gd", "var w := PaxTestWorld.make()", "medium"),
            ("air/test_grid.gd", "var g := BuildGrid.new(Vector2i.ONE, Vector3.ZERO)", "medium"),
            ("flt/test_sim.gd", "var sim := FlightSim.new()", "medium"),
            ("bld/test_site.gd", 'const SITE := preload("res://build/terminal_site.tres")', "medium"),
            ("air/test_gate.gd", "var w := GateWalkWorld.new()", "medium"),
            ("core/test_major.gd", "extends MajorTestBase", "medium"),
            ("econ/test_wages.gd", "var s := SettlementWagesKit.new()", "medium"),
            ("ui/test_scene.gd", 'var x = "res://ui/panel.tscn"', "medium"),
            ("art/test_mesh.gd", 'var g = "res://art/chair.glb"', "medium"),
            ("art/test_rig.gd", "var r := CharacterRig.new()", "medium"),
            # Fast fallback
            ("core/test_math.gd", "extends GdUnitTestSuite\nfunc test_add(): pass", "fast"),
        ]
        for rel, content, expected in cases:
            with self.subTest(rel=rel):
                self.assertEqual(test_tiers.classify_suite(rel, content), expected)


class TestBatchChunker(unittest.TestCase):
    BASE_CMD = (
        '"C:/Users/chulf/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe" '
        "--headless --path game --audio-driver Dummy --remote-debug tcp://127.0.0.1:0 "
        "-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c "
        '-rd "res://reports/run_medium_20261122T122914Z_AbCdEf/b000" -rc 20'
    )

    def _render_full_cmd(self, batch: list[str]) -> str:
        args = " ".join(f'"-a" "{p}"' for p in batch)
        return f"{self.BASE_CMD} {args}"

    def test_chunker_respects_max_chars_with_full_cmd_overhead(self) -> None:
        suites = [f"area_{i // 10}/test_suite_{i:03d}.gd" for i in range(55)]
        overhead = len(self.BASE_CMD) + 16
        batches = test_tiers.chunk_suites(
            suites, max_chars=700, max_suites=None, base_overhead=overhead
        )
        self.assertGreater(len(batches), 1)

        reconstructed: list[str] = []
        for batch in batches:
            rendered = self._render_full_cmd(batch)
            self.assertLessEqual(len(rendered), 700)
            reconstructed.extend(batch)

        self.assertEqual(reconstructed, [f"res://tests/{s}" for s in suites])

    def test_chunker_respects_max_suites(self) -> None:
        suites = [f"a/test_{i:03d}.gd" for i in range(10)]
        batches = test_tiers.chunk_suites(suites, max_chars=20_000, max_suites=4)
        self.assertEqual([len(b) for b in batches], [4, 4, 2])

    def test_live_tiers_full_rendered_cmd_under_20000_ceiling(self) -> None:
        buckets = test_tiers.classify_all(LIVE_TESTS_DIR)
        overhead = max(test_tiers.DEFAULT_BASE_CMD_OVERHEAD, len(self.BASE_CMD) + 16)
        for tier in ("fast", "medium", "slow"):
            batches = test_tiers.chunk_suites(
                buckets[tier],
                max_chars=test_tiers.DEFAULT_MAX_BATCH_CHARS,
                base_overhead=overhead,
            )
            flat = [p for b in batches for p in b]
            self.assertEqual(flat, [f"res://tests/{s}" for s in buckets[tier]])
            for batch in batches:
                self.assertLessEqual(len(batch), test_tiers.DEFAULT_MAX_BATCH_SUITES)
                rendered = self._render_full_cmd(batch)
                self.assertLessEqual(len(rendered), 20_000)

    def test_all_tier_live_tree_multi_batch_caps_and_complete_coverage(self) -> None:
        all_suites = test_tiers.discover_test_suites(LIVE_TESTS_DIR)
        overhead = max(test_tiers.DEFAULT_BASE_CMD_OVERHEAD, len(self.BASE_CMD) + 16)
        batches = test_tiers.build_batches(
            LIVE_TESTS_DIR,
            "all",
            max_chars=test_tiers.DEFAULT_MAX_BATCH_CHARS,
            max_suites=test_tiers.DEFAULT_MAX_BATCH_SUITES,
            base_overhead=overhead,
        )
        self.assertGreater(len(batches), 1)

        flat = [p for b in batches for p in b]
        self.assertEqual(len(flat), len(all_suites))
        self.assertEqual(len(set(flat)), len(all_suites))
        self.assertEqual(set(flat), {f"res://tests/{s}" for s in all_suites})

        for batch in batches:
            self.assertGreater(len(batch), 0)
            self.assertLessEqual(len(batch), test_tiers.DEFAULT_MAX_BATCH_SUITES)
            rendered = self._render_full_cmd(batch)
            self.assertLessEqual(len(rendered), 20_000)

    def test_cli_batches_all_writes_chunked_manifest_and_stdout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tests_dir = root / "tests"
            suites = [f"area_{i // 3}/test_suite_{i:02d}.gd" for i in range(8)]
            for rel in suites:
                _write_file(tests_dir / rel, "extends GdUnitTestSuite\n")
            _write_file(tests_dir / "helper.gd", "extends RefCounted\n")
            manifest = root / "expected_batches.json"

            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = test_tiers.main(
                    [
                        "batches",
                        "--tests-dir",
                        str(tests_dir),
                        "--tier",
                        "all",
                        "--max-suites",
                        "3",
                        "--max-chars",
                        "500",
                        "--base-overhead",
                        "200",
                        "--manifest-out",
                        str(manifest),
                    ]
                )

            self.assertEqual(rc, 0)
            lines = [line for line in buf.getvalue().splitlines() if line.strip()]
            self.assertGreater(len(lines), 1)
            self.assertNotIn("res://tests", lines)

            stdout_batches = [line.split("\t") for line in lines]
            manifest_batches = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(len(stdout_batches), len(manifest_batches))

            flat_stdout = [p for b in stdout_batches for p in b]
            flat_manifest = [p for b in manifest_batches for p in b]
            self.assertEqual(flat_stdout, [f"res://tests/{s}" for s in suites])
            self.assertEqual(flat_manifest, suites)
            for batch in stdout_batches:
                self.assertLessEqual(len(batch), 3)
                cmd_len = 200 + sum(
                    len(p) + test_tiers.PER_SUITE_ARG_OVERHEAD for p in batch
                )
                self.assertLessEqual(cmd_len, 500)


class TestSummaryParser(unittest.TestCase):
    def test_clean_xml_and_exit_zero_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reports = root / "reports"
            _write_results_xml(
                reports,
                0,
                [
                    ("res://tests/a/test_one.gd", 5, 0, 0, 0, 0.400),
                    ("res://tests/a/test_two.gd", 10, 0, 0, 1, 1.250),
                ],
            )
            _write_results_xml(
                reports,
                1,
                [
                    ("res://tests/b/test_three.gd", 3, 0, 0, 0, 0.800),
                ],
            )
            log_file = root / "run.log"
            _write_file(
                log_file,
                "\x1b[34mOverall Summary:\x1b[0m 15 test cases | 0 errors | 0 failures | 0 flaky | 1 skipped | 0 orphans |\n"
                "Overall Summary: 3 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans |\n",
            )

            summary = test_tiers.summarize_run(
                tier="fast",
                run_id="fast_test",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[0, 0],
                wall_seconds=3.5,
                expected_batches=[
                    ["a/test_one.gd", "a/test_two.gd"],
                    ["b/test_three.gd"],
                ],
            )
            self.assertTrue(summary.ok, summary.failure_reasons)
            self.assertEqual(summary.suites_expected, 3)
            self.assertEqual(summary.suites_executed, 3)
            self.assertEqual(summary.total_tests, 18)
            self.assertEqual(summary.passed, 17)
            self.assertEqual(summary.skipped, 1)
            self.assertEqual(summary.failures, 0)
            self.assertEqual(summary.errors, 0)
            self.assertEqual(summary.orphans, 0)
            self.assertEqual(
                summary.slowest_suites[0], (1.250, "tests/a/test_two")
            )
            rendered = test_tiers.format_summary(summary)
            self.assertIn("Suites executed : 3/3", rendered)
            self.assertIn("Verdict         : PASS", rendered)

    def test_fails_on_missing_expected_suite(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reports = root / "reports"
            _write_results_xml(
                reports,
                0,
                [("res://tests/a/test_one.gd", 4, 0, 0, 0, 0.200)],
            )
            log_file = root / "run.log"
            _write_file(log_file, "")
            summary = test_tiers.summarize_run(
                tier="fast",
                run_id="r_missing",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[0],
                expected_batches=[["a/test_one.gd", "a/test_missing.gd"]],
            )
            self.assertFalse(summary.ok)
            self.assertEqual(summary.missing_suites, ["a/test_missing.gd"])
            self.assertIn("missing expected suite(s)", " ".join(summary.failure_reasons))

    def test_fails_on_duplicate_suite_across_batches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reports = root / "reports"
            _write_results_xml(
                reports, 0, [("res://tests/a/test_one.gd", 4, 0, 0, 0, 0.200)]
            )
            _write_results_xml(
                reports, 1, [("res://tests/a/test_one.gd", 4, 0, 0, 0, 0.200)]
            )
            log_file = root / "run.log"
            _write_file(log_file, "")
            summary = test_tiers.summarize_run(
                tier="fast",
                run_id="r_dup",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[0, 0],
                expected_batches=[["a/test_one.gd"], ["a/test_one.gd"]],
            )
            self.assertFalse(summary.ok)
            self.assertEqual(summary.duplicate_suites, ["a/test_one.gd"])
            self.assertIn("duplicate executed suite(s)", " ".join(summary.failure_reasons))

    def test_fails_on_unexpected_extra_suite_in_explicit_tier(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reports = root / "reports"
            _write_results_xml(
                reports,
                0,
                [
                    ("res://tests/a/test_one.gd", 4, 0, 0, 0, 0.200),
                    ("res://tests/a/test_extra.gd", 2, 0, 0, 0, 0.100),
                ],
            )
            log_file = root / "run.log"
            _write_file(log_file, "")
            summary = test_tiers.summarize_run(
                tier="fast",
                run_id="r_extra",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[0],
                expected_batches=[["a/test_one.gd"]],
            )
            self.assertFalse(summary.ok)
            self.assertEqual(summary.unexpected_suites, ["a/test_extra.gd"])
            self.assertIn("unexpected executed suite(s)", " ".join(summary.failure_reasons))

    def test_all_tier_allows_zero_test_non_test_helper_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reports = root / "reports"
            _write_results_xml(
                reports,
                0,
                [
                    ("res://tests/a/test_one.gd", 4, 0, 0, 0, 0.200),
                    ("res://tests/pax/passenger_test_world.gd", 0, 0, 0, 0, 0.001),
                ],
            )
            log_file = root / "run.log"
            _write_file(log_file, "")
            summary = test_tiers.summarize_run(
                tier="all",
                run_id="r_all",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[0],
                expected_batches=[["a/test_one.gd"]],
            )
            self.assertTrue(summary.ok, summary.failure_reasons)
            self.assertEqual(summary.suites_executed, 1)

    def test_fails_on_multiple_xml_reports_in_single_batch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reports = root / "reports"
            _write_results_xml(
                reports, 0, [("res://tests/a/test_one.gd", 4, 0, 0, 0, 0.200)]
            )
            second_xml = reports / "b0" / "report_2" / "results.xml"
            _write_file(second_xml, (reports / "b0" / "report_1" / "results.xml").read_text())
            log_file = root / "run.log"
            _write_file(log_file, "")
            summary = test_tiers.summarize_run(
                tier="fast",
                run_id="r_multi",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[0],
                expected_batches=[["a/test_one.gd"]],
            )
            self.assertFalse(summary.ok)
            self.assertEqual(summary.multiple_xml_batches, {0: 2})
            self.assertIn("multiple results.xml files", " ".join(summary.failure_reasons))

    def test_fails_on_exit_101_orphans(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reports = root / "reports"
            _write_results_xml(
                reports,
                0,
                [("res://tests/a/test_one.gd", 4, 0, 0, 0, 0.200)],
            )
            log_file = root / "run.log"
            _write_file(
                log_file,
                "Overall Summary: 4 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 3 orphans |\n",
            )
            summary = test_tiers.summarize_run(
                tier="fast",
                run_id="r1",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[101],
            )
            self.assertFalse(summary.ok)
            self.assertEqual(summary.orphans, 3)
            joined = " ".join(summary.failure_reasons)
            self.assertIn("101", joined)
            self.assertIn("orphans == 3", joined)

    def test_fails_on_exit_100_failures(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reports = root / "reports"
            _write_results_xml(
                reports,
                0,
                [("res://tests/a/test_one.gd", 4, 1, 0, 0, 0.200)],
            )
            log_file = root / "run.log"
            _write_file(log_file, "")
            summary = test_tiers.summarize_run(
                tier="fast",
                run_id="r2",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[100],
            )
            self.assertFalse(summary.ok)
            joined = " ".join(summary.failure_reasons)
            self.assertIn("100", joined)
            self.assertIn("failures == 1", joined)

    def test_fails_on_zero_tests_even_if_exit_zero(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reports = root / "reports"
            _write_results_xml(reports, 0, [])
            log_file = root / "run.log"
            _write_file(log_file, "No test cases found, abort test run!\n")
            summary = test_tiers.summarize_run(
                tier="fast",
                run_id="r3",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[0],
            )
            self.assertFalse(summary.ok)
            self.assertIn("total_tests == 0", " ".join(summary.failure_reasons))

    def test_fails_on_missing_xml(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reports = root / "reports"
            reports.mkdir(parents=True)
            log_file = root / "run.log"
            _write_file(log_file, "")
            summary = test_tiers.summarize_run(
                tier="fast",
                run_id="r4",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[0],
            )
            self.assertFalse(summary.ok)
            self.assertIn("missing results.xml", " ".join(summary.failure_reasons))

    def test_all_tier_multi_batch_xml_reconciliation_pass_and_timeout_fail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reports = root / "reports"
            _write_results_xml(
                reports,
                0,
                [
                    ("res://tests/a/test_one.gd", 4, 0, 0, 0, 0.300),
                    ("res://tests/a/test_two.gd", 6, 0, 0, 0, 0.500),
                ],
            )
            _write_results_xml(
                reports,
                1,
                [
                    ("res://tests/b/test_three.gd", 5, 0, 0, 1, 1.100),
                ],
            )
            _write_results_xml(
                reports,
                2,
                [
                    ("res://tests/c/test_four.gd", 2, 0, 0, 0, 0.200),
                ],
            )
            log_file = root / "run.log"
            _write_file(
                log_file,
                "Overall Summary: 10 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans |\n"
                "Overall Summary: 5 test cases | 0 errors | 0 failures | 0 flaky | 1 skipped | 0 orphans |\n"
                "Overall Summary: 2 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans |\n",
            )
            expected = [
                ["a/test_one.gd", "a/test_two.gd"],
                ["b/test_three.gd"],
                ["c/test_four.gd"],
            ]
            summary = test_tiers.summarize_run(
                tier="all",
                run_id="all_ok",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[0, 0, 0],
                wall_seconds=12.4,
                expected_batches=expected,
            )
            self.assertTrue(summary.ok, summary.failure_reasons)
            self.assertEqual(summary.suites_expected, 4)
            self.assertEqual(summary.suites_executed, 4)
            self.assertEqual(summary.total_tests, 17)
            self.assertEqual(summary.passed, 16)
            self.assertEqual(summary.skipped, 1)

            # Simulate batch 1 timing out without writing results.xml
            (reports / "b1" / "report_1" / "results.xml").unlink()
            failed = test_tiers.summarize_run(
                tier="all",
                run_id="all_timeout",
                reports_dir=reports,
                log_file=log_file,
                batch_codes=[0, 124, 0],
                wall_seconds=3610.0,
                expected_batches=expected,
            )
            self.assertFalse(failed.ok)
            joined = " ".join(failed.failure_reasons)
            self.assertIn("batch 1 exited with 124", joined)
            self.assertIn("missing results.xml for batch(es): b1", joined)
            self.assertEqual(failed.suites_executed, 3)
            self.assertEqual(failed.suites_expected, 4)


if __name__ == "__main__":
    unittest.main()
