#!/usr/bin/env python3
"""Run Flutter-OH against an isolated copy of the current project sources."""

import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "tool" / "ohos"
WORKSPACE = ROOT / "build" / "ohos_workspace"
SDK_REVISION = "adaf911c35c9136a7d18fc424d714c9ec7724e60"
HELP = """Usage: tool/ohos.sh <prepare|analyze|test|build hap|run|doctor|devices|pub get> [options]

All Flutter commands run inside build/ohos_workspace. Current lib/, assets/,
test/, integration_test/ and ohos/ sources are copied there before each command.
Edit the original sources; generated workspace edits are overwritten.

Examples:
  tool/ohos.sh prepare
  tool/ohos.sh analyze
  tool/ohos.sh test
  tool/ohos.sh build hap --debug --no-codesign
  tool/ohos.sh run -d <device-id>

Environment:
  FLUTTER_OH_ROOT      Defaults to ~/Development/flutter-oh
  DEVECO_STUDIO_HOME   Defaults to /Applications/DevEco-Studio.app/Contents
  OHOS_BUILD_PROFILE  Optional local signing build-profile.json5

The main pubspec.yaml, pubspec.lock and .dart_tool are never changed. The
optional tool/ohos/pubspec.lock seeds a fresh OH workspace after validation.
"""


def write_if_changed(path, content):
    if not path.exists() or path.read_bytes() != content:
        path.write_bytes(content)


def prepare():
    profile_override = os.environ.get("OHOS_BUILD_PROFILE")
    profile = (
        Path(profile_override).expanduser()
        if profile_override
        else ROOT / "ohos" / "build-profile.local.json5"
    )
    if profile_override and not profile.is_absolute():
        raise RuntimeError("OHOS_BUILD_PROFILE must be an absolute path")
    if profile_override and not profile.is_file():
        raise RuntimeError(f"OHOS_BUILD_PROFILE does not exist: {profile}")
    pubspec = (ROOT / "pubspec.yaml").read_text()
    if len(re.findall(r"^dependencies:\s*$", pubspec, re.MULTILINE)) != 1:
        raise RuntimeError("Expected one top-level dependencies section")
    additional = (CONFIG / "dependencies.yaml").read_text()
    pubspec = re.sub(
        r"^dependencies:\s*$",
        lambda _: "dependencies:\n" + additional,
        pubspec,
        count=1,
        flags=re.MULTILINE,
    )
    write_if_changed(WORKSPACE / "pubspec.yaml", pubspec.encode())
    write_if_changed(
        WORKSPACE / "pubspec_overrides.yaml",
        (CONFIG / "pubspec_overrides.yaml").read_bytes(),
    )
    for name in ("analysis_options.yaml", ".metadata"):
        source = ROOT / name
        if source.exists():
            write_if_changed(WORKSPACE / name, source.read_bytes())
    lockfile = WORKSPACE / "pubspec.lock"
    if not lockfile.exists():
        seed = CONFIG / "pubspec.lock"
        if not seed.exists():
            seed = ROOT / "pubspec.lock"
        if seed.exists():
            shutil.copy2(seed, lockfile)
    for name in ("lib", "assets", "test", "integration_test", "ohos"):
        source = ROOT / name
        if not source.is_dir():
            continue
        destination = WORKSPACE / name
        destination.mkdir(exist_ok=True)
        # Preserve native dependency/build caches while refreshing edited and
        # deleted sources. Excluding the root build directory prevents recursion.
        native_excludes = (
            ["--exclude=/signing/", "--exclude=/build-profile.local.json5"]
            if name == "ohos"
            else []
        )
        subprocess.run(
            [
                "rsync",
                "-a",
                "--delete",
                "--exclude=.git",
                "--exclude=.dart_tool",
                "--exclude=build",
                "--exclude=.hvigor",
                "--exclude=oh_modules",
                "--exclude=local.properties",
                "--exclude=.DS_Store",
                *native_excludes,
                str(source) + "/",
                str(destination) + "/",
            ],
            check=True,
        )
    if profile.is_file():
        write_if_changed(
            WORKSPACE / "ohos" / "build-profile.json5", profile.read_bytes()
        )


def flutter_environment():
    sdk = Path(
        os.environ.get("FLUTTER_OH_ROOT", "~/Development/flutter-oh")
    ).expanduser()
    deveco = Path(
        os.environ.get(
            "DEVECO_STUDIO_HOME", "/Applications/DevEco-Studio.app/Contents"
        )
    ).expanduser()
    flutter = sdk / "bin" / "flutter"
    if not flutter.is_file():
        raise RuntimeError(f"Flutter-OH not found: {flutter}; set FLUTTER_OH_ROOT")
    environment = os.environ.copy()
    storage_host = (
        urlparse(environment.get("FLUTTER_STORAGE_BASE_URL", "")).hostname or ""
    )
    if "flutter-ohos" in storage_host:
        # The OH mirror only contains OH artifacts; applying it to Flutter's
        # general artifact downloads causes missing engine_stamp responses.
        environment.pop("FLUTTER_STORAGE_BASE_URL", None)
    environment.update(
        {
            "DEVECO_SDK_HOME": str(deveco / "sdk"),
            "NODE_HOME": str(deveco / "tools" / "node"),
            "JAVA_HOME": str(deveco / "jbr" / "Contents" / "Home"),
        }
    )
    binary_directories = [
        sdk / "bin",
        deveco / "tools" / "node" / "bin",
        deveco / "tools" / "ohpm" / "bin",
        deveco / "tools" / "hvigor" / "bin",
        deveco / "sdk" / "default" / "openharmony" / "toolchains",
    ]
    environment["PATH"] = os.pathsep.join(
        [str(path) for path in binary_directories] + [environment.get("PATH", "")]
    )
    version_file = sdk / "bin" / "cache" / "flutter.version.json"
    if not version_file.is_file():
        subprocess.run([str(flutter), "--version"], env=environment, check=True)
    if not version_file.is_file():
        raise RuntimeError(f"Flutter SDK version metadata is missing: {version_file}")
    version = json.loads(version_file.read_text())
    if version.get("frameworkRevision") != SDK_REVISION:
        raise RuntimeError(
            "Expected Flutter-OH 3.41.10-ohos-1.0.1 "
            f"({SDK_REVISION}), found {version.get('frameworkVersion')} at {sdk}"
        )
    return flutter, environment


def main():
    arguments = sys.argv[1:]
    if not arguments or arguments[0] in ("-h", "--help", "help"):
        print(HELP)
        return 0
    command = arguments[0]
    if command not in {
        "prepare", "analyze", "test", "build", "run", "doctor", "devices", "pub",
    }:
        raise RuntimeError(f"Unsupported command: {command}\n{HELP}")
    if command == "build" and arguments[1:2] != ["hap"]:
        raise RuntimeError("This launcher builds the OH hap target only")
    if command == "pub" and arguments[1:2] != ["get"]:
        raise RuntimeError("Use pub get; dependency changes belong in tool/ohos")
    WORKSPACE.parent.mkdir(exist_ok=True)
    # Keep pub resolution, source synchronization and builds in the same
    # workspace serialized. Normal Flutter commands use a different directory.
    with (WORKSPACE.parent / ".ohos_workspace.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError(
                "Another OH command is using build/ohos_workspace"
            ) from None
        WORKSPACE.mkdir(exist_ok=True)
        prepare()
        print(f"HarmonyOS workspace: {WORKSPACE}", flush=True)
        if command == "prepare":
            return 0
        flutter, environment = flutter_environment()
        return subprocess.call(
            [str(flutter), *arguments], cwd=WORKSPACE, env=environment
        )


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"ohos: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
