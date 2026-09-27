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

Use `JournalSerif` for large numbers, times and short Latin headings. The clock
enables `tnum` and `lnum` and disables kerning (including repeated 1s); both supplied weights also have equal default advances
for all ten digits. Normal display uses weight 400; high-contrast accessibility
uses the supplied weight 700 to strengthen strokes without synthetic bolding.
Keep explanatory copy in Inter.

## JournalChinese — Noto Serif SC subset

`NotoSerifSCSubset.ttf` derives from `NotoSerifSC[wght].ttf` in the
[Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/notoserifsc),
downloaded on 2026-09-27, Git blob
`eab063faf229160a52d3760f5555150e4eb9e5bf`. See `OFL-NotoSerifSC.txt`.

This subset retains 7,624 encoded characters, including the GB2312 repertoire,
Latin-1 and all current application copy, while keeping the 200–900 variable
weight axis. It is about 5.2 MiB instead of the original 24 MiB. FontTools 4.66.0
performed Unicode subsetting with default layout-feature closure, preserving all
name IDs/languages and legacy names. No outlines, advances or design were edited.

Use `JournalChinese` for Chinese page headings, date labels and short navigation
labels, normally at weight 400–500. Use Inter with JournalChinese as the bundled Chinese fallback for
small explanatory text. The subset is not a complete CJK font; if new text needs a
rare character, add it to the subset or allow the system font fallback.

## Inter

`InterVariable.ttf` remains the body and control font. Its existing license is
`OFL-Inter.txt`.
