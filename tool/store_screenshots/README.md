# Reproducible store screenshot source

This separate entry point renders the **real `FeedReminderApp`** with fixed
in-memory demonstration data. Open features through the app's actual controls.
It never changes production `lib/`, device storage, or the release entry point.

## Build and serve locally

Use the ordinary Flutter SDK and its existing package resolution:

```powershell
./tool/store_screenshots/build.ps1 -Flutter flutter
# A full flutter.bat path is also accepted.
python -m http.server 8765 --bind 127.0.0.1 --directory build/store-assets-1.1.0-5/app
```

`-OutputDirectory` and `-FontDirectory` override the output and Windows fonts
directories. The build uses `--no-pub`. Complete normal dependency setup first
if `.dart_tool/package_config.json` does not exist.

Microsoft YaHei (`msyh.ttc` / `msyhbd.ttc`) is copied from Windows to the **ignored
local build**, never to tracked source. Serve this capture build on localhost
only and do not publish/distribute those OS font files. The final screenshot
PNGs contain rendered application pixels.

## Capture geometry

The application frame is always **432 × 768 logical pixels**, positioned at the
top-left in `FittedBox(fit: BoxFit.contain)`, with no added title bar, corner mask,
or device bezel. Its internal MediaQuery also remains exactly 432 × 768.

Set the browser content viewport to **864 × 1536** at DPR=1 for an exact 2× frame.
The whole screenshot will then be **864 × 1536 pixels**, without outer space.
A 432 × 768 viewport at DPR=2 produces the same pixel size. Other viewport aspect
ratios show grey outside the fitted application; do not include that area in
published images.

- `http://127.0.0.1:8765/`: normal light fixture.
- `?state=overdue`: overdue fixture for the snooze screenshot.
- `?theme=dark`: optional dark preview; the actual settings control also works.
- `?state=overdue&theme=dark`: both options are supported.

Save raw captures in `build/store-assets-1.1.0-5/raw/`. Poster layout is separate:
all raw frames must share the same size and origin and preserve actual app pixels.

## Deterministic fixture and fonts

- Fixed local time **2026-10-06 10:20**; six complete previous days plus today.
- Today's normal four meals: **00:00 / 03:00 / 06:00 / 09:00**, each **180 mL**,
  total **720 mL**. Three-hour interval gives next reminder **12:00** and **1:40**
  remaining. Previous days vary for the seven-day chart.
- Overdue fixture: last meal **06:40**, showing **40 minutes** overdue.
- SharedPreferences is an in-memory mock. The injected provider clock does not
  advance and its periodic timer is disabled. Reloading restores the fixture.
- Platform effects are disabled; notification and audio services are inert.
- Animations and text scaling are fixed. Original shadows and icon assets remain.
- Microsoft YaHei is loaded explicitly into the platform font families. Tinos
  comes from the repository. Width checks include unstyled custom painters and
  stop setup if text falls back to square test glyphs. This uses real Web rendering
  because `flutter test` hard-codes `--use-test-fonts`; dynamic fonts cannot replace
  the default font of all its unstyled `TextPainter` instances.

Live semantics expose the real controls for capture automation. Microsoft YaHei
does not claim to be HarmonyOS's system font. Verify every screenshot visually
and check the browser console before publication.

## Nine frames and actual navigation

| File | Action |
| --- | --- |
| `01-timer.png` | Normal fixture's initial timer |
| `02-milk-amount.png` | Tap **奶量** → 调整本次奶量 |
| `03-history.png` | Cancel dialog → **记录** tab |
| `04-backfill.png` | **补记喂奶** on history |
| `05-statistics.png` | Cancel form → **奶量统计**, default 7 days |
| `06-snooze.png` | Reload overdue fixture → **稍后提醒** |
| `07-settings.png` | Normal fixture → **设置**, scroll to show night controls |
| `08-dark-timer.png` | Settings → 外观主题 **深色** → **计时** |
| `09-data-management.png` | Switch theme back to 浅色 → Settings → **管理喂奶记录** |

Stable code keys: `adjust-meal-amount`, `nav-history`,
`history-backfill-button`, `history-statistics-button`, `snooze-reminder`,
`nav-settings`, `night-end-time`, `theme-mode-dark`, `nav-home`,
`theme-mode-light`, `open-data-management`.

## Compose and review the listing images

`listing.json` is the shared source for the current Chinese listing text and all
ten poster captions. After capturing the nine complete app frames, place the
current native Previewer renders in `raw/widgets/` as
`QaNormalWide-light.jpg`, `QaNormalSquare-light.jpg`, and
`QaNormalCompact-light.jpg`. The tenth image labels this native-card composition
explicitly; it is not a fabricated phone-home-screen capture.

```powershell
python tool/store_screenshots/compose.py
```

Use a Python environment with Pillow. Every poster has a 1080 × 1920 canvas and
the same app viewport at (108, 336), sized 864 × 1536 with a 52 px corner radius.
The script rejects mismatched frame sizes, distorted card aspect ratios,
overflowing captions, and files over AppGallery's 5 MiB limit. It writes source
hashes and geometry to `manifest.json`, plus a contact sheet and review gallery.

Review every full-size poster as well as the contact sheet before uploading.
Confirm text, controls, dates, amounts, backgrounds, masks, and absence of desktop
or browser chrome. The geometry checks alone do not constitute visual approval.
These are real Flutter Web screens with isolated example records; they do not
establish HarmonyOS system-font, notification, or home-screen interaction results.
