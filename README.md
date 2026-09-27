# 喂奶提醒

一个离线使用的 Flutter 喂奶记录与提醒应用。主要面向手机横屏放置使用：大号倒计时居中显示，记录与补记操作集中在底部；同时适配竖屏、小屏、大字体和平板。记录与设置保存在本机，无需账户。

## 使用方式

- **记录喂奶**：从首页滑块左侧向右滑到底并松开，才会保存。点击、短滑或取消手势不会生成记录。保存成功后可在原位撤销，操作窗口为 6 秒；保存失败可重新滑动重试。
- **查看与补记**：记录页按日期展示时间和相邻喂奶间隔，支持补记及确认删除。倒计时始终以最新一条记录为准，补记更早的时间不会重置当前计时；删除全部记录后清空计时。最多保留最近 100 条。
- **调整提醒**：设置喂奶间隔（1–1440 分钟）、夜间静音时段、声音及循环播放，可单独试听提醒音。
- **选择外观**：在「设置 → 屏幕与显示」选择跟随系统、浅色或深色，默认跟随系统，重启后保留选择。外观与夜间静音分别设置。
- **固定放置**：计时首页有记录时保持屏幕常亮，切页或进入后台会释放。开启防烧屏保护后，闲置约 30 秒进入深色移动时钟；轻触或首次按键仅唤醒，到点提醒会自动退出待机。待机不改变手机的系统亮度。

支持键盘和读屏操作。键盘使用右方向键逐步推进记录滑块，再按回车确认；读屏使用滑块的逐步调整动作。系统高对比模式下，玻璃效果会降级为实色显示。

## 提醒行为与限制

前台显示倒计时，并按设置播放提醒音；循环音频仅在应用前台播放。停止本次提醒的状态会保留到重启后。后台通过系统安排下一次通知，实际投递受设备权限和省电策略影响。

Android 未授予精确闹钟权限时，会使用系统允许的不精确通知，可在设置页打开通知和准时提醒权限。夜间静音保留应用内视觉提示、关闭前台声音；预定时间位于静音时段时不安排系统通知。夜间开始与结束相同表示不进入静音时段。不精确通知可能因系统延迟跨入静音时段，后台投递时无法再次判断夜间窗口。

Web 和 Windows 支持记录与前台计时，不提供系统定时通知。发布前应在目标真机上验证后台省电限制、长时间锁屏提醒和 iOS 行为。

## 开发与运行

使用 Flutter 3.47.2（Dart 3.13.2）和 JDK 17。当前 Android Gradle 8.14 与 Java 25 不兼容。使用 FVM 时，可在项目根目录执行：

```powershell
fvm use 3.47.2
fvm flutter config --jdk-dir="你的 JDK 17 安装目录"
fvm flutter pub get
fvm flutter run
```

正式入口为 `lib/main.dart`。IDE 和命令行应使用同一套 Flutter SDK。`flutter config --jdk-dir` 是用户级设置，会影响本机其他 Flutter 项目。

Windows 本机测试需要 Visual Studio 的 C++ 工具链：项目将 `win32` 构建钩子配置为本地编译。Android、iOS 和 Web 构建不执行这段 Windows 编译。

## 测试与打包

```powershell
fvm flutter analyze
fvm flutter test
fvm flutter test integration_test/app_test.dart -d <Android设备ID>
fvm flutter build apk --release
```

单元和组件测试覆盖数据恢复、存储失败、计时与静音边界、设置持久化、操作防重复、可访问性和响应式布局。Android 集成测试使用隔离的内存记录，并验证真实玻璃渲染、通知调度及音频启停。

APK 输出为 `build/app/outputs/flutter-apk/app-release.apk`。当前 release 构建使用 debug 签名；正式发布前需在 `android/app/build.gradle.kts` 配置自己的签名，并替换示例应用 ID `com.example.feed_reminder`。

## 目录职责

- `lib/main.dart`、`lib/app.dart`：启动、依赖装配、主题和页面导航。
- `lib/screens`、`lib/widgets`：自适应页面、玻璃数字与共用交互组件。
- `lib/theme`：明暗主题、字体及 Cupertino 控件样式。
- `lib/providers`：计时状态、设置及提醒协调，支持注入时钟。
- `lib/repositories`、`lib/models`：记录模型、排序及相邻喂奶间隔。
- `lib/services`：本地存储、音频播放及系统通知。
- `test`、`integration_test`：单元、组件和设备集成测试。
- `tool/generate_countdown_glyphs.py`：从随包字体生成倒计时字形路径。

## 界面资源与许可

玻璃表面使用 `liquid_glass_widgets` 的 standard 渲染模式，启动时跳过 premium 管线；必需 shader 加载失败时使用实色表面。倒计时由 Inter 等宽数字轮廓、字形裁切的背景模糊和静态高光组成，不运行持续材质动画，也不会每秒主动读屏播报。

随包字体 Inter 使用 SIL Open Font License 1.1，许可保留在 [assets/fonts/OFL-Inter.txt](assets/fonts/OFL-Inter.txt)。字形路径随代码提供，运行时不解析字体；更换字体后可按生成脚本中的说明重新生成。背景和声音资源也随应用打包，无需联网加载。
