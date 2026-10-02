# 鸿蒙构建入口

使用独立的 Flutter-OH SDK：`3.41.10-ohos-1.0.1`，对应提交
`adaf911c35c9136a7d18fc424d714c9ec7724e60`、Dart `3.11.5`。
默认安装路径为 `~/Development/flutter-oh`；可通过 `FLUTTER_OH_ROOT` 修改。
DevEco 默认路径为 `/Applications/DevEco-Studio.app/Contents`，可通过
`DEVECO_STUDIO_HOME` 修改。

工程 compile/target 为 API 26，最低运行 HarmonyOS 5.0.5 / API 17，来自所选
Flutter-OH 引擎发布说明。最低版本声明仍需目标真机验证。

尚未安装专用 SDK 的机器可使用以下固定版本（不要覆盖已有 SDK 目录）：

```sh
git clone --depth 1 --branch 3.41.10-ohos-1.0.1 \
  https://gitcode.com/CPF-Flutter/flutter_flutter.git ~/Development/flutter-oh
```

在项目根目录执行：

```sh
tool/ohos.sh analyze
tool/ohos.sh test
tool/ohos.sh build hap --debug --no-codesign
tool/ohos.sh build hap --release --no-codesign
tool/ohos.sh devices
tool/ohos.sh run -d <device-id>
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
也需核对应用标识、证书和原安装包一致，避免触发签名不一致而被迫卸载。
`--no-codesign` 产物仅用于编译验证，不能视为已完成真机安装验证。

配置完成后执行 `tool/ohos.sh run --release -d <device-id>` 可构建并安装。
手机需保持解锁；系统锁屏会阻止启动应用。自动调试签名绑定 Profile 中的设备，
即使使用 Release 编译模式也仍是调试签名，正式上架需另行配置发布签名。

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
| 屏幕常亮         | `wakelock_plus` 1.4.0、对应 interface，`7009f270c6bb1bb4aaf373e226a873a126f9b9f4`                     | 此版本已将 OH 原生实现合并至主包；专用 interface 对齐 OH 的 `isEnabled` 返回格式。                                                |

旧版 `wakelock_plus_ohos` 是独立包，但其 Windows/Linux 依赖范围与本项目当前
`wakelock_plus` 冲突，因此这里选择较新的合并版本。音频 fork 的其他平台插件
及 `path_provider` 在覆盖文件中固定为 hosted 版本，避免其未指定 ref 的传递
Git 依赖进入构建。上述覆盖只影响鸿蒙副本。

源码来源：

- [shared_preferences_ohos](https://gitcode.com/CPF-Flutter/flutter_packages/tree/4a7a536bba8447c7d4eacde2fb1a2e0fbe2da044/packages/shared_preferences/shared_preferences_ohos)
- [path_provider_ohos](https://gitcode.com/CPF-Flutter/flutter_packages/tree/d4e49daa0acbd0bc419d58b1da27d64d44fab54b/packages/path_provider/path_provider_ohos)
- [audioplayers](https://gitcode.com/CPF-Flutter/flutter_audioplayers/tree/b853cdafdef1549be31b478a954f6d8b36d314e6/packages)
- [wakelock_plus](https://gitcode.com/CPF-Flutter/fluttertpc_wakelock_plus/tree/7009f270c6bb1bb4aaf373e226a873a126f9b9f4)

已将成功解析并验证的锁文件保存为 `tool/ohos/pubspec.lock`，供新的鸿蒙工作
副本使用。已有工作副本会保留自己的锁，
正常解析会根据当前源码依赖和覆盖文件更新；升级固定版本时应一起复核锁文件。

## 必须执行的设备验证

普通 Flutter 的测试在项目根目录执行。新增的
`test/harmony_notification_service_test.dart` 使用 Flutter-OH 的平台枚举检查
时间戳、声音参数、初始化和错误传播；在普通 Flutter 下会明确跳过。
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
