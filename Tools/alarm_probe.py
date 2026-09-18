"""独立提醒验证：只编译或执行无声检查，不启动发声试验。"""

import argparse
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Tools" / "AlarmProbe"
BUILD = ROOT / ".build-local" / "alarm-probe"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("step", choices=["test", "build"])
    args = parser.parse_args()
    for folder in [BUILD, BUILD / "module-cache", BUILD / "tmp"]:
        folder.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TMPDIR=str(BUILD / "tmp"),
               CLANG_MODULE_CACHE_PATH=str(BUILD / "module-cache"))
    sdk = subprocess.check_output(["/usr/bin/xcrun", "--show-sdk-path"], text=True, timeout=10).strip()
    compiler = subprocess.check_output(["/usr/bin/xcrun", "--find", "swiftc"], text=True, timeout=10).strip()
    sources = [SOURCES / name for name in ["ProbeSession.swift", "ProbeOptions.swift", "ProbeTone.swift", "ProbeLog.swift"]]
    sources.append(ROOT / "Tests" / "AlarmProbeChecks.swift" if args.step == "test" else SOURCES / "ProbeMain.swift")
    output = BUILD / ("alarm-probe-checks" if args.step == "test" else "alarm-probe")
    command = [compiler, "-sdk", sdk, "-swift-version", "6", "-target", "arm64-apple-macosx14.0",
               "-warnings-as-errors", "-Onone", "-module-cache-path", str(BUILD / "module-cache"),
               "-file-prefix-map", str(ROOT) + "=/timenote", "-debug-prefix-map", str(ROOT) + "=/timenote",
               "-file-compilation-dir", "/timenote", *map(str, sources), "-o", str(output)]
    subprocess.run(command, cwd=ROOT, env=env, check=True, timeout=120)
    if args.step == "test":
        subprocess.run([str(output)], cwd=ROOT, env=env, check=True, timeout=20)
    else:
        print("只完成编译，未运行：", output)
        print("真实声音试验需要另行确认参数和批准；无参数启动会拒绝。")


if __name__ == "__main__":
    main()
