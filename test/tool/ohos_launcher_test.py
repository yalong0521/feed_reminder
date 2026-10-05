"""Host-side launcher safety tests; do not require Flutter or signing material."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


LAUNCHER = Path(__file__).resolve().parents[2] / "tool" / "ohos" / "run.py"
SPEC = importlib.util.spec_from_file_location("ohos_launcher", LAUNCHER)
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)


class LauncherTest(unittest.TestCase):
    def setUp(self):
        self.comspec = os.environ.get("COMSPEC")
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "project"
        self.config = self.root / "tool" / "ohos"
        self.workspace = self.root / "build" / "ohos_workspace"
        self.config.mkdir(parents=True)
        self.workspace.mkdir(parents=True)
        for key, value in {
            "ROOT": self.root, "CONFIG": self.config, "WORKSPACE": self.workspace,
        }.items():
            override = patch.object(launcher, key, value)
            override.start()
            self.addCleanup(override.stop)
        self.environment = patch.dict(os.environ, {}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def write(self, path, text="data"):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def basic_sources(self):
        self.write(self.root / "pubspec.yaml", "name: test_app\n# 奶点记\ndependencies:\n  flutter:\n    sdk: flutter\n")
        self.write(self.config / "dependencies.yaml", "  shared_preferences_ohos: any\n")
        self.write(self.config / "pubspec_overrides.yaml", "dependency_overrides: {}\n")
        self.write(self.root / "pubspec.lock", "main lock")
        self.write(self.root / "lib" / "main.dart", "// 记录奶量")

    def test_windows_prepare_copies_utf8_and_keeps_main_inputs(self):
        self.basic_sources()
        original = (self.root / "pubspec.yaml").read_bytes()
        with patch.object(launcher, "WINDOWS", True):
            launcher.prepare()
        generated = (self.workspace / "pubspec.yaml").read_text(encoding="utf-8")
        self.assertIn("# 奶点记", generated)
        self.assertEqual(generated.count("shared_preferences_ohos"), 1)
        self.assertEqual((self.root / "pubspec.yaml").read_bytes(), original)
        self.assertEqual((self.root / "pubspec.lock").read_text(), "main lock")
        self.assertEqual((self.workspace / "lib" / "main.dart").read_text(encoding="utf-8"), "// 记录奶量")

    def test_mirror_updates_sources_and_removes_only_stale_files(self):
        source = self.root / "lib"
        destination = self.workspace / "lib"
        self.write(source / "a.dart", "new")
        self.write(destination / "a.dart", "old")
        self.write(destination / "stale" / "old.dart")
        self.write(destination / "stale" / "build" / "cache")
        self.write(destination / "delete" / "old.dart")
        launcher.sync_directory(source, destination)
        self.assertEqual((destination / "a.dart").read_text(), "new")
        self.assertFalse((destination / "stale" / "old.dart").exists())
        self.assertTrue((destination / "stale" / "build" / "cache").exists())
        self.assertFalse((destination / "delete").exists())

    def test_native_caches_signing_and_local_config_are_preserved_not_copied(self):
        source = self.root / "ohos"
        destination = self.workspace / "ohos"
        protected = [
            "signing/key", "build-profile.local.json5", ".hvigor/cache", "oh_modules/cache",
            "entry/build/cache", "local.properties", ".git/config", ".dart_tool/cache",
        ]
        for relative in protected:
            self.write(source / relative, "source private value")
            self.write(destination / relative, "workspace private value")
        self.write(source / "entry" / "source.ets", "current")
        launcher.sync_directory(source, destination, native=True)
        for relative in protected:
            self.assertEqual((destination / relative).read_text(), "workspace private value")
        self.assertEqual((destination / "entry" / "source.ets").read_text(), "current")

    def test_preserved_cache_prevents_destructive_directory_to_file_replacement(self):
        source = self.root / "lib"
        destination = self.workspace / "lib"
        self.write(source / "changed", "now a file")
        cache = self.write(destination / "changed" / "build" / "cache")
        with self.assertRaisesRegex(RuntimeError, "protected cache"):
            launcher.sync_directory(source, destination)
        self.assertTrue(cache.exists())

    def test_node_modules_external_links_are_preserved_without_traversing(self):
        source = self.root / "ohos"
        destination = self.workspace / "ohos"
        self.write(source / "entry" / "source.ets", "current")
        protected = self.write(self.root.parent / "external_plugin" / "plugin.js", "external")
        dependencies = destination / "node_modules"
        dependencies.mkdir(parents=True)
        try:
            (dependencies / "flutter-hvigor-plugin").symlink_to(protected.parent, target_is_directory=True)
        except OSError as error:
            self.skipTest(f"Host does not permit symlinks: {error}")
        self.write(source / "node_modules" / "do_not_copy.js")
        launcher.sync_directory(source, destination, native=True)
        self.assertTrue((dependencies / "flutter-hvigor-plugin").is_symlink())
        self.assertEqual(protected.read_text(), "external")
        self.assertFalse((dependencies / "do_not_copy.js").exists())
        self.assertEqual((destination / "entry" / "source.ets").read_text(), "current")

    def test_mirror_handles_unprotected_type_changes(self):
        source = self.root / "lib"
        destination = self.workspace / "lib"
        self.write(source / "becomes_file", "file")
        self.write(destination / "becomes_file" / "old")
        self.write(source / "becomes_directory" / "new", "new")
        self.write(destination / "becomes_directory", "old")
        launcher.sync_directory(source, destination)
        self.assertEqual((destination / "becomes_file").read_text(), "file")
        self.assertEqual((destination / "becomes_directory" / "new").read_text(), "new")

    def test_outside_destination_is_rejected_before_deleting(self):
        outside = self.root.parent / "outside"
        protected = self.write(outside / "keep")
        source = self.root / "lib"
        source.mkdir()
        with self.assertRaisesRegex(RuntimeError, "outside the OH workspace"):
            launcher.sync_directory(source, outside)
        self.assertTrue(protected.exists())

    def test_relocated_workspace_is_rejected(self):
        with patch.object(launcher, "WORKSPACE", self.root.parent / "elsewhere"):
            with self.assertRaisesRegex(RuntimeError, "inside this project's build"):
                launcher.prepare()

    def test_symlink_cannot_redirect_stale_deletion_outside_workspace(self):
        outside = self.root.parent / "outside"
        protected = self.write(outside / "keep")
        source = self.root / "lib"
        source.mkdir()
        destination = self.workspace / "lib"
        destination.mkdir()
        try:
            (destination / "linked").symlink_to(outside, target_is_directory=True)
        except OSError as error:
            self.skipTest(f"Host does not permit symlinks: {error}")
        with self.assertRaisesRegex(RuntimeError, "outside the OH workspace"):
            launcher.sync_directory(source, destination)
        self.assertTrue(protected.exists())

    def test_explicit_profile_and_existing_workspace_lock_are_preserved(self):
        self.basic_sources()
        self.write(self.root / "ohos" / "build-profile.json5", "public profile")
        local = self.write(self.root / "ohos" / "build-profile.local.json5", "local profile")
        self.write(self.workspace / "pubspec.lock", "resolved OH lock")
        with patch.object(launcher, "WINDOWS", True):
            launcher.prepare()
        self.assertEqual((self.workspace / "ohos" / "build-profile.json5").read_bytes(), local.read_bytes())
        self.assertFalse((self.workspace / "ohos" / "build-profile.local.json5").exists())
        self.assertEqual((self.workspace / "pubspec.lock").read_text(), "resolved OH lock")

    def test_macos_keeps_rsync_exclusions(self):
        self.basic_sources()
        self.write(self.root / "ohos" / "entry" / "test.ets")
        with patch.object(launcher, "WINDOWS", False), patch.object(launcher.subprocess, "run") as run:
            launcher.prepare()
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(len(commands), 2)
        self.assertTrue(all(command[:3] == ["rsync", "-a", "--delete"] for command in commands))
        self.assertTrue(all("--exclude=node_modules" in command for command in commands))
        self.assertIn("--exclude=/signing/", commands[-1])
        self.assertIn("--exclude=/build-profile.local.json5", commands[-1])

    def test_environment_uses_platform_specific_flutter_java_and_node(self):
        sdk = self.root.parent / "Flutter OH"
        deveco = self.root.parent / "DevEco Studio"
        self.write(sdk / "bin" / "flutter.bat")
        self.write(sdk / "bin" / "flutter")
        self.write(sdk / "bin" / "cache" / "flutter.version.json", json.dumps({"frameworkRevision": launcher.SDK_REVISION}))
        for windows in (True, False):
            with self.subTest(windows=windows), patch.object(launcher, "WINDOWS", windows), patch.dict(os.environ, {
                "FLUTTER_OH_ROOT": str(sdk), "DEVECO_STUDIO_HOME": str(deveco),
                "FLUTTER_STORAGE_BASE_URL": "https://flutter-ohos.example.invalid",
            }):
                flutter, environment = launcher.flutter_environment()
            self.assertEqual(flutter.name, "flutter.bat" if windows else "flutter")
            self.assertEqual(environment["JAVA_HOME"], str(deveco / "jbr" if windows else deveco / "jbr" / "Contents" / "Home"))
            node = deveco / "tools" / "node" if windows else deveco / "tools" / "node" / "bin"
            self.assertIn(str(node), environment["PATH"].split(os.pathsep))
            self.assertNotIn("FLUTTER_STORAGE_BASE_URL", environment)
            if windows:
                self.assertEqual(environment["OS"], "Windows_NT")
                self.assertEqual(environment["GIT_CONFIG_COUNT"], "1")
                self.assertEqual(environment["GIT_CONFIG_KEY_0"], "core.longpaths")
                self.assertEqual(environment["GIT_CONFIG_VALUE_0"], "true")
            else:
                self.assertNotIn("OS", environment)
                self.assertNotIn("GIT_CONFIG_COUNT", environment)

    @unittest.skipUnless(os.name == "nt", "Runs a Windows batch expansion regression")
    def test_windows_subprocess_enables_deveco_batch_delayed_expansion(self):
        sdk = self.root.parent / "Flutter OH"
        self.write(sdk / "bin" / "flutter.bat")
        self.write(sdk / "bin" / "cache" / "flutter.version.json", json.dumps({"frameworkRevision": launcher.SDK_REVISION}))
        batch = self.write(self.workspace / "deveco_environment_probe.bat", """@echo off
if "%OS%"=="Windows_NT" setlocal enabledelayedexpansion
set OHPM_FIRST_PARAM=--version
echo !OHPM_FIRST_PARAM!
""")
        with patch.dict(os.environ, {"FLUTTER_OH_ROOT": str(sdk)}):
            _, environment = launcher.flutter_environment()
            self.assertNotIn("OS", os.environ)
        result = subprocess.run([self.comspec, "/d", "/c", str(batch)], env=environment, capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.strip(), "--version")

    def test_windows_longpaths_appends_without_overwriting_caller_git_config(self):
        sdk = self.root.parent / "Flutter OH"
        self.write(sdk / "bin" / "flutter.bat")
        self.write(sdk / "bin" / "cache" / "flutter.version.json", json.dumps({"frameworkRevision": launcher.SDK_REVISION}))
        inherited = {
            "FLUTTER_OH_ROOT": str(sdk), "GIT_CONFIG_COUNT": "2",
            "GIT_CONFIG_KEY_0": "core.autocrlf", "GIT_CONFIG_VALUE_0": "false",
            "GIT_CONFIG_KEY_1": "core.longpaths", "GIT_CONFIG_VALUE_1": "false",
        }
        with patch.object(launcher, "WINDOWS", True), patch.dict(os.environ, inherited):
            _, environment = launcher.flutter_environment()
            self.assertEqual(os.environ["GIT_CONFIG_COUNT"], "2")
            self.assertNotIn("GIT_CONFIG_KEY_2", os.environ)
        for key, value in inherited.items():
            if key != "GIT_CONFIG_COUNT":
                self.assertEqual(environment[key], value)
        self.assertEqual(environment["GIT_CONFIG_COUNT"], "3")
        self.assertEqual(environment["GIT_CONFIG_KEY_2"], "core.longpaths")
        self.assertEqual(environment["GIT_CONFIG_VALUE_2"], "true")

    def test_lock_rejects_concurrent_process_and_releases_after_exception(self):
        child = """import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('launcher', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.ROOT = pathlib.Path(sys.argv[2])
module.WORKSPACE = module.ROOT / 'build' / 'ohos_workspace'
try:
    with module.workspace_lock():
        print('acquired')
except RuntimeError:
    print('locked')
"""
        with self.assertRaisesRegex(ValueError, "test release"):
            with launcher.workspace_lock():
                result = subprocess.run([sys.executable, "-c", child, str(LAUNCHER), str(self.root)], capture_output=True, text=True, check=True)
                self.assertEqual(result.stdout.strip(), "locked")
                raise ValueError("test release")
        result = subprocess.run([sys.executable, "-c", child, str(LAUNCHER), str(self.root)], capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.strip(), "acquired")


if __name__ == "__main__":
    unittest.main()
