# 奶点记

一个离线使用的 Flutter 喂奶记录与提醒应用。日光手账以暖纸底色、陶土色和大号衬线数字呈现倒计时，提供协调的深色外观；横屏使用手账侧栏，竖屏使用底部导航，记录与补记集中在计时页下方。同时适配小屏、大字体和平板。记录与设置保存在本机，无需账户。

## 使用方式

- **记录喂奶**：从首页滑块左侧向右滑到底并松开，才会保存。点击、短滑或取消手势不会生成记录。保存成功后可在原位撤销，操作窗口为 6 秒；保存失败可重新滑动重试。
- **查看与补记**：记录页按日期展示时间和相邻喂奶间隔，支持补记及确认删除。倒计时始终以最新一条记录为准，补记更早的时间不会重置当前计时；删除全部记录后清空计时。历史不再按条数自动删减，列表按需创建可见条目。
- **调整提醒**：设置喂奶间隔（1–1440 分钟）、夜间静音时段、声音及循环播放，可单独试听提醒音。
- **选择外观**：在「设置 → 屏幕与外观」选择跟随系统、浅色或深色，默认跟随系统，重启后保留选择。Android 手势导航区域透明，页面背景延伸至小白条下方；手势条随主题调整对比色，操作控件保留安全距离。外观与夜间静音分别设置。
- **固定放置**：计时首页有记录时保持屏幕常亮，切页或进入后台会释放。开启防烧屏保护后，闲置约 30 秒进入深色移动时钟；轻触或首次按键仅唤醒。到点提醒会自动退出待机，之后约 30 秒无操作可再次进入，并显示「已超时」和超时时长。声音仍按原设置播放，停止本次提醒后也可待机；待机不改变手机的系统亮度。

支持键盘和读屏操作。键盘使用右方向键逐步推进记录滑块，再按回车确认；读屏使用滑块的逐步调整动作。滑块具有轻微按压缩放和跟随进度的暖色渐变，系统减少动态效果时关闭额外缩放与回弹。系统高对比模式下，倒计时使用更厚的字形与更清晰的细节。数字下方的刻度表示本轮剩余时间比例，到点变暗、记录后重新点亮；时间、刻度和下一次提示保持成组居中。

## 提醒行为与限制

前台显示倒计时，并按设置播放提醒音；循环音频仅在应用前台播放。停止本次提醒的状态会保留到重启后。后台通过系统安排下一次通知，实际投递受设备权限和省电策略影响。

误操作新增记录后撤销，会恢复旧周期已保存的停止提醒状态。循环声音遇到播放错误时会在前台重试，单次声音正常播完不会自动重播；用户明确停止后，切回前台也不会擅自重新播放。

Android 未授予精确闹钟权限时，会使用系统允许的不精确通知，可在设置页打开通知和准时提醒权限。夜间静音保留应用内视觉提示、关闭前台声音；预定时间位于静音时段时不安排系统通知。夜间开始与结束相同表示不进入静音时段。不精确通知可能因系统延迟跨入静音时段，后台投递时无法再次判断夜间窗口。

Web 和 Windows 支持记录与前台计时，不提供系统定时通知。发布前应在目标真机上验证后台省电限制、长时间锁屏提醒和 iOS 行为。

## 开发与运行

原生鸿蒙使用独立的 Flutter-OH 工具链，构建、签名和提醒能力说明见 [鸿蒙开发与验证](tool/ohos/README.md)。

使用 Flutter 3.47.4（Dart 3.13.3）和 JDK 17。当前 Android Gradle 8.14 与 Java 25 不兼容。使用 FVM 时，可在项目根目录执行：

```powershell
fvm use 3.47.4
fvm flutter config --jdk-dir="你的 JDK 17 安装目录"
fvm flutter pub get
fvm flutter run
```

正式入口为 `lib/main.dart`。IDE 和命令行应使用同一套 Flutter SDK。`flutter config --jdk-dir` 是用户级设置，会影响本机其他 Flutter 项目。

Apple 工程最低支持 iOS 15、macOS 12，与当前 Flutter SDK 要求一致。
iOS / macOS 已接入 Flutter 的 Swift Package Manager；尚未支持它的通知插件
继续通过 CocoaPods 集成。首次构建请使用 `fvm flutter build ios --simulator`
或 `fvm flutter build macos`，生成插件配置并安装依赖后再从 Xcode 打开对应
`Runner.xcworkspace`。生成的插件包位于 `ephemeral` 目录，无需提交。

Windows 本机测试需要 Visual Studio 的 C++ 工具链：项目将 `win32` 构建钩子配置为本地编译。Android、iOS 和 Web 构建不执行这段 Windows 编译。

## 测试与打包

```powershell
fvm flutter analyze
fvm flutter test
fvm flutter test integration_test/app_test.dart -d <Android设备ID>
fvm flutter build apk --release
```

单元和组件测试覆盖数据恢复、存储失败、计时与静音边界、设置持久化、操作防重复、可访问性和响应式布局。Android 集成测试使用隔离的内存记录，并验证实际界面操作、通知调度及音频启停。

`integration_test/storage_test.dart` 另外验证真实原生存储，使用独立键前缀，覆盖 240 条记录、设置重新读取和旧数据迁移。`integration_test/notification_delivery_test.dart` 仅允许 Android 模拟器运行，要求通知和精确闹钟权限均已授予，验证系统通知实际投递与取消；它会清理该测试应用的通知，不用于已有用户数据的设备。它不覆盖后台省电或重启恢复。

APK 输出为 `build/app/outputs/flutter-apk/app-release.apk`。当前 release 构建使用 debug 签名；正式发布前需在 `android/app/build.gradle.kts` 配置自己的签名。

## 应用标识

Android、iOS、macOS、鸿蒙和 Linux 的主应用标识统一为 `com.weiyalong.naidianji`，
iOS / macOS 测试目标使用 `com.weiyalong.naidianji.RunnerTests`。
正式签名和商店登记需要与各平台的这个标识匹配。

Android 的 Kotlin 包和 namespace 同步使用该标识；Dart 包名 `feed_reminder`
以及内部 MethodChannel 名称不属于安装标识，保持原有值。
Windows 当前是普通 EXE 工程，尚未配置 MSIX 商店身份；Web 使用站点地址识别，
不将移动端包名写入 Web manifest。

从旧示例标识切换后，系统会视为新的应用，旧标识下的本地记录、设置和授权不会自动迁移。
鸿蒙原本已使用此标识，不涉及这次标识迁移。

## 目录职责

- `lib/main.dart`、`lib/app.dart`：启动、依赖装配、主题和页面导航。
- `lib/screens`、`lib/widgets`：自适应页面、等宽倒计时数字与共用交互组件。
- `lib/theme`：明暗主题、字体及 Cupertino 控件样式。
- `lib/providers`：计时状态、设置及提醒协调，支持注入时钟。
- `lib/repositories`、`lib/models`：记录模型、排序及相邻喂奶间隔。
- `lib/services`：本地存储、音频播放及系统通知。
- `test`、`integration_test`：单元、组件和设备集成测试。

## 界面资源与许可

界面以衬线排版、暖纸表面、开放式分组和细分隔线建立层级；不依赖玻璃着色器。倒计时使用 Tinos 等宽数字，中文标题使用 Noto Serif SC 常用字子集，正文使用 Inter，并以随包中文字体补齐汉字。倒计时不会每秒主动读屏播报，滑动操作保留触摸、键盘和读屏等价交互。

删除确认与错误提示使用同一套纸色弹窗和按压按钮，随明暗主题变化。删除前单独显示记录日期与时间，点击弹窗外空白、取消、系统返回及 Escape 均只会关闭弹窗，不会删除记录；短横屏、大字体及键盘遮挡时可滚动查看内容与操作。

随包字体均使用 SIL Open Font License 1.1，来源、子集说明及许可见 [assets/fonts/README.md](assets/fonts/README.md)。字体和声音随应用打包，无需联网加载。
