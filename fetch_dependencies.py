"""下载官方固定版本；只解压普通文件，不执行上游脚本。"""

import hashlib
import io
import json
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LIBRARIES = [
    ("GRDB.swift", "7.11.1", "https://codeload.github.com/groue/GRDB.swift/tar.gz/refs/tags/v7.11.1"),
    ("KeyboardShortcuts", "3.0.1", "https://codeload.github.com/sindresorhus/KeyboardShortcuts/tar.gz/refs/tags/3.0.1"),
]


def main():
    destination = ROOT / "Vendor"
    pins_file = ROOT / "dependencies.json"
    previous = json.loads(pins_file.read_text()) if pins_file.exists() else []
    pins = []
    for name, version, url in LIBRARIES:
        folder = destination / (name + "-" + version)
        known = next((p for p in previous if p["name"] == name and p["version"] == version), None)
        if folder.exists() and known:
            pins.append(known)
            continue
        if folder.exists():
            raise RuntimeError("目录已存在，拒绝覆盖：" + str(folder))
        print("下载官方源码：", name, version, flush=True)
        data = urllib.request.urlopen(url, timeout=60).read()
        digest = hashlib.sha256(data).hexdigest()
        if known and known["sha256"] != digest:
            raise RuntimeError("下载校验值与锁定值不同，已停止")
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            members = []
            skipped = []
            for member in archive.getmembers():
                target = (destination / member.name).resolve()
                if destination.resolve() not in target.parents:
                    raise RuntimeError("不安全的压缩路径：" + member.name)
                if member.isfile() or member.isdir():
                    members.append(member)
                else:
                    skipped.append(member.name)
            archive.extractall(destination, members=members)
        pins.append({"name": name, "version": version, "url": url, "sha256": digest,
                     "skippedNonRegularEntries": skipped})
        pins_file.write_text(json.dumps(pins, indent=2) + "\n")
    print("源码下载完成；不安装工具、不运行上游脚本。", flush=True)


if __name__ == "__main__":
    main()
