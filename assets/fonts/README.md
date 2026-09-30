# Bundled typefaces

All typefaces are distributed under the SIL Open Font License 1.1. Keep the
corresponding OFL files with redistributed application/font files.

## JournalSerif — Tinos

`Tinos-Regular.ttf` and `Tinos-Bold.ttf` are unmodified upright fonts from the
[Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/tinos),
downloaded on 2026-09-27. The upstream project and license are at
[googlefonts/tinos](https://github.com/googlefonts/tinos).
The downloaded Git blobs are `893a1b525962984481aee5ce275516d384eb4865`
(regular) and `887fc97a95d30a08190217b6075a5e0a0f92bec7` (bold).
Both downloaded fonts identify SIL OFL 1.1 in their embedded license records.
See `OFL-Tinos.txt`.

Use `JournalSerif` only for the large countdown and standby time display.
The clock enables `tnum` and `lnum` and disables kerning (including repeated 1s);
both supplied weights also have equal default advances
for all ten digits. Normal display uses weight 400; high-contrast accessibility
uses the supplied weight 700 to strengthen strokes without synthetic bolding.

All other text uses the platform's default fonts. No additional custom text
font is bundled or assigned globally.
