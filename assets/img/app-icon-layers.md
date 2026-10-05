# 启动图标的前景与背景

2026-10-05。将现有奶瓶图标拆为独立前景和背景，供系统桌面合成与裁切。

- `app_icon_foreground.png`：透明奶瓶母图，使用内置 image_gen 从 `app_icon.png` 提取，保留奶瓶、时钟指针和陶瓷光影。
- `app_icon_background.svg`：满幅陶土色渐变，不预裁圆角；左上色 `#DD8C6A` 取自原图，经过 `#B65B3D` 过渡到现有品牌色 `#AD593C`。
- 原有 `app_icon.png` 继续作为不支持分层平台的图标资源。`launch_icon.png` 是开屏专用图片，未用于桌面前景层，也未修改。

## 平台导出

Windows 下运行 `./tool/export_launcher_foreground.ps1`，对已提取的前景做尺寸导出并同步背景：

- 鸿蒙：将方形前景母图等比缩放至完整的 1024×1024 透明画布，不额外添加内间距，不预裁圆角；背景直接同步现有 1024×1024 满幅 SVG。保留奶瓶、时钟指针、原有构图与背景渐变。`AppScope/resources/base/media/app_icon_layered.json` 关联两层，`app.json5` 与 `EntryAbility.icon` 共用该资源，避免桌面继续使用 Ability 的旧单层图标。
- Android 8.0 及以上：`mipmap-anydpi-v26/ic_launcher.xml` 分别引用背景渐变和奶瓶前景；透明 PNG 保留原始分辨率，使用 drawable 的 12% inset 留出裁切空间。旧版 Android 保留已有 mipmap PNG。
- iOS、macOS、Windows、Web 保留现有合成图标；启动页图标与字标保持原有配置。

Android 分层 XML 与鸿蒙 layered-image 资源单独维护；不要把合成的 `app_icon.png` 复制为前景。重新生成旧版平面图标后，应保留并检查这些分层配置。

鸿蒙上架规格依据：2026-10-05 华为 1.1.0（3）上架自检报告 `1313942118937670924`，Mate 80 / Mate X7（OS 6.1.1.120）均指出：“应用图标资源必须分为前景图和背景图两层，尺寸要求必须为1024px*1024px，资源不允许自行裁切圆角，不允许在资源内添加内间距”。导出遵循该要求，由系统处理最终轮廓和动态效果。

上架设计要求参考：[华为应用 UX 体验规范](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/ux-guidelines-general-0000001760708152#section1353515481417)，其中背景图不允许包含透明像素。资源格式参考：[OpenHarmony 分层图标](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/quick-start/layered-image.md)。Android 规格参考：[Android 自适应图标](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)，按 108dp 图层及中央 66dp 安全区域预留空间；不要将 Android 的 inset 应用于鸿蒙导出。

## 提取提示词

工具：内置 image_gen，透明背景开启；编辑目标：`assets/img/app_icon.png`。

> Use case: background-extraction. Edit target: the supplied existing 1024x1024 production launcher icon of 奶点记. Create its separate foreground layer by removing ONLY the full terracotta background and its cast shadow behind/below the bottle, replacing all space outside the bottle silhouette with genuinely transparent alpha. Preserve the exact existing ivory baby bottle, nipple, rounded collar, bottle body, embedded terracotta clock hands and center dot, the soft ceramic shading, highlights, texture, colors and proportions as faithfully as possible. Keep the existing composition, same square canvas, bottle centered at the same position and same original size (bottle approx x=260..760 y=120..890 on 1024 canvas). Do not redraw, reinterpret, simplify, rotate, crop, stretch, enlarge, change clock hands, change the shape, add text, add any backdrop, rounded square tile, white matte, edge halo, new drop shadow or checkerboard pixels. Smooth clean antialiased alpha at the silhouette. Output ONE transparent PNG foreground asset, no labels, no mockup or comparison.
