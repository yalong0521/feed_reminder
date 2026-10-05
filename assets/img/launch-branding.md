# 奶点记启动页资产

- 鸿蒙与 Android 8.0+ 桌面图标采用独立奶瓶前景和陶土色背景，资源及导出方式见 `app-icon-layers.md`；其他平台保留 `app_icon.png` 合成图标。开屏专用 `launch_icon.png` 带透明圆角，由内置 imagegen 基于原图处理，避免依赖各平台是否自动裁切。
- Android、iOS、鸿蒙及 Web 使用同一份开屏图，Web 不再单独依靠 CSS 圆角模拟。生成要求见 `launch-icon-prompt.txt`。
- `launch-branding.svg` 与 `launch-branding-dark.svg` 是浅色、深色字标母版，画布为 200 × 80。
- 标题为“奶点记”，短句为“记下每一餐，安心每一天”。字形轮廓沿用此前从 Noto Serif SC 转换的路径，使用 500 字重；标题 26、字距 5，短句 11、字距 1。
- SVG 已将文字转为路径，不嵌入或加载字体文件。依据 [OFL 官方 FAQ 1.1.1–1.1.2](https://openfontlicense.org/ofl-faq/)，这类图形作品无需附带字体许可；项目不再打包 Noto 字体及其许可文件。
- 鸿蒙的 `startWindowBrandingImage` 采用只缩小、不放大的图片布局。其 base/dark 资源单独以 `800 × 320` 的内禀尺寸导出，保留 `200 × 80` 的 viewBox，并将副标题提高到 14；避免把 200 像素直接作为高密度屏上的最终宽度。不要用普通母版直接覆盖这两份资源。
- 浅色背景 / 主色 / 次文字色：`#FAF6EE` / `#AD593C` / `#706257`；深色：`#221E1B` / `#EDA987` / `#C5B3A2`，与 `AppPalette` 保持一致。

原生启动资源随系统深浅色外观切换。应用内手动选择的主题在 Flutter 读取设置后接管。启动画面由平台首帧机制结束，不添加固定停留时间。

修改开屏图后需要同步 Android `drawable-nodpi/launch_icon.png`、iOS `LaunchImage` 图片集、鸿蒙 `base/media/launch_icon.png` 及 Web `icons/Launch.png`。鸿蒙旧式 `startWindowIcon` 与增强 `startWindowAppIcon` 均引用开屏专用资源，桌面图标引用保持不变。

修改字标母版后需要同步 Android drawable、iOS LaunchBranding 图片集；鸿蒙 base/dark media 按上述专用导出尺寸和字号重新生成。Web 使用相同图标和文案，由 HTML/CSS 显示，收到 Flutter 首帧事件后移除。
