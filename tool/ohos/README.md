# 鸿蒙构建入口

使用独立的 Flutter-OH SDK：`3.41.10-ohos-1.0.1`，对应提交
`adaf911c35c9136a7d18fc424d714c9ec7724e60`、Dart `3.11.5`。
默认安装路径为 `~/Development/flutter-oh`；可通过 `FLUTTER_OH_ROOT` 修改。
DevEco 在 macOS 默认路径为 `/Applications/DevEco-Studio.app/Contents`，在
Windows 默认路径为 `%ProgramFiles%\Huawei\DevEco Studio`（通常是
`C:\Program Files\Huawei\DevEco Studio`），可通过 `DEVECO_STUDIO_HOME` 修改。

工程 compile/target 为 API 26，最低运行 HarmonyOS 5.0.5 / API 17，来自所选
Flutter-OH 引擎发布说明。最低版本声明仍需目标真机验证。

尚未安装专用 SDK 的机器可使用以下固定版本（不要覆盖已有 SDK 目录）：

```sh
git clone --depth 1 --branch 3.41.10-ohos-1.0.1 \
  https://gitcode.com/CPF-Flutter/flutter_flutter.git ~/Development/flutter-oh
```

在项目根目录执行；macOS 使用 Bash 入口：

```sh
tool/ohos.sh analyze
tool/ohos.sh test
tool/ohos.sh build hap --debug --no-codesign
tool/ohos.sh build hap --release --no-codesign
tool/ohos.sh devices
```

Windows 在 PowerShell 中直接调用同一个 Python 入口，无需 Bash 或 rsync：

```powershell
python tool/ohos/run.py prepare
python tool/ohos/run.py pub get
python tool/ohos/run.py analyze
python tool/ohos/run.py test
python tool/ohos/run.py build hap --release --no-codesign
python tool/ohos/run.py devices
```

Windows 入口自动使用 `flutter.bat`、DevEco 的 `tools\node` 和 `jbr`；
并在子进程中补齐 `OS=Windows_NT`，避免部分嵌入式终端缺失此变量时
`ohpm.bat` 无法启用延迟变量展开、陷入参数解析递归。
源码同步和跨进程文件锁使用 Python/Windows API。它会保留签名、本机配置及
构建/依赖缓存，拒绝同步到工作副本之外的路径。依赖仓库包含路径较深的 Android
示例，入口通过子进程环境追加 `core.longpaths=true`，保留调用者已有的动态 Git
配置，不修改系统或全局 Git 配置。主机侧安全测试无需 Flutter、
手机或签名，可在项目根目录执行：

```sh
python -m unittest discover -s test/tool -p '*_test.py' -v
```

`tool/ohos.sh pub get` 会同步工作副本、解析依赖并生成 Flutter/Hvigor 插件配置。
`tool/ohos.sh prepare` 仅同步源码与配置，不补齐构建依赖；执行后不能保证 DevEco
工程已就绪。需要用 DevEco 配置签名或直接运行时，先执行 `tool/ohos.sh pub get`，
再打开 `build/ohos_workspace/ohos`。修改原项目后也按此步骤重新同步。
在 DevEco 中完成签名配置后，将生成的 `build-profile.json5` 保存到原项目已忽略的
`ohos/build-profile.local.json5`；之后每次运行会使用这个本机配置。也可以通过
`OHOS_BUILD_PROFILE=/绝对路径/build-profile.json5` 指定本机配置。
这些文件可能包含签名凭据，不应纳入版本控制；脚本不会寻找其他签名文件。
配置中的证书、密钥和 Profile 请使用绝对路径，以免工作副本的位置改变其含义。
首次安装前将这三份文件复制到已忽略的 `ohos/signing/`，并让本机配置引用这些
固定副本；使用 DevEco 加密口令时，还需复制密钥库同级的 `material/` 目录，
保持相对位置，整个签名目录只允许本机用户访问。DevEco 重新生成自动签名时
可能覆盖 `~/.ohos/config/` 中的材料；
覆盖更新必须保留原签名身份，不能只备份引用路径。申请能力后更新 Profile 时，
也需核对应用标识、证书和原安装包一致；签名不一致时停止安装并修正配置，
不能通过卸载旧版来继续覆盖更新。
`--no-codesign` 产物仅用于编译验证，不能视为已完成真机安装验证。

**已有真实记录的手机应将构建与安装分开。** 固定版本 Flutter-OH 的
`ohos_device.dart` 中，`installApp()` 在覆盖安装失败后会调用 `uninstallApp()`
卸载已安装的旧版，再尝试重新安装。因此不要对这类设备使用 `flutter run`、
`tool/ohos.sh run` 或 `python tool/ohos/run.py run`。

签名配置完成后，先构建已签名的 Release 包，再单独使用 `hdc install -r`
覆盖安装；macOS 构建命令为 `tool/ohos.sh build hap --release`，Windows 示例：

```powershell
python tool/ohos/run.py build hap --release
```

确认构建成功，并从本次输出中选取已签名的 Release HAP。以下路径和设备 ID
需替换为实际值；使用自定义 DevEco 安装目录时也需修改 `hdc.exe` 路径：

```powershell
$ohosHdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $ohosHdc -t '<device-id>' install -r '<已签名ReleaseHAP的绝对路径>'
```

检查安装输出确认成功后，才启动应用；覆盖失败立即停止，保留旧应用和数据，
不追加卸载命令。不能仅凭 `hdc` 进程退出码认定安装成功，还需检查设备返回的
安装结果。启动命令为：

```powershell
& $ohosHdc -t '<device-id>' shell aa start -a EntryAbility -b com.weiyalong.naidianji
```

仅在没有需要保留数据的独立测试设备上，才可使用
`tool/ohos.sh run --release -d <device-id>` 或对应 Python 入口的 `run` 命令。
手机需保持解锁；系统锁屏会阻止启动应用。自动调试签名绑定 Profile 中的设备，
即使使用 Release 编译模式也仍是调试签名，正式上架需另行配置发布签名。

### 本轮构建与安装状态

Windows 已配置上述 Flutter-OH 固定版本与 DevEco/API 26，完成主应用及并存
测试应用的已签名 Release HAP 构建。Flutter-OH 主机测试 485 项通过、0 跳过，
静态分析无问题；Python 构建入口测试 15 项通过。

原标识 `com.weiyalong.naidianji` 的 `hdc install -r` 返回 `9568332`（签名不匹配），
未执行卸载。按用户选择另建并单独签名的 `com.weiyalong.naidianji.dev` 已并存安装，
设备返回 `install bundle successfully`，商店版及其数据保留。两种标识的数据与授权
互相隔离，主应用标识保持不变。

并存测试产物为 `build/ohos_releases/naidianji-test-release.hap`，大小 25.6 MB，
包内 `debug=false` 且包含 AOT 产物 `libapp.so`；这是 Release 编译、绑定设备的
调试签名，不是商店发布签名。`aa start` 已成功，设备任务状态确认测试版位于前台，
进程持续运行；真实手机截图 `build/ohos_preview_launch.jpeg` 确认设置页正常渲染。

设备日志 `build/ohos_preview_launch.log` 显示 `publishReminder` 返回 `1700002` /
`reminder_limit_exceeded`（后台提醒额度受限）。应用已捕获原生错误，未造成闪退；
测试签名 Profile 的 `bundleName` 为 `com.weiyalong.naidianji.dev`、`profileType`
为 `debug`，`appServicesCapabilities` 为空，未包含代理提醒开放能力。原应用已获批的
能力不会自动继承到新标识，需要为测试身份配置对应能力后再验后台通知。错误码本身
不足以确认唯一原因，系统配额仍需核查，后台提醒尚未验收通过。卡片和系统文件操作
仍待真机专项验收；本轮未修改提醒算法或申请新账号、发布商店包。

## 启动画面

启动画面使用原生窗口，沿用应用图标及 `AppPalette` 的浅深背景色。
API 19+ 通过 `start_window.json` 显示底部“奶点记”字标，旧版保留
`startWindowIcon` / `startWindowBackground` 配置；API 17 的实际回退效果仍需真机验证。
字标沿用 `assets/img/launch-branding*.svg` 的设计，base/dark media 使用鸿蒙专用导出：
内禀尺寸 800 × 320、viewBox 200 × 80，副标题为 14。系统只缩小、不放大图片，
直接复制 200 × 80 母版会使高密度手机上的两行字过小。
图标尺寸与位置由系统控制，启动资源跟随系统外观，Flutter 加载后使用应用自身主题。
没有额外开屏页面或固定停留时间；检查完整启动效果时，应先结束应用进程再重新打开。

## 系统提醒能力

应用名称为“奶点记”，包名为 `com.weiyalong.naidianji`，配置在
`ohos/AppScope/app.json5`。签名必须关联开发者账号下该包名对应的 App ID。

手机、平板的后台代理提醒需要在 AppGallery Connect「项目设置 → 开放能力管理」
申请“代理提醒”，获批开启后重新生成 Profile。通知授权弹窗不能替代能力申请。
DevEco 26 也可在「项目结构 → 签名配置 → 开通开放能力」选择
`Agent-powered reminder` 提交申请，需要用途说明和附件；可复制
[本项目的申请说明](../../docs/harmony-reminder-application.md)。
工程已声明 `ohos.permission.PUBLISH_AGENT_REMINDER`，没有获批签名时不能将
成功构建等同于后台提醒可用。参考 [华为代理提醒指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-powered-reminder)。

- Dart 传递绝对毫秒时间戳，ArkTS 转为本地年月日时分秒，创建一次 Calendar
  代理提醒；向上取整到秒，避免提前投递和 UTC 字符串被当成本地时间。
- 每次替换先取消旧代理和可见通知；进程重启也能清理旧提醒，不依赖内存里的 ID。
- 前台仍由应用播放单次/循环音频，后台由系统投递。切后台停止前台音频并释放常亮，
  销毁引擎保留已安排的系统提醒。
- 有声通知走服务提醒槽；静音通知走默认低优先级、无声的内容资讯槽，默认仅
  进入通知中心。最终声音行为遵循用户的系统通知槽设置。
- `ringDuration: 0` 表示跟随通知槽，并不是强制静音。本实现不启用独立代理
  闹钟铃声或静音音频变通；后台使用系统通知音，前台保留随包提醒音。
- 夜间静音、停止本次提醒、补记和撤销继续沿用现有业务及持久化规则。
- 读取记录不会主动弹权限框。系统隐私门禁通过后，在前台请求通知授权；设置页的
  “系统通知权限”直接打开系统通知设置。API 26 起在原生设置关闭后同步当前提醒；API 17–25 在
  返回应用点击“完成”后同步，避免依赖半屏设置不一定触发的前台恢复事件。
  权限拒绝或代理能力不可用不阻止记录的读取、保存。

## 隐私声明托管

鸿蒙版使用华为标准化隐私声明托管，发布范围限定为中国大陆。在 AppGallery
Connect 启用托管、填写并发布声明后，须将该声明随应用版本提交审核。不能仅替换
一个网页链接，或仅凭本机安装成功，判断托管配置已经生效。

本轮本地政策版本更新为 2026-10-03，补充奶量、延后状态、桌面卡片摘要及用户主动备份/恢复/导出。
鸿蒙发布前需同步这些实际功能到 AppGallery Connect 托管声明；本次代码修改未发布托管声明。

正式版本的首次隐私弹窗由系统管理，鸿蒙路径不再弹出应用自有的首次隐私提示，
也不使用其他平台保存在本机的同意版本。业务启动依赖系统门禁，通知权限申请
须在门禁通过且应用回到前台后执行，不能主动重复调用系统同意弹窗来补一次提示。

设置页“隐私政策”通过独立的 `feed_reminder/privacy` 通道调用
`FeedReminderPrivacy`。原生使用 `@kit.AppGalleryKit` 的
`privacyManager.getAppPrivacyMgmtInfo()` 查询当前声明，选择
`PRIVACY_STATEMENT_LINK`，再通过 `UIAbilityContext.openLink()` 展示托管页面。
查询或打开失败只提示重试，不回退为自有隐私网页、本地政策或第二套同意弹窗，
避免与系统当前声明不一致。其他平台继续使用离线隐私政策与本地首次提示。

直接侧载的调试包不等同于商店分发包。验证系统托管弹窗时，须按
[华为隐私声明托管接入说明](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/store-privacy)
设置调试用 metadata，并遵循文档要求的测试条件；调试 metadata 只能用于隔离的
调试配置，不能误纳入正式源码配置或上架包。生成工作副本会被下一次同步覆盖，
调试后须重新从正式源码构建并检查实际打包配置。

托管声明下发、首次系统弹窗、拒绝后再次启动、设置页托管链接和失败重试均待
目标真机验证；Dart 测试与 HAP/APP 编译通过不能代替这些验证。托管适用范围与
审核要求见[华为隐私声明托管 FAQ](https://developer.huawei.com/consumer/cn/doc/app/agc-help-privacy-policy-faq-0000002342315628)。

## 操作触感

`AppHaptics` 统一控制选择、成功和警示反馈：奶量尺在手指拖动经过 10 mL 刻度时轻触，加减奶量及设置生效时提示，记录/补记/修改/撤销/删除/提醒处理完成后确认；操作失败或主动提交非法值时配合可见错误提示。取消、同值选择、普通导航、输入同步及松手后的惯性滚动不触发。反馈有节流，不延迟排队，也不参与业务保存的成功判定。

鸿蒙通过 `feed_reminder/haptics` 使用短预置效果和 `usage: 'touch'`，遵循系统触感设置。仅在设备明确不支持预置效果时降为 8/20/35 ms 单次反馈，平台异常不重试或改用提醒振动。`EntryAbility` 转发前后台状态，进入后台或引擎解绑时丢弃待触发效果，能力查询超过 70 ms 也直接丢弃当次反馈。`ohos.permission.VIBRATE` 为 normal / system_grant 权限，不需要用户授权弹窗。

参考：[VIBRATE 权限](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/security/AccessToken/permissions-for-all.md#ohospermissionvibrate)、[系统对 touch 振动开关的处理](https://github.com/openharmony/sensors_miscdevice/blob/3128a695dac2847a3f3d910917982e1677543e35/services/miscdevice_service/src/vibration_priority_manager.cpp#L935)。`test/native/haptics_native_test.cjs` 验证通道失败、降级、缓存、重叠及前后台取消；实际强度与手感仍取决于设备马达和系统设置。

## 构建隔离

脚本把当前源码（包含未提交修改）同步到 `build/ohos_workspace`，仅在那里
增加鸿蒙联邦依赖、应用 `pubspec_overrides.yaml` 并生成构建产物。普通 Flutter
继续使用根目录原有的 `pubspec.yaml`、`pubspec.lock` 和 `.dart_tool`。
SDK、Node、Java、ohpm、hvigor、hdc 的环境只注入当前子进程，不修改全局配置。
不要把 `FLUTTER_STORAGE_BASE_URL` 设置为鸿蒙引擎镜像；Flutter-OH 自带独立的
鸿蒙下载配置，通用 Flutter 产物仍有自己的下载地址。

源码只维护一份：修改原项目后重新执行入口。直接修改工作副本中的源码会在
下次同步时被覆盖。产物位于 `build/ohos_workspace/build/ohos/`。
相同项目的鸿蒙命令使用文件锁，避免同时解析依赖或覆盖构建中的源码。

## 依赖选择

所有 Git 依赖固定完整提交，避免构建时自动移动到上游分支的新代码。

| 能力             | 依赖与固定提交                                                                                        | 选择原因                                                                                                                          |
| ---------------- | ----------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| 本地记录、设置   | `shared_preferences_ohos` 2.5.4，`4a7a536bba8447c7d4eacde2fb1a2e0fbe2da044`                           | 附加联邦实现，保留普通 `shared_preferences`；支持 legacy `setValue/getAll`、写入 flush、失败返回。                                |
| 音频资产临时文件 | `path_provider_ohos` 2.2.17，`d4e49daa0acbd0bc419d58b1da27d64d44fab54b`                               | 附加联邦实现，提供 `AudioCache` 使用的临时目录。                                                                                  |
| 提醒声音         | `audioplayers` 6.5.1、`audioplayers_ohos`、对应 interface，`b853cdafdef1549be31b478a954f6d8b36d314e6` | 此版本 OH 原生 global init 不回传结果，配套 Dart 主包跳过该初始化；interface 含 OH AudioContext。需整体覆盖，不能只增加 OH 插件。 |
| 屏幕常亮         | `wakelock_plus` 1.6.1、对应 interface，`5d3040f140b8a7e445c5e7102e811ff08e496905`                     | 使用 Flutter 3.41 适配提交，原生实现与 Pigeon 接口成对更新；支持 `file_picker` 13 所需的 `win32` 6。                              |

旧版 `wakelock_plus_ohos` 是独立包，但其 Windows/Linux 依赖范围与本项目当前
`wakelock_plus` 冲突，因此这里选择较新的合并版本。音频 fork 的其他平台插件
及 `path_provider` 在覆盖文件中固定为 hosted 版本，避免其未指定 ref 的传递
Git 依赖进入构建。上述覆盖只影响鸿蒙副本。

固定的音频 fork 提交含一个无法从上游下载的 Git LFS 对象，位于
`packages/audioplayers/example/ohos/dta/icudtl.dat`。它只属于上游示例应用，
本工程使用 Flutter-OH SDK 提供的引擎运行时，不使用该示例文件。因此入口默认仅在
构建子进程中设置 `GIT_LFS_SKIP_SMUDGE=1`，让依赖源码可以完成检出；不会修改
全局 Git/LFS 配置。调用者显式设置此变量时保留其值。升级依赖时必须重新核对
是否出现实际构建所需的 LFS 文件，不能直接沿用这一假设。

源码来源：

- [shared_preferences_ohos](https://gitcode.com/CPF-Flutter/flutter_packages/tree/4a7a536bba8447c7d4eacde2fb1a2e0fbe2da044/packages/shared_preferences/shared_preferences_ohos)
- [path_provider_ohos](https://gitcode.com/CPF-Flutter/flutter_packages/tree/d4e49daa0acbd0bc419d58b1da27d64d44fab54b/packages/path_provider/path_provider_ohos)
- [audioplayers](https://gitcode.com/CPF-Flutter/flutter_audioplayers/tree/b853cdafdef1549be31b478a954f6d8b36d314e6/packages)
- [wakelock_plus](https://gitcode.com/CPF-Flutter/fluttertpc_wakelock_plus/tree/5d3040f140b8a7e445c5e7102e811ff08e496905)

已将成功解析并验证的锁文件保存为 `tool/ohos/pubspec.lock`，供新的鸿蒙工作
副本使用。已有工作副本会保留自己的锁，
正常解析会根据当前源码依赖和覆盖文件更新；升级固定版本时应一起复核锁文件。

## 必须执行的设备验证

### 桌面卡片与文件备份

`FeedReminderFormAbility` 提供三种 ArkTS 卡片，跟随系统浅深色。
按桌面宽×高，“喂养概览”4×2 展示完整概览，“最近一餐”2×2 展示最近一餐、
下次提醒及记录入口，“下次喂奶”2×1 展示下次提醒的日期与时间，整张点击进入计时页。
鸿蒙配置按行×列命名，分别为 `2*4`、`2*2`、`1*2`。三个独立页面显式选择
共享组件的布局，不依赖系统是否将 Want 尺寸参数注入 LocalStorage。
保留原 `FeedSummary` 卡片名称、入口与默认 `2*4` 尺寸，已添加的卡片继续使用原布局。
2×1 卡片按实际剩余高度布局时间或状态，紧凑版上下留白为 6vp，避免折叠屏
约 56vp 高的桌面单元裁切“已停止”和时间。已用原生 Previewer 验证正常与停止
状态在 48/56/64/72vp、浅深色以及 424×153px、440dpi 的 20 个组合；真机已有
卡片覆盖安装后正常时间完整显示。此项不代表系统大字体已验证。
完整概览展示最近一餐的时间与奶量、指定日期的汇总、下一次提醒绝对时间；停止本轮提醒
后明确显示已停止。0 mL 显示“未记录奶量”，不解释为实际未喝奶。点击摘要进入
计时页，“记录喂奶”进入应用内确认面板，原生卡片不会直接创建记录。

`feed_reminder/home_widget` 仅接收隐私门禁通过、记录加载及保存成功后的摘要。
App 独占摘要 Preferences，FormExtension 独占卡片实例 Preferences；两者通过
应用沙箱内原子替换的 JSON 投影交换数据，避免跨进程共享 Preferences。
卡片首次同步帧使用不含用户数据的占位内容，再读取最近完整摘要。快照和卡片刷新
失败不影响喂养记录保存；更新请求按顺序处理，失败后相同摘要仍可重试。

应用不运行时只会在系统允许的卡片生命周期回调中读取最近摘要，不运行后台秒级
倒计时。完整概览固定显示统计日期、更新时间及快照时区；小尺寸保留显示时间的
日期，更新时间可由无障碍说明读取，跨日后也不把旧汇总称为
“今日”。定点刷新由系统调度，不能视作实时性保证；前台恢复及业务变化后会发布
新的摘要。此投影不包含完整历史，卸载应用时由应用沙箱一起清除。

`feed_reminder/data_files` 通过 DocumentViewPicker 保存 JSON/CSV 或读取单个
JSON 备份，只访问用户选择的 URI，无额外广泛文件权限。导入上限 10 MiB，严格
UTF-8 解码；导出逐块写入、fsync 并关闭后才报告成功。CSV 在最终字节输出处补
UTF-8 BOM，避免 MethodChannel 的字符串解码移除 BOM 后影响中文识别。
文件选择取消返回空结果；读取、写入、编码、超限和权限错误交由应用提示。

新增 Dart 测试可用普通 Flutter 运行，但不能证明原生 ArkTS 编译或桌面渲染。
另可使用 Node 24 执行 `node --test test/native/home_widget_native_test.cjs`，
通过类型擦除加载实际非 UI ArkTS 控制流并注入内存平台替身。本轮 13 项通过，
覆盖更新竞争、失败后重试、移除卡片、紧凑卡片空态及停止状态、跨日跨年、
跨夏令时显示和启动入口；这不检查 ArkTS
语法约束、系统 API 可用性、HAP 打包或设备行为。
当前 Windows 环境已完成 API 26 的 ArkTS 编译及已签名 Release HAP 构建，
并存测试包已安装并成功启动，设备截图已验证设置页及 2×1、2×2 卡片渲染。后台代理提醒仍返回
额度受限错误，配额与能力状态需要继续确认；以下项目仍需单独验证：

- Debug HAP 构建，以及 API 17 与目标版本的卡片加载。
- 首次启动前添加卡片、隐私门禁、冷/暖启动、重复点按和取消记录确认。
- 多卡片更新/移除、编辑/删除/恢复记录、延后与停止提醒、浅深色、大字体。
- 跨日、时区变化、划掉进程、重启后日期标签与更新边界。
- 文件保存/取消/覆盖、中文 CSV、损坏 UTF-8、10 MiB 边界及写入失败后的重试。

API 依据：[FormExtensionAbility 生命周期](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/arkts-ui-widget-lifecycle-V5)、
[卡片尺寸配置](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-configuration.md#配置文件字段说明)、
[组件树共享 LocalStorage](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/ui/state-management/arkts-localstorage.md#概述)、
[DocumentViewPicker](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-file-picker)、
[Preferences 单进程限制](https://github.com/openharmony/interface_sdk-js/blob/master/api/@ohos.data.preferences.d.ts)。

普通 Flutter 的测试在项目根目录执行。新增的
`test/harmony_notification_service_test.dart` 使用 Flutter-OH 的平台枚举检查
时间戳、声音参数、初始化和错误传播；在普通 Flutter 下会明确跳过。
2026-10-06 发布前复核：Flutter-OH analyze 无问题，主机测试 581 项通过、0 跳过，
原生逻辑替身测试 28 项通过，隔离构建工具测试 15 项通过。修正了页面隐藏后异步
保存结果补发触感，以及系统触感能力首次查询失败后不能恢复的问题。这仍不是
手机上的原生通知投递或存储集成测试。
原生存储可以沿用有独立测试键空间的集成测试：

```sh
tool/ohos.sh test integration_test/storage_test.dart -d <device-id>
```

现有 `integration_test/notification_delivery_test.dart` 是 Android 专用，不能
用于证明鸿蒙实际投递。签名与代理能力开通后还需验证：通知拒绝后重新授权、
记录/补记/撤销后只保留一次提醒、夜间静音、前后台跨越截止时间、取消已投递
提醒、静音槽的默认和用户修改行为，以及划掉应用、强制停止、重启和时区变更。
系统支持冻结或普通退出不等于这些场景均已得到验证。

编译、Dart 测试不能覆盖原生插件行为。需要检查保存记录后强制退出重开、设置
持久化、WAV 单次和循环播放、快速开始/停止、停止后再次播放、返回前台恢复、
首页常亮与切页/后台释放。上游常亮插件捕获系统错误后只打印日志，因此尤其
需要通过屏幕实际状态确认。后台提醒与通知权限由项目自己的鸿蒙通知实现验证。
