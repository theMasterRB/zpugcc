"""Host checks of the result reader, NOT execution tests of the ZPU."""
import importlib.util
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "tools/run.py"
SPEC = importlib.util.spec_from_file_location("runner", SCRIPT)
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class ResultReaderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.run_dir = Path(self.temp.name)
        self.manifest = runner.read_manifest()
        self.words = [0] * (self.manifest["layout"]["ram_bytes"] // 4)
        self.words[0x1000 // 4] = 0x5a505530
        for slot, (value, _) in enumerate(self.manifest["tests"]["addition"]):
            self.words[0x1010 // 4 + slot] = int(value, 16)
        (self.run_dir / "status.txt").write_text("HALT cycles=100\n")
        self.write_dump()

    def write_dump(self):
        (self.run_dir / "dump.hex").write_text(
            "".join(f"{word:08x}\n" for word in self.words))

    def judge(self):
        return runner.judge("addition", self.run_dir, self.manifest)

    def test_valid_fixture_is_accepted(self):
        self.assertEqual(self.judge(), [])

    def test_wrong_result_is_reported(self):
        self.words[0x1010 // 4] = 6
        self.write_dump()
        failures = self.judge()
        self.assertEqual(len(failures), 1)
        self.assertIn("slot 0", failures[0])

    def test_zero_memory_and_breakpoint_are_not_a_pass(self):
        self.words = [0] * len(self.words)
        self.write_dump()
        with self.assertRaisesRegex(ValueError, "Incomplete execution"):
            self.judge()

    def test_timeout_is_rejected_even_with_matching_memory(self):
        (self.run_dir / "status.txt").write_text("TIMEOUT\n")
        with self.assertRaisesRegex(ValueError, "did not halt"):
            self.judge()

    def test_missing_dump_is_rejected(self):
        (self.run_dir / "dump.hex").unlink()
        with self.assertRaises(FileNotFoundError):
            self.judge()

    def test_truncated_dump_is_rejected(self):
        (self.run_dir / "dump.hex").write_text("00000000\n")
        with self.assertRaisesRegex(ValueError, "full RAM dump"):
            self.judge()

    def test_unknown_memory_is_rejected(self):
        dump = self.run_dir / "dump.hex"
        dump.write_text(dump.read_text().replace("00000000", "xxxxxxxx", 1))
        with self.assertRaisesRegex(ValueError, "Malformed/unknown"):
            self.judge()

    def test_io_access_is_rejected(self):
        (self.run_dir / "status.txt").write_text("IO_ACCESS\n")
        with self.assertRaisesRegex(ValueError, "did not halt"):
            self.judge()

    def test_hex_conversion_is_big_endian_and_pads_at_end(self):
        self.assertEqual(runner.binary_to_hex(bytes.fromhex("12345678ab")),
                         "12345678\nab000000\n")

    def test_emulated_opcode_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Non-Tier-0"):
            runner.check_opcodes(bytes([0x80, 50, 0]))

    def test_straight_line_trace_and_instruction_count(self):
        (self.run_dir / "trace.txt").write_text(
            "# PC OPCODE SP TOS NOS\n00000000 0b 00007ff8 0 0\n00000001 00 00007ff8 0 0\n")
        (self.run_dir / "status.txt").write_text("HALT instructions=2\n")
        runner.validate_trace(bytes([11, 0]), self.run_dir)

    def test_profiler_duplicate_rows_are_rejected(self):
        (self.run_dir / "trace.txt").write_text(
            "00000000 0b 00007ff8 0 0\n00000000 0b 00007ff8 0 0\n00000001 00 00007ff8 0 0\n")
        (self.run_dir / "status.txt").write_text("HALT instructions=3\n")
        with self.assertRaisesRegex(ValueError, "one row per code byte"):
            runner.validate_trace(bytes([11, 0]), self.run_dir)


class Java8AdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.reference = json.loads((runner.ROOT / "reference.json").read_text())
        source = self.root / self.reference["adapter"]
        source.parent.mkdir(parents=True)
        shutil.copyfile(runner.ROOT / self.reference["adapter"], source)
        directory = self.root / self.reference["adapter_bytecode"]["directory"]
        directory.mkdir()
        for name in self.reference["adapter_bytecode"]["classes"]:
            shutil.copyfile(runner.ROOT / self.reference["adapter_bytecode"]["directory"] / name,
                            directory / name)
        # Fixture JAR is never executed; this checks command/checksum construction.
        self.jar = self.root / "fixture.jar"
        self.jar.write_bytes(b"fixture, not an executable simulator")
        self.reference["jar_sha256"] = hashlib.sha256(self.jar.read_bytes()).hexdigest()
        self.write_reference()

    def write_reference(self):
        (self.root / "reference.json").write_text(json.dumps(self.reference))

    def command(self):
        with patch.object(runner, "ROOT", self.root), \
                patch.object(runner.shutil, "which", return_value="/example/java"):
            return runner.reference_command(self.jar)

    def test_launches_class_instead_of_source_file(self):
        command = self.command()
        self.assertEqual(command[-1], "ReferenceRunner")
        self.assertFalse(any(arg.endswith(".java") for arg in command))

    def test_modified_class_is_rejected(self):
        name = next(iter(self.reference["adapter_bytecode"]["classes"]))
        path = self.root / self.reference["adapter_bytecode"]["directory"] / name
        path.write_bytes(path.read_bytes() + b"changed")
        with self.assertRaisesRegex(ValueError, "pinned checksum"):
            self.command()

    def test_modified_source_requires_rebuild(self):
        path = self.root / self.reference["adapter"]
        path.write_text(path.read_text() + "\n// changed\n")
        with self.assertRaisesRegex(ValueError, "rebuild"):
            self.command()

    def test_newer_class_format_is_rejected(self):
        name = next(iter(self.reference["adapter_bytecode"]["classes"]))
        path = self.root / self.reference["adapter_bytecode"]["directory"] / name
        raw = bytearray(path.read_bytes())
        raw[6:8] = (53).to_bytes(2, "big")
        path.write_bytes(raw)
        self.reference["adapter_bytecode"]["classes"][name] = hashlib.sha256(raw).hexdigest()
        self.write_reference()
        with self.assertRaisesRegex(ValueError, "Java 8 format"):
            self.command()


if __name__ == "__main__":
    unittest.main()
