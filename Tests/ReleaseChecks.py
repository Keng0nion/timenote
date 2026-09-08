"""检查公开源码可独立构建，以及发布标识和路径隐私保护。"""

import importlib.util
import plistlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("timenote_build", ROOT / "build.py")
if spec is None or spec.loader is None:
    raise RuntimeError("无法加载本仓库的构建脚本")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class ReleaseChecks(unittest.TestCase):
    def test_core_is_inside_repository(self):
        self.assertIn(ROOT, build.CORE.parents, "公开仓库不能依赖仓库外的基础代码")
        self.assertTrue(build.CORE.is_file())

    def test_compiler_remaps_private_paths(self):
        source = (ROOT / "build.py").read_text()
        self.assertIn('"-file-prefix-map"', source)
        self.assertIn('"-debug-prefix-map"', source)
        self.assertIn('"-file-compilation-dir", "/timenote"', source)

    def test_public_copy_and_release_identity(self):
        sources = ROOT / "Sources" / "TimeNoteNative"
        settings = (sources / "SettingsView.swift").read_text()
        app = (sources / "AppMain.swift").read_text()
        third_party = (ROOT / "Resources" / "第三方说明.txt").read_text()
        for text in [settings, third_party]:
            self.assertNotIn("未公开发布", text)
            self.assertNotIn("原始问卷", text)
        self.assertIn("0.1.2 公开预览版", app)
        views = (sources / "Views.swift").read_text()
        self.assertNotIn("本地试用版", views)
        self.assertIn("0.1.2 · 公开预览版", views)
        with (ROOT / "Resources" / "Info.plist").open("rb") as file:
            info = plistlib.load(file)
        self.assertEqual(info["CFBundleShortVersionString"], "0.1.2")
        self.assertEqual(info["CFBundleVersion"], "3")
        self.assertEqual(info["CFBundleIdentifier"], "local.timenote.native.v1")
        self.assertEqual(info["CFBundleExecutable"], "TimeNote")

    def test_recurring_action_ui_and_explanation(self):
        sources = ROOT / "Sources" / "TimeNoteNative"
        choices = (sources / "GoalAssignment.swift").read_text()
        goals = (sources / "ReviewViews.swift").read_text()
        self.assertIn("groupedCandidates", choices)
        self.assertIn("WorkAction.grouped(tasks)", choices)
        self.assertIn("setGoal(action:", choices)
        self.assertNotIn("重复安排也只处理选中的这一天", choices)
        self.assertIn("WorkAction.grouped(tasks)", goals)
        self.assertIn("推进目标的行动", goals)
        self.assertNotIn("ForEach(tasks.prefix(12))", goals)
        for name in ["README.md", "RELEASE_NOTES.md"]:
            text = (ROOT / name).read_text()
            self.assertIn("持续行动", text)
            self.assertIn("整组", text)
            self.assertNotIn("重复任务的其他日期不自动跟着变", text)

    def test_main_license_and_bundled_entry(self):
        license_path = ROOT / "LICENSE"
        self.assertTrue(license_path.is_file(), "主项目必须提供 LICENSE")
        text = license_path.read_text()
        self.assertTrue(text.startswith("MIT License\n"))
        self.assertIn("Copyright (c) 2026 Kengo Kubota and Keng0nion", text)
        self.assertIn("Permission is hereby granted, free of charge", text)
        self.assertIn("The above copyright notice and this permission notice", text)
        self.assertIn('THE SOFTWARE IS PROVIDED "AS IS"', text)
        source = (ROOT / "build.py").read_text()
        self.assertIn('shutil.copy2(ROOT / "LICENSE", contents / "Resources" / "TimeNote-LICENSE.txt")', source)
        settings = (ROOT / "Sources" / "TimeNoteNative" / "SettingsView.swift").read_text()
        self.assertIn('openLicense("TimeNote-LICENSE")', settings)
        self.assertIn("Kengo Kubota", settings)
        self.assertIn("Keng0nion", settings)
        for name in ["README.md", "RELEASE_NOTES.md", "Resources/第三方说明.txt"]:
            text = (ROOT / name).read_text()
            self.assertNotIn("许可证尚未选择", text)
            self.assertIn("MIT", text)
            self.assertIn("Kengo Kubota", text)
            self.assertIn("Keng0nion", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
