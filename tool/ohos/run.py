#!/usr/bin/env python3
"""Run Flutter-OH against an isolated copy of the current project sources."""

from contextlib import contextmanager
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
WINDOWS = os.name == "nt"
SDK_REVISION = "adaf911c35c9136a7d18fc424d714c9ec7724e60"
HELP = """Usage: tool/ohos.sh <prepare|analyze|test|build hap|run|doctor|devices|pub get> [options]

All Flutter commands run inside build/ohos_workspace. Current lib/, assets/,
test/, integration_test/ and ohos/ sources are copied there before each command.
Edit the original sources; generated workspace edits are overwritten.

Examples:
  python tool/ohos/run.py prepare                    (Windows/PowerShell)
  python tool/ohos/run.py build hap --release        (Windows/PowerShell)
  tool/ohos.sh prepare
  tool/ohos.sh analyze
  tool/ohos.sh test
  tool/ohos.sh build hap --debug --no-codesign
  tool/ohos.sh run -d <device-id>

Environment:
  FLUTTER_OH_ROOT      Defaults to ~/Development/flutter-oh
  DEVECO_STUDIO_HOME   Defaults to the standard DevEco install location
  OHOS_BUILD_PROFILE  Optional local signing build-profile.json5

The main pubspec.yaml, pubspec.lock and .dart_tool are never changed. The
optional tool/ohos/pubspec.lock seeds a fresh OH workspace after validation.
"""


def write_if_changed(path, content):
    verify_destination(path)
    if not path.exists() or path.read_bytes() != content:
        path.write_bytes(content)


def verify_workspace():
    """Do not follow a relocated build/workspace directory during synchronization."""
    expected = ROOT.resolve() / "build" / "ohos_workspace"
    if WORKSPACE.resolve() != expected:
        raise RuntimeError("The OH workspace must stay inside this project's build directory")


def verify_destination(path):
    verify_workspace()
    resolved = path.resolve()
    if resolved != WORKSPACE.resolve() and WORKSPACE.resolve() not in resolved.parents:
        raise RuntimeError(f"Refusing to modify a path outside the OH workspace: {path}")
    if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
        raise RuntimeError(f"Refusing to synchronize through a linked path: {path}")


def excluded_path(relative, native):
    excluded = {".git", ".dart_tool", "build", ".hvigor", "oh_modules", "node_modules", "local.properties", ".DS_Store"}
    return relative.name in excluded or (
        native and len(relative.parts) == 1
        and relative.name in {"signing", "build-profile.local.json5"}
    )


def remove_stale(path, relative, native):
    """Remove only stale source entries; retain excluded caches even in stale folders."""
    if excluded_path(relative, native):
        return
    verify_destination(path)
    if path.is_dir():
        for child in path.iterdir():
            remove_stale(child, relative / child.name, native)
        if not any(path.iterdir()):
            path.rmdir()
    elif path.exists():
        path.unlink()


def sync_directory(source, destination, native=False, relative=Path()):
    """Windows equivalent of rsync --delete, with protected local files/caches."""
    if source.is_symlink() or (hasattr(source, "is_junction") and source.is_junction()):
        raise RuntimeError(f"Linked source directories/files are not supported: {source}")
    verify_destination(destination)
    if not destination.is_dir():
        if destination.exists():
            destination.unlink()
        destination.mkdir()
    source_entries = {
        child.name: child for child in source.iterdir()
        if not excluded_path(relative / child.name, native)
    }
    for child in destination.iterdir():
        child_relative = relative / child.name
        if child.name not in source_entries:
            remove_stale(child, child_relative, native)
    for name, origin in source_entries.items():
        target = destination / name
        child_relative = relative / name
        if origin.is_symlink() or (hasattr(origin, "is_junction") and origin.is_junction()):
            raise RuntimeError(f"Linked source directories/files are not supported: {origin}")
        verify_destination(target)
        if origin.is_dir():
            sync_directory(origin, target, native, child_relative)
        else:
            if target.is_dir():
                remove_stale(target, child_relative, native)
                if target.exists():
                    raise RuntimeError(f"A protected cache prevents replacing this directory: {target}")
            if not target.exists() or origin.read_bytes() != target.read_bytes():
                shutil.copy2(origin, target)


@contextmanager
def workspace_lock():
    verify_workspace()
    lock_path = WORKSPACE.parent / ".ohos_workspace.lock"
    if lock_path.resolve() != ROOT.resolve() / "build" / ".ohos_workspace.lock":
        raise RuntimeError("The OH workspace lock must stay inside this project's build directory")
    # Opening in append mode avoids truncating the byte another process has locked.
    with lock_path.open("a+b") as lock:
        if WINDOWS:
            import msvcrt

            lock.seek(0, os.SEEK_END)
            if lock.tell() == 0:
                lock.write(b"\0")
                lock.flush()
            lock.seek(0)
            try:
                msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError:
                raise RuntimeError("Another OH command is using build/ohos_workspace") from None
        else:
            import fcntl

            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError("Another OH command is using build/ohos_workspace") from None
        try:
            yield
        finally:
            if WINDOWS:
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(lock, fcntl.LOCK_UN)


def prepare():
    verify_workspace()
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
    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8-sig")
    if len(re.findall(r"^dependencies:\s*$", pubspec, re.MULTILINE)) != 1:
        raise RuntimeError("Expected one top-level dependencies section")
    additional = (CONFIG / "dependencies.yaml").read_text(encoding="utf-8-sig")
    pubspec = re.sub(
        r"^dependencies:\s*$",
        lambda _: "dependencies:\n" + additional,
        pubspec,
        count=1,
        flags=re.MULTILINE,
    )
    write_if_changed(WORKSPACE / "pubspec.yaml", pubspec.encode("utf-8"))
    write_if_changed(
        WORKSPACE / "pubspec_overrides.yaml",
        (CONFIG / "pubspec_overrides.yaml").read_bytes(),
    )
    for name in ("analysis_options.yaml", ".metadata"):
        source = ROOT / name
        if source.exists():
            write_if_changed(WORKSPACE / name, source.read_bytes())
    lockfile = WORKSPACE / "pubspec.lock"
    verify_destination(lockfile)
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
        verify_destination(destination)
        if WINDOWS:
            sync_directory(source, destination, native=name == "ohos")
            continue
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
                "--exclude=node_modules",
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
    default_deveco = (
        str(Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Huawei" / "DevEco Studio")
        if WINDOWS else "/Applications/DevEco-Studio.app/Contents"
    )
    deveco = Path(
        os.environ.get(
            "DEVECO_STUDIO_HOME", default_deveco
        )
    ).expanduser()
    flutter = sdk / "bin" / ("flutter.bat" if WINDOWS else "flutter")
    if not flutter.is_file():
        raise RuntimeError(f"Flutter-OH not found: {flutter}; set FLUTTER_OH_ROOT")
    environment = os.environ.copy()
    # The pinned audio fork has one unavailable LFS object in its example app.
    # Runtime artifacts come from this SDK, not that example's icudtl.dat.
    environment.setdefault("GIT_LFS_SKIP_SMUDGE", "1")
    if WINDOWS:
        # Some embedded terminals omit OS. DevEco's ohpm.bat needs this exact
        # value to enable delayed expansion; otherwise its argument loop recurses.
        environment["OS"] = "Windows_NT"
        # Pub checks out entire plugin repositories, including deeply nested
        # Android examples. Scope long-path support to this command's children
        # and append to any caller-supplied Git configuration without replacing it.
        try:
            git_config_count = int(environment.get("GIT_CONFIG_COUNT", "0"))
            if git_config_count < 0:
                raise ValueError
        except ValueError:
            raise RuntimeError("GIT_CONFIG_COUNT must be a nonnegative integer") from None
        environment[f"GIT_CONFIG_KEY_{git_config_count}"] = "core.longpaths"
        environment[f"GIT_CONFIG_VALUE_{git_config_count}"] = "true"
        environment["GIT_CONFIG_COUNT"] = str(git_config_count + 1)
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
            "JAVA_HOME": str(deveco / "jbr" if WINDOWS else deveco / "jbr" / "Contents" / "Home"),
        }
    )
    binary_directories = [
        sdk / "bin",
        deveco / "tools" / "node" if WINDOWS else deveco / "tools" / "node" / "bin",
        Path(environment["JAVA_HOME"]) / "bin",
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
    version = json.loads(version_file.read_text(encoding="utf-8-sig"))
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
    verify_workspace()
    WORKSPACE.parent.mkdir(exist_ok=True)
    # Keep pub resolution, source synchronization and builds in the same
    # workspace serialized. Normal Flutter commands use a different directory.
    with workspace_lock():
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
