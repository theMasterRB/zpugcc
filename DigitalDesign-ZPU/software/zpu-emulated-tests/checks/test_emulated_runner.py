"""Checker regressions: native bypass, bad vector/return/SP, and stale inputs.

These host fixtures test the judge. They are not additional CPU executions.
"""
from pathlib import Path
from contextlib import redirect_stdout
import io
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import run_emulated as runner


class EmulationTraceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.record = {"entry_pc": 0x2000, "final_pc": 0x2001,
                       "code_ranges": [[0x240, 0x241], [0x2000, 0x2002]], "opcode": 50}
        self.raw = bytearray(0x2002)
        self.raw[0x2000] = 50
        self.raw[0x240] = 4
        self.rows = [[0x2000, 50, 0x77f4, 3, 5],
                     [0x240, 4, 0x77f0, 0x2001, 3],
                     [0x2001, 0, 0x77f8, 6, 0x6a09e667]]

    def validate(self):
        (self.directory / "trace.txt").write_text("".join(
            " ".join(f"{field:x}" for field in row) + "\n" for row in self.rows))
        (self.directory / "status.txt").write_text(f"HALT instructions={len(self.rows)}\n")
        return runner.validate_trace(self.raw, self.directory, self.record, {50})

    def test_software_dispatch_is_accepted(self):
        self.assertEqual(self.validate(), 3)

    def test_native_bypass_is_rejected(self):
        del self.rows[1]
        with self.assertRaisesRegex(ValueError, "Missing software dispatch"):
            self.validate()

    def test_wrong_vector_is_rejected(self):
        self.rows[1][0] = 0x220
        with self.assertRaisesRegex(ValueError, "Missing software dispatch"):
            self.validate()

    def test_wrong_dispatch_return_address_is_rejected(self):
        self.rows[1][3] = 0x2000
        with self.assertRaisesRegex(ValueError, "Missing software dispatch"):
            self.validate()

    def test_wrong_dispatch_stack_effect_is_rejected(self):
        self.rows[1][2] += 4
        with self.assertRaisesRegex(ValueError, "Missing software dispatch"):
            self.validate()

    def test_missing_completion_breakpoint_is_rejected(self):
        self.rows.pop()
        with self.assertRaisesRegex(ValueError, "expected final breakpoint"):
            self.validate()

    def test_fetch_outside_code_is_rejected(self):
        self.rows.insert(2, [0x1000, 0, 0x77f8, 6, 7])
        with self.assertRaisesRegex(ValueError, "invalid state"):
            self.validate()

    def test_unaligned_stack_is_rejected(self):
        self.rows[-1][2] += 1
        with self.assertRaisesRegex(ValueError, "invalid state"):
            self.validate()


class IndependentCliTests(unittest.TestCase):
    def test_handler_line_endings_are_portable_but_code_changes_are_detected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "emulated_cases.json").write_text('{"handler_source": "crt0.S"}')
            handler = root / "crt0.S"
            with mock.patch.object(runner, "ROOT", root):
                handler.write_bytes(b"loadsp 4\npoppc\n")
                expected = runner.handler_digest()
                handler.write_bytes(b"loadsp 4\r\npoppc\r\n")
                self.assertEqual(runner.handler_digest(), expected)
                handler.write_bytes(b"loadsp 8\r\npoppc\r\n")
                self.assertNotEqual(runner.handler_digest(), expected)

    def check_help(self, include_native):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "emulated_cases.json").write_text('{"tests": {"eq": {}}}')
            if include_native:
                (root / "tier0").mkdir()
                (root / "manifest.json").write_text(
                    '{"tests": {"native": [["0x00000000", "fixture"]]}}')
            output = io.StringIO()
            with mock.patch.object(runner, "ROOT", root), \
                    mock.patch.object(runner.tier0, "ROOT", root), \
                    mock.patch.object(sys, "argv", ["run_emulated.py", "--help"]), \
                    redirect_stdout(output):
                with self.assertRaises(SystemExit) as stopped:
                    runner.main()
            self.assertEqual(stopped.exception.code, 0)
            self.assertEqual("cpp-tier0" in output.getvalue(), include_native)

    def test_cli_runs_without_original_hardware_suite(self):
        self.check_help(False)

    def test_combined_suite_retains_optional_native_command(self):
        self.check_help(True)


if __name__ == "__main__":
    unittest.main()
