"""Export the bundled Inter font's exact countdown outlines as Dart paths.

From the repository root (no Flutter or runtime package required):
    python -m pip install --target build/font_tools fonttools==4.66.0
    python tool/generate_countdown_glyphs.py
    python tool/generate_countdown_glyphs.py --check

All variable axes are pinned: weight 600, others at the font defaults. The
OpenType tnum feature is applied, including its colon/hyphen alternates. Curves
are preserved, never flattened or simplified. A single affine transform puts
the shared ink bounds at y=0..100, preserving a common baseline and advances.

Original outlines: Copyright 2020 The Inter Project Authors.
Font license: assets/fonts/OFL-Inter.txt (SIL Open Font License 1.1).
"""

from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "build" / "font_tools"))
try:
    import fontTools
    from fontTools.pens.basePen import BasePen
    from fontTools.pens.boundsPen import BoundsPen
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont
except ImportError as error:
    raise SystemExit(
        "Install the build-only dependency: python -m pip install "
        "--target build/font_tools fonttools==4.66.0"
    ) from error


FONT = ROOT / "assets" / "fonts" / "InterVariable.ttf"
OUTPUT = ROOT / "lib" / "widgets" / "countdown_glyphs.dart"
CHARACTERS = "0123456789:-"


def number(value: float) -> str:
    """Stable Dart double literals; error is below 0.000000005 logical units."""
    if not math.isfinite(value):
        raise ValueError("The font contains a non-finite coordinate")
    result = f"{value:.8f}".rstrip("0").rstrip(".")
    return "0.0" if result in ("0", "-0") else result if "." in result else result + ".0"


class DartPathPen(BasePen):
    def __init__(self, glyph_set, scale: float, top: float):
        super().__init__(glyph_set)
        self.scale = scale
        self.top = top
        self.commands: list[str] = []
        self.contours = 0

    def point(self, point) -> str:
        x, y = point
        return f"{number(x * self.scale)}, {number((self.top - y) * self.scale)}"

    def _moveTo(self, point):
        self.commands.append(f"..moveTo({self.point(point)})")

    def _lineTo(self, point):
        self.commands.append(f"..lineTo({self.point(point)})")

    def _qCurveToOne(self, control, end):
        self.commands.append(
            f"..quadraticBezierTo({self.point(control)}, {self.point(end)})"
        )

    def _curveToOne(self, first, second, end):
        self.commands.append(
            f"..cubicTo({self.point(first)}, {self.point(second)}, {self.point(end)})"
        )

    def _closePath(self):
        self.commands.append("..close()")
        self.contours += 1

    def _endPath(self):
        raise ValueError("Expected closed font contours, found an open path")


def tabular_substitutions(font: TTFont) -> list[dict[str, str]]:
    """Read the actual GSUB feature rather than guessing glyph suffixes."""
    if "GSUB" not in font:
        return []
    table = font["GSUB"].table
    lookup_indices = []
    for feature in table.FeatureList.FeatureRecord:
        if feature.FeatureTag == "tnum":
            for index in feature.Feature.LookupListIndex:
                if index not in lookup_indices:
                    lookup_indices.append(index)
    substitutions = []
    for index in lookup_indices:
        lookup = table.LookupList.Lookup[index]
        for subtable in lookup.SubTable:
            lookup_type = lookup.LookupType
            if lookup_type == 7:  # GSUB extension lookup.
                lookup_type = subtable.ExtensionLookupType
                subtable = subtable.ExtSubTable
            if lookup_type != 1:
                raise ValueError(f"Unsupported tnum lookup type: {lookup_type}")
            substitutions.append(subtable.mapping)
    return substitutions


def generate() -> str:
    source = TTFont(FONT)
    axes = {axis.axisTag: axis.defaultValue for axis in source["fvar"].axes}
    axes["wght"] = 600
    font = instantiateVariableFont(source, axes, inplace=True)
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()
    substitutions = tabular_substitutions(font)
    glyph_names = {}
    bounds = {}
    for character in CHARACTERS:
        name = cmap[ord(character)]
        for substitution in substitutions:
            name = substitution.get(name, name)
        glyph_names[character] = name
        pen = BoundsPen(glyph_set)
        glyph_set[name].draw(pen)
        if pen.bounds is None:
            raise ValueError(f"Empty countdown glyph: {name}")
        bounds[character] = pen.bounds

    bottom = min(bound[1] for bound in bounds.values())
    top = max(bound[3] for bound in bounds.values())
    scale = 100.0 / (top - bottom)
    advances = {
        character: glyph_set[name].width * scale
        for character, name in glyph_names.items()
    }
    if len({round(advances[character], 8) for character in "0123456789"}) != 1:
        raise ValueError("Countdown numerals must have equal advances")
    for character, (left, _, right, _) in bounds.items():
        if left < 0 or right * scale > advances[character]:
            raise ValueError(f"Glyph exceeds its horizontal advance: {character}")

    axis_description = ", ".join(f"{key}={value:g}" for key, value in axes.items())
    digest = hashlib.sha256(FONT.read_bytes()).hexdigest()
    lines = [
        "// GENERATED FILE. Regenerate with tool/generate_countdown_glyphs.py.",
        "// dart format off",
        "// Outlines: Copyright 2020 The Inter Project Authors; SIL OFL 1.1.",
        "// License: assets/fonts/OFL-Inter.txt. No runtime font parsing required.",
        f"// Source SHA-256: {digest}",
        f"// fontTools {fontTools.__version__}; {axis_description}; OpenType tnum.",
        "",
        "import 'dart:ui';",
        "",
        "/// Bundled Inter 600 outlines with tabular countdown glyphs.",
        "///",
        "/// All paths share one baseline and y=0..[height] ink bounds. Advances",
        "/// include the original side bearings. The single normalization retains",
        "/// Inter's round-glyph overshoot, counters and original quadratic curves.",
        "/// Scale x and y equally by desiredInkHeight / height when painting.",
        "/// Supported characters are [characters]; other input throws ArgumentError.",
        "abstract final class CountdownGlyphs {",
        f"  static const String characters = '{CHARACTERS}';",
        "  static const double height = 100.0;",
        f"  static const double baseline = {number(top * scale)};",
        f"  static const double capHeight = {number(font['OS/2'].sCapHeight * scale)};",
        f"  static const double unitsPerEm = {number(font['head'].unitsPerEm * scale)};",
        f"  static const double digitAdvance = {number(advances['0'])};",
        "",
        "  /// Returns a copy, so callers can safely transform or extend the path.",
        "  static Path pathFor(String character) {",
        "    final path = _paths[character];",
        "    if (path == null) {",
        "      throw ArgumentError.value(character, 'character', 'Unsupported glyph');",
        "    }",
        "    return Path.from(path);",
        "  }",
        "",
        "  static double advanceFor(String character) {",
        "    final advance = _advances[character];",
        "    if (advance == null) {",
        "      throw ArgumentError.value(character, 'character', 'Unsupported glyph');",
        "    }",
        "    return advance;",
        "  }",
        "",
        "  /// Advance-box width, without kerning; spacing uses the same units.",
        "  static double widthOf(String text, {double letterSpacing = 0}) {",
        "    if (text.isEmpty) {",
        "      return 0;",
        "    }",
        "    var width = letterSpacing * (text.length - 1);",
        "    for (final character in text.split('')) {",
        "      width += advanceFor(character);",
        "    }",
        "    return width;",
        "  }",
        "",
        "  static Size sizeOf(String text, {double letterSpacing = 0}) => Size(",
        "    widthOf(text, letterSpacing: letterSpacing),",
        "    text.isEmpty ? 0 : height,",
        "  );",
        "",
        "  /// Combines glyphs in the same advance box returned by [sizeOf].",
        "  static Path pathForText(String text, {double letterSpacing = 0}) {",
        "    final result = Path();",
        "    var x = 0.0;",
        "    for (final character in text.split('')) {",
        "      result.addPath(pathFor(character), Offset(x, 0));",
        "      x += advanceFor(character) + letterSpacing;",
        "    }",
        "    return result;",
        "  }",
        "",
        "  static const _advances = <String, double>{",
    ]
    for character in CHARACTERS:
        lines.append(f"    '{character}': {number(advances[character])},")
    lines.extend(["  };", "", "  static final _paths = <String, Path>{"])
    total_commands = 0
    for character in CHARACTERS:
        name = glyph_names[character]
        pen = DartPathPen(glyph_set, scale, top)
        glyph_set[name].draw(pen)
        if not pen.contours:
            raise ValueError(f"No closed contours for {name}")
        total_commands += len(pen.commands)
        lines.append(f"    // {name}; {pen.contours} closed contour(s).")
        lines.append(f"    '{character}': Path()")
        for index, command in enumerate(pen.commands):
            suffix = "," if index == len(pen.commands) - 1 else ""
            lines.append(f"      {command}{suffix}")
    lines.extend(["  };", "}", ""])
    print(
        f"Validated {len(CHARACTERS)} glyphs / {total_commands} path operations; "
        f"{axis_description}; digit advance {number(advances['0'])}; "
        f"baseline {number(top * scale)}"
    )
    font.close()
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="Check output without changing files"
    )
    arguments = parser.parse_args()
    generated = generate()
    if arguments.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != generated:
            raise SystemExit("Countdown glyph output is out of date; regenerate it.")
        print("Generated Dart output is up to date.")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(generated, encoding="utf-8", newline="\n")
        print(f"Wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
