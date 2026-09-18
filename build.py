"""项目内直接编译与打包；不安装工具，不读取有冲突的 SwiftPM 接口。"""

import argparse
import hashlib
import os
import plistlib
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ALIAS = Path.home() / "Library" / "Caches" / "TimeNoteBuildAlias"
BUILD = ROOT / ".build-local"


def ensure_alias():
    # swift-driver 在 TMPDIR 指向非 ASCII 路径时可能崩溃（仓库移动到中文路径后暴露）。
    # 仓库内目录经由纯 ASCII 别名（符号链接指回仓库）作为构建临时目录，文件实体与位置不变。
    ALIAS.parent.mkdir(parents=True, exist_ok=True)
    if ALIAS.is_symlink() and ALIAS.readlink() == ROOT:
        return
    if ALIAS.is_symlink() or ALIAS.exists():
        ALIAS.unlink()
    ALIAS.symlink_to(ROOT)
VENDOR = ROOT / "Vendor"
SOURCES = ROOT / "Sources" / "TimeNoteNative"
CORE = ROOT / "Sources" / "TimeNoteCore" / "Progress.swift"
GRDB = VENDOR / "GRDB.swift-7.11.1"
KEYS = VENDOR / "KeyboardShortcuts-3.0.1"


def run(command, timeout=240):
    subprocess.run(list(map(str, command)), cwd=ROOT, env=ENV, check=True, timeout=timeout)


def compile_module(name, sources, extra):
    output = BUILD / ("lib" + name + ".dylib")
    digest = hashlib.sha256((str(COMMON) + str(extra)).encode())
    for path in sources:
        digest.update(path.read_bytes())
    marker = BUILD / (name + ".sha256")
    if output.exists() and marker.exists() and marker.read_text() == digest.hexdigest():
        print("复用已编译模块：", name, flush=True)
        return
    print("编译模块：", name, flush=True)
    run(COMMON + ["-O", "-whole-module-optimization", "-emit-library", "-emit-module",
                  "-module-name", name, "-emit-module-path", BUILD / (name + ".swiftmodule"),
                  "-Xlinker", "-install_name", "-Xlinker", "@rpath/lib" + name + ".dylib",
                  *extra, *sources, "-o", output], timeout=300)
    marker.write_text(digest.hexdigest())


def dependencies():
    if not (GRDB / "GRDB").is_dir() or not (KEYS / "Sources").is_dir():
        raise RuntimeError("请先运行 fetch_dependencies.py 下载已锁定的官方源码。")
    compile_module("GRDB", sorted((GRDB / "GRDB").rglob("*.swift")),
                   ["-I", GRDB / "Sources" / "GRDBSQLite", "-D", "SQLITE_ENABLE_FTS5",
                    "-D", "SQLITE_ENABLE_SNAPSHOT", "-enable-upcoming-feature", "MemberImportVisibility"])
    resource = BUILD / "KeyboardShortcutsResources.swift"
    resource.write_text('import Foundation\nextension Bundle {\n nonisolated static var module: Bundle {\n  guard let url = Bundle.main.resourceURL?.appendingPathComponent("KeyboardShortcuts.bundle"), let bundle = Bundle(url: url) else { return .main }\n  return bundle\n }\n}\n')
    generated = BUILD / "KeyboardShortcuts-compatible"
    generated.mkdir(exist_ok=True)
    for source in sorted((KEYS / "Sources" / "KeyboardShortcuts").glob("*.swift")):
        text = source.read_text()
        if source.name == "ConflictPolicy.swift":
            original = 'extension EnvironmentValues {\n\t@Entry\n\tvar keyboardShortcutsConflictPolicy = KeyboardShortcuts.ConflictPolicy.default\n}'
            replacement = 'private struct ConflictPolicyKey: @preconcurrency EnvironmentKey {\n @MainActor static let defaultValue = KeyboardShortcuts.ConflictPolicy.default\n}\nextension EnvironmentValues {\n var keyboardShortcutsConflictPolicy: KeyboardShortcuts.ConflictPolicy {\n  get { self[ConflictPolicyKey.self] }\n  set { self[ConflictPolicyKey.self] = newValue }\n }\n}'
            if text.count(original) != 1:
                raise RuntimeError("快捷键兼容锚点变化，停止构建")
            text = text.replace(original, replacement)
        if source.name == "Recorder.swift":
            if text.count("#Preview {") != 3 or not text.rstrip().endswith("#endif"):
                raise RuntimeError("快捷键预览锚点变化，停止构建")
            text = text[:text.index("#Preview {")] + "#endif\n"
        (generated / source.name).write_text(text)
    compile_module("KeyboardShortcuts", sorted(generated.glob("*.swift")) + [resource],
                   ["-default-isolation", "MainActor", "-enable-upcoming-feature", "NonisolatedNonsendingByDefault",
                    "-enable-upcoming-feature", "InferIsolatedConformances"])


def links():
    return ["-I", BUILD, "-I", GRDB / "Sources" / "GRDBSQLite", "-L", BUILD,
            "-lGRDB", "-lKeyboardShortcuts"]


def checks():
    output = BUILD / "native-checks"
    run(COMMON + ["-warnings-as-errors", "-Onone", CORE, SOURCES / "Models.swift", SOURCES / "WorkAction.swift", SOURCES / "Repository.swift",
                  SOURCES / "AppState.swift", ROOT / "Tests" / "NativeChecks.swift", ROOT / "Tests" / "ActionChecks.swift", ROOT / "Tests" / "CockpitChecks.swift", *links(), "-Xlinker", "-rpath", "-Xlinker", BUILD,
                  "-o", output])
    run([output, BUILD / "test-data"], timeout=45)


def icon():
    output = BUILD / "icon-maker"
    run(COMMON + [ROOT / "Tools" / "Icon.swift", "-o", output])
    folder = BUILD / "TimeNote.iconset"
    run([output, folder])
    run(["/usr/bin/iconutil", "--convert", "icns", folder, "--output", ROOT / "Resources" / "TimeNote.icns"])


def app(testing=False):
    destination = ROOT / "dist" / ("时间便签测试.app" if testing else "时间便签.app")
    bundle = BUILD / "package" / ("TimeNote-test" if testing else "TimeNote")
    contents = bundle / "Contents"
    for folder in [contents / "MacOS", contents / "Frameworks", contents / "Resources"]:
        folder.mkdir(parents=True, exist_ok=True)
    test_flags = ["-D", "LOCAL_UI_TEST", ROOT / "Tests" / "NativeUI.swift"] if testing else []
    run(COMMON + test_flags + ["-O", "-warnings-as-errors", CORE, *sorted(SOURCES.glob("*.swift")), *links(),
                  "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                  "-o", contents / "MacOS" / "TimeNote"])
    for name in ["GRDB", "KeyboardShortcuts"]:
        shutil.copy2(BUILD / ("lib" + name + ".dylib"), contents / "Frameworks")
    with (ROOT / "Resources" / "Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if testing:
        info["CFBundleIdentifier"] = "local.timenote.native.v1.test"
        info["CFBundleName"] = "时间便签测试"
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump(info, file)
    shutil.copy2(ROOT / "LICENSE", contents / "Resources" / "TimeNote-LICENSE.txt")
    shutil.copy2(GRDB / "LICENSE", contents / "Resources" / "GRDB-LICENSE.txt")
    shutil.copy2(KEYS / "license", contents / "Resources" / "KeyboardShortcuts-LICENSE.txt")
    shutil.copy2(GRDB / "GRDB" / "PrivacyInfo.xcprivacy", contents / "Resources")
    for path in (ROOT / "Resources").iterdir():
        if path.is_file() and path.name != "Info.plist":
            shutil.copy2(path, contents / "Resources")
    resources = contents / "Resources" / "KeyboardShortcuts.bundle"
    resources.mkdir(exist_ok=True)
    shutil.copytree(KEYS / "Sources" / "KeyboardShortcuts" / "Localization", resources, dirs_exist_ok=True)
    with (resources / "Info.plist").open("wb") as file:
        plistlib.dump({"CFBundleIdentifier": "local.timenote.KeyboardShortcuts", "CFBundleDevelopmentRegion": "en"}, file)
    for name in ["GRDB", "KeyboardShortcuts"]:
        run(["/usr/bin/codesign", "--force", "--sign", "-", contents / "Frameworks" / ("lib" + name + ".dylib")])
    # 文件提供程序会再次附加 Finder 元信息，紧接签名前清理生成包；不移除隔离属性。
    for attribute in ["com.apple.ResourceFork", "com.apple.FinderInfo"]:
        run(["/usr/bin/xattr", "-dr", attribute, bundle])
    # 递归遍历期间这两个包目录可能已被重新标记，最后单独清理后立即签名。
    for path in [resources, bundle]:
        attributes = subprocess.check_output(["/usr/bin/xattr", str(path)], text=True, timeout=10).splitlines()
        if "com.apple.FinderInfo" in attributes:
            run(["/usr/bin/xattr", "-d", "com.apple.FinderInfo", path])
    run(["/usr/bin/codesign", "--force", "--sign", "-", bundle])
    run(["/usr/bin/codesign", "--verify", "--deep", bundle])
    shutil.copytree(bundle, destination, dirs_exist_ok=True)
    run(["/usr/bin/codesign", "--verify", "--deep", destination])
    strict = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(destination)],
                            cwd=ROOT, env=ENV, text=True, capture_output=True, timeout=20, check=False)
    (BUILD / ("signature-test.txt" if testing else "signature.txt")).write_text(strict.stdout + strict.stderr)
    if strict.returncode:
        if "resource fork, Finder information" not in strict.stderr:
            raise RuntimeError("严格签名校验失败：" + strict.stderr)
        print("注意：普通签名有效；严格校验受目录自动附加的 Finder 信息影响，详见 signature.txt。", flush=True)
    print("本机应用已构建：", destination, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("step", choices=["deps", "test", "icon", "app", "ui-app", "all"])
    args = parser.parse_args()
    for folder in [BUILD, BUILD / "module-cache", BUILD / "tmp"]:
        folder.mkdir(parents=True, exist_ok=True)
    ensure_alias()
    ENV = dict(os.environ, TMPDIR=str(ALIAS / ".build-local" / "tmp"),
               CLANG_MODULE_CACHE_PATH=str(ALIAS / ".build-local" / "module-cache"))
    # 命令行工具的默认 SDK 把 @State 实现为外部宏但不包含其插件，缺少插件时编译失败；
    # 用 SDKROOT 指向仍以属性包装器实现 @State 的 SDK（如本机 MacOSX26.5.sdk）后运行本脚本。
    sdk = subprocess.check_output(["/usr/bin/xcrun", "--show-sdk-path"], text=True, timeout=10).strip()
    compiler = subprocess.check_output(["/usr/bin/xcrun", "--find", "swiftc"], text=True, timeout=10).strip()
    COMMON = [compiler, "-sdk", sdk, "-swift-version", "6", "-target", "arm64-apple-macosx14.0",
              "-file-prefix-map", f"{ROOT}=/timenote",
              "-debug-prefix-map", f"{ROOT}=/timenote",
              "-file-compilation-dir", "/timenote",
              "-module-cache-path", BUILD / "module-cache"]
    dependencies()
    if args.step in ["test", "all"]:
        checks()
    if args.step in ["icon", "all"]:
        icon()
    if args.step in ["app", "all"]:
        app()
    if args.step == "ui-app":
        app(testing=True)
