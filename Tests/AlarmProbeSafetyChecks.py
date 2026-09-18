"""只执行帮助和无许可的拒绝路径，不启动窗口或真实音频。"""

import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / ".build-local" / "alarm-probe" / "alarm-probe"


class AlarmProbeSafetyChecks(unittest.TestCase):
    def invoke(self, arguments):
        self.assertTrue(BINARY.is_file(), "请先只编译独立验证工具；当前尚无可检查程序")
        before = set(BINARY.parent.glob("trial-*"))
        result = subprocess.run([str(BINARY), *arguments], cwd=ROOT,
                                capture_output=True, text=True, timeout=5, check=False)
        self.assertEqual(before, set(BINARY.parent.glob("trial-*")), "拒绝路径不能创建试验记录")
        return result

    def test_help_has_no_audio(self):
        result = self.invoke(["--help"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("不打开窗口或音频设备", result.stdout)
        self.assertIn("--approve-audio", result.stdout)

    def test_no_arguments_refuses(self):
        result = self.invoke([])
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn("拒绝启动", result.stderr)

    def test_parameters_without_permission_refuse(self):
        result = self.invoke(["--delay", "10", "--tolerance", "1", "--max-duration", "60", "--volume", "0.15"])
        self.assertEqual(result.returncode, 2, result.stdout)

    def test_permission_without_parameters_refuses(self):
        result = self.invoke(["--approve-audio"])
        self.assertEqual(result.returncode, 2, result.stdout)

    def test_bad_parameters_refuse_even_with_permission(self):
        result = self.invoke(["--approve-audio", "--delay", "10", "--tolerance", "1", "--max-duration", "60", "--volume", "nan"])
        self.assertEqual(result.returncode, 2, result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
