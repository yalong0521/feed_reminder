// GENERATED FILE. Regenerate with tool/generate_countdown_glyphs.py.
// dart format off
// Outlines: Copyright 2020 The Inter Project Authors; SIL OFL 1.1.
// License: assets/fonts/OFL-Inter.txt. No runtime font parsing required.
// Source SHA-256: 29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031
// fontTools 4.66.0; opsz=14, wght=600; OpenType tnum.

import 'dart:ui';

/// Bundled Inter 600 outlines with tabular countdown glyphs.
///
/// All paths share one baseline and y=0..[height] ink bounds. Advances
/// include the original side bearings. The single normalization retains
/// Inter's round-glyph overshoot, counters and original quadratic curves.
/// Scale x and y equally by desiredInkHeight / height when painting.
/// Supported characters are [characters]; other input throws ArgumentError.
abstract final class CountdownGlyphs {
  static const String characters = '0123456789:-';
  static const double height = 100.0;
  static const double baseline = 98.6013779;
  static const double capHeight = 97.19928251;
  static const double unitsPerEm = 133.60008764;
  static const double digitAdvance = 86.43560358;

  /// Returns a copy, so callers can safely transform or extend the path.
  static Path pathFor(String character) {
    final path = _paths[character];
    if (path == null) {
      throw ArgumentError.value(character, 'character', 'Unsupported glyph');
    }
    return Path.from(path);
  }

  static double advanceFor(String character) {
    final advance = _advances[character];
    if (advance == null) {
      throw ArgumentError.value(character, 'character', 'Unsupported glyph');
    }
    return advance;
  }

  /// Advance-box width, without kerning; spacing uses the same units.
  static double widthOf(String text, {double letterSpacing = 0}) {
    if (text.isEmpty) {
      return 0;
    }
    var width = letterSpacing * (text.length - 1);
    for (final character in text.split('')) {
      width += advanceFor(character);
    }
    return width;
  }

  static Size sizeOf(String text, {double letterSpacing = 0}) => Size(
    widthOf(text, letterSpacing: letterSpacing),
    text.isEmpty ? 0 : height,
  );

  /// Combines glyphs in the same advance box returned by [sizeOf].
  static Path pathForText(String text, {double letterSpacing = 0}) {
    final result = Path();
    var x = 0.0;
    for (final character in text.split('')) {
      result.addPath(pathFor(character), Offset(x, 0));
      x += advanceFor(character) + letterSpacing;
    }
    return result;
  }

  static const _advances = <String, double>{
    '0': 86.43560358,
    '1': 86.43560358,
    '2': 86.43560358,
    '3': 86.43560358,
    '4': 86.43560358,
    '5': 86.43560358,
    '6': 86.43560358,
    '7': 86.43560358,
    '8': 86.43560358,
    '9': 86.43560358,
    ':': 35.87892979,
    '-': 86.43560358,
  };

  static final _paths = <String, Path>{
    // zero.tf; 2 closed contour(s).
    '0': Path()
      ..moveTo(43.22171968, 99.90606626)
      ..quadraticBezierTo(31.42998549, 99.90606626, 23.37485679, 94.01148522)
      ..quadraticBezierTo(15.31972808, 88.11690419, 11.2112697, 76.97356046)
      ..quadraticBezierTo(7.10281132, 65.83021674, 7.10281132, 50.06697107)
      ..quadraticBezierTo(7.10281132, 34.30372539, 11.25302068, 23.13689823)
      ..quadraticBezierTo(15.40323004, 11.97007107, 23.43748326, 6.03373905)
      ..quadraticBezierTo(31.47173648, 0.09740703, 43.22171968, 0.09740703)
      ..quadraticBezierTo(54.97170288, 0.09740703, 63.0385733, 6.04548077)
      ..quadraticBezierTo(71.10544373, 11.99355451, 75.22303588, 23.14863995)
      ..quadraticBezierTo(79.34062803, 34.30372539, 79.34062803, 50.06697107)
      ..quadraticBezierTo(79.34062803, 65.83021674, 75.24391137, 76.97356046)
      ..quadraticBezierTo(71.14719471, 88.11690419, 63.11294149, 94.01148522)
      ..quadraticBezierTo(55.07868828, 99.90606626, 43.22171968, 99.90606626)
      ..close()
      ..moveTo(43.22171968, 85.27283647)
      ..quadraticBezierTo(49.510351, 85.27283647, 53.74018027, 81.29612103)
      ..quadraticBezierTo(57.97000954, 77.3194056, 60.1123255, 69.45862242)
      ..quadraticBezierTo(62.25464146, 61.59783924, 62.25464146, 50.06697107)
      ..quadraticBezierTo(62.25464146, 38.40563405, 60.1123255, 30.53310915)
      ..quadraticBezierTo(57.97000954, 22.66058426, 53.74018027, 18.65125162)
      ..quadraticBezierTo(49.510351, 14.64191898, 43.22171968, 14.64191898)
      ..quadraticBezierTo(36.95657179, 14.64191898, 32.7150008, 18.65125162)
      ..quadraticBezierTo(28.47342981, 22.66058426, 26.33111385, 30.53310915)
      ..quadraticBezierTo(24.18879789, 38.40563405, 24.18879789, 50.06697107)
      ..quadraticBezierTo(24.18879789, 61.59783924, 26.33111385, 69.45862242)
      ..quadraticBezierTo(28.47342981, 77.3194056, 32.7150008, 81.29612103)
      ..quadraticBezierTo(36.95657179, 85.27283647, 43.22171968, 85.27283647)
      ..close(),
    // one.tf; 2 closed contour(s).
    '1': Path()
      ..moveTo(12.61120174, 98.6013779)
      ..lineTo(12.61120174, 84.35955462)
      ..lineTo(76.40248323, 84.35955462)
      ..lineTo(76.40248323, 98.6013779)
      ..close()
      ..moveTo(55.62919127, 1.40209539)
      ..lineTo(55.62919127, 98.6013779)
      ..lineTo(38.33444979, 98.6013779)
      ..lineTo(38.33444979, 16.92250371)
      ..lineTo(37.68210561, 16.92250371)
      ..lineTo(14.99615199, 33.23637183)
      ..lineTo(14.99615199, 16.64086972)
      ..lineTo(36.3669377, 1.40209539)
      ..close(),
    // two.tf; 1 closed contour(s).
    '2': Path()
      ..moveTo(10.28624613, 98.6013779)
      ..lineTo(10.28624613, 86.07129714)
      ..lineTo(44.00977247, 52.84863926)
      ..quadraticBezierTo(48.76669297, 48.0108128, 52.00233442, 44.22066684)
      ..quadraticBezierTo(55.23797588, 40.43052089, 56.91189725, 36.85304774)
      ..quadraticBezierTo(58.58581862, 33.27557459, 58.58581862, 29.15013472)
      ..quadraticBezierTo(58.58581862, 24.55500226, 56.4656881, 21.22411712)
      ..quadraticBezierTo(54.34555758, 17.89323198, 50.71719967, 16.10319144)
      ..quadraticBezierTo(47.08884176, 14.31315089, 42.43369078, 14.31315089)
      ..quadraticBezierTo(37.56978487, 14.31315089, 33.96230246, 16.28193709)
      ..quadraticBezierTo(30.35482004, 18.25072328, 28.3834259, 21.86994742)
      ..quadraticBezierTo(26.41203176, 25.48917155, 26.41203176, 30.47571051)
      ..lineTo(9.79571389, 30.47571051)
      ..quadraticBezierTo(9.79571389, 21.27768149, 13.99810601, 14.44895506)
      ..quadraticBezierTo(18.20049812, 7.62022863, 25.61371443, 3.85881783)
      ..quadraticBezierTo(33.02693073, 0.09740703, 42.64244569, 0.09740703)
      ..quadraticBezierTo(52.39886126, 0.09740703, 59.75466698, 3.75314237)
      ..quadraticBezierTo(67.11047269, 7.40887771, 71.23197079, 13.76400562)
      ..quadraticBezierTo(75.35346888, 20.11913352, 75.35346888, 28.26819597)
      ..quadraticBezierTo(75.35346888, 33.66960099, 73.30902844, 38.84790143)
      ..quadraticBezierTo(71.264588, 44.02620186, 66.05629023, 50.494841)
      ..quadraticBezierTo(60.84799247, 56.96348014, 51.32119537, 66.11978206)
      ..lineTo(34.42269404, 83.33145159)
      ..lineTo(34.42269404, 84.06729774)
      ..lineTo(76.77297841, 84.06729774)
      ..lineTo(76.77297841, 98.6013779)
      ..close(),
    // three.tf; 1 closed contour(s).
    '3': Path()
      ..moveTo(42.86684827, 99.90606626)
      ..quadraticBezierTo(32.63812022, 99.90606626, 24.71477029, 96.39776931)
      ..quadraticBezierTo(16.79142036, 92.88947235, 12.1950138, 86.66090734)
      ..quadraticBezierTo(7.59860723, 80.43234233, 7.38985232, 72.2415289)
      ..lineTo(24.94031559, 72.2415289)
      ..quadraticBezierTo(25.19082148, 76.21563639, 27.57580757, 79.15250708)
      ..quadraticBezierTo(29.96079365, 82.08937777, 33.94272497, 83.68371506)
      ..quadraticBezierTo(37.92465628, 85.27805235, 42.83552906, 85.27805235)
      ..quadraticBezierTo(48.07519381, 85.27805235, 52.10018605, 83.45147671)
      ..quadraticBezierTo(56.1251783, 81.62490107, 58.4305803, 78.33967285)
      ..quadraticBezierTo(60.7359823, 75.05444464, 60.7359823, 70.75938095)
      ..quadraticBezierTo(60.7359823, 66.29731332, 58.39927303, 62.91944937)
      ..quadraticBezierTo(56.06256377, 59.54158542, 51.68530805, 57.62237403)
      ..quadraticBezierTo(47.30805234, 55.70316265, 41.12378653, 55.70316265)
      ..lineTo(32.5024355, 55.70316265)
      ..lineTo(32.5024355, 42.23888871)
      ..lineTo(41.12378653, 42.23888871)
      ..quadraticBezierTo(46.16512814, 42.23888871, 50.02180651, 40.45406405)
      ..quadraticBezierTo(53.87848488, 38.66923939, 56.03384056, 35.47925486)
      ..quadraticBezierTo(58.18919623, 32.28927033, 58.18919623, 28.01769007)
      ..quadraticBezierTo(58.18919623, 23.8948462, 56.31565372, 20.82358879)
      ..quadraticBezierTo(54.44211121, 17.75233137, 51.03293999, 16.03274113)
      ..quadraticBezierTo(47.62376877, 14.31315089, 43.04428397, 14.31315089)
      ..quadraticBezierTo(38.55613692, 14.31315089, 34.75816713, 15.9192299)
      ..quadraticBezierTo(30.96019735, 17.52530891, 28.61043642, 20.46478754)
      ..quadraticBezierTo(26.26067549, 23.40426618, 26.13542254, 27.53232594)
      ..lineTo(9.38341995, 27.53232594)
      ..quadraticBezierTo(9.55042388, 19.43023036, 14.05550465, 13.24863222)
      ..quadraticBezierTo(18.56058542, 7.06703408, 26.16689703, 3.58222056)
      ..quadraticBezierTo(33.77320865, 0.09740703, 43.2112879, 0.09740703)
      ..quadraticBezierTo(52.88944128, 0.09740703, 60.06781129, 3.75053443)
      ..quadraticBezierTo(67.2461813, 7.40366183, 71.17979997, 13.50437789)
      ..quadraticBezierTo(75.11341864, 19.60509395, 75.11341864, 26.98961094)
      ..quadraticBezierTo(75.11341864, 35.16218071, 70.30566117, 40.72668371)
      ..quadraticBezierTo(65.49790369, 46.29118672, 57.6149948, 48.06297166)
      ..lineTo(57.6149948, 48.79881781)
      ..quadraticBezierTo(64.39935036, 49.7303672, 69.09621649, 52.84466165)
      ..quadraticBezierTo(73.79308263, 55.9589561, 76.21457992, 60.76934542)
      ..quadraticBezierTo(78.63607721, 65.57973473, 78.63607721, 71.6413197)
      ..quadraticBezierTo(78.63607721, 79.81126958, 74.02532098, 86.20293258)
      ..quadraticBezierTo(69.41456475, 92.59459558, 61.33726255, 96.25033092)
      ..quadraticBezierTo(53.25996035, 99.90606626, 42.86684827, 99.90606626)
      ..close(),
    // four.tf; 2 closed contour(s).
    '4': Path()
      ..moveTo(5.47457077, 80.50267319)
      ..lineTo(5.47457077, 66.65747229)
      ..lineTo(46.78627256, 1.40209539)
      ..lineTo(58.25693109, 1.40209539)
      ..lineTo(58.25693109, 21.20187196)
      ..lineTo(51.23778896, 21.20187196)
      ..lineTo(23.29642737, 65.37364748)
      ..lineTo(23.29642737, 66.15646049)
      ..lineTo(80.9271176, 66.15646049)
      ..lineTo(80.9271176, 80.50267319)
      ..close()
      ..moveTo(51.74401664, 98.6013779)
      ..lineTo(51.74401664, 76.32771823)
      ..lineTo(52.02060197, 70.03918246)
      ..lineTo(52.02060197, 1.40209539)
      ..lineTo(68.45426825, 1.40209539)
      ..lineTo(68.45426825, 98.6013779)
      ..close(),
    // five.tf; 1 closed contour(s).
    '5': Path()
      ..moveTo(42.25885107, 99.90606626)
      ..quadraticBezierTo(32.75032151, 99.90606626, 25.28492245, 96.33514283)
      ..quadraticBezierTo(17.81952339, 92.7642194, 13.4462214, 86.5147789)
      ..quadraticBezierTo(9.07291941, 80.2653384, 8.81719762, 72.2415289)
      ..lineTo(25.75185181, 72.2415289)
      ..quadraticBezierTo(26.00235771, 76.19474895, 28.26469878, 79.25817059)
      ..quadraticBezierTo(30.52703986, 82.32159223, 34.19323086, 84.03465664)
      ..quadraticBezierTo(37.85942187, 85.74772105, 42.25885107, 85.74772105)
      ..quadraticBezierTo(47.4724125, 85.74772105, 51.50783651, 83.37186874)
      ..quadraticBezierTo(55.54326053, 80.99601643, 57.83561088, 76.77923882)
      ..quadraticBezierTo(60.12796122, 72.56246121, 60.12796122, 67.11144555)
      ..quadraticBezierTo(60.12796122, 61.55344448, 57.75210891, 57.24142319)
      ..quadraticBezierTo(55.3762566, 52.92940189, 51.25733062, 50.49092311)
      ..quadraticBezierTo(47.13840463, 48.05244433, 41.75783927, 48.05244433)
      ..quadraticBezierTo(37.35059819, 48.05244433, 33.12991463, 49.69895244)
      ..quadraticBezierTo(28.90923108, 51.34546054, 26.46161852, 54.03309944)
      ..lineTo(10.66984076, 51.47073738)
      ..lineTo(15.70596648, 1.40209539)
      ..lineTo(71.96913882, 1.40209539)
      ..lineTo(71.96913882, 15.98314243)
      ..lineTo(30.18262411, 15.98314243)
      ..lineTo(27.39578781, 41.84738664)
      ..lineTo(27.91766315, 41.84738664)
      ..quadraticBezierTo(30.66012858, 38.66397572, 35.60227279, 36.60780551)
      ..quadraticBezierTo(40.54441699, 34.55163529, 46.41287081, 34.55163529)
      ..quadraticBezierTo(52.99633112, 34.55163529, 58.59214139, 36.91834188)
      ..quadraticBezierTo(64.18795166, 39.28504847, 68.32772925, 43.61792137)
      ..quadraticBezierTo(72.46750684, 47.95079426, 74.75984523, 53.8284177)
      ..quadraticBezierTo(77.05218363, 59.70604113, 77.05218363, 66.70439138)
      ..quadraticBezierTo(77.05218363, 76.33819778, 72.62147105, 83.83232005)
      ..quadraticBezierTo(68.19075847, 91.32644232, 60.3561264, 95.61625429)
      ..quadraticBezierTo(52.52149432, 99.90606626, 42.25885107, 99.90606626)
      ..close(),
    // six.tf; 2 closed contour(s).
    '6': Path()
      ..moveTo(44.26806636, 99.90606626)
      ..quadraticBezierTo(37.33237842, 99.90606626, 30.70197513, 97.52371201)
      ..quadraticBezierTo(24.07157183, 95.14135776, 18.77585422, 89.71125343)
      ..quadraticBezierTo(13.48013661, 84.28114909, 10.3501945, 75.21487496)
      ..quadraticBezierTo(7.22025239, 66.14860083, 7.22025239, 52.78076107)
      ..quadraticBezierTo(7.22025239, 40.30531572, 9.86615225, 30.54493449)
      ..quadraticBezierTo(12.51205211, 20.78455325, 17.50508107, 13.9845142)
      ..quadraticBezierTo(22.49811003, 7.18447514, 29.52122977, 3.64094109)
      ..quadraticBezierTo(36.54434952, 0.09740703, 45.27530584, 0.09740703)
      ..quadraticBezierTo(54.36894545, 0.09740703, 61.43772212, 3.67615429)
      ..quadraticBezierTo(68.50649879, 7.25490155, 72.88632661, 13.44824141)
      ..quadraticBezierTo(77.26615443, 19.64158127, 78.29947334, 27.53232594)
      ..lineTo(61.18738345, 27.53232594)
      ..quadraticBezierTo(59.83832422, 21.97954076, 55.72984196, 18.58470726)
      ..quadraticBezierTo(51.62135969, 15.18987375, 45.27530584, 15.18987375)
      ..quadraticBezierTo(38.51960182, 15.18987375, 33.79529853, 19.16136135)
      ..quadraticBezierTo(29.07099523, 23.13284895, 26.62338268, 30.52785743)
      ..quadraticBezierTo(24.17577012, 37.92286591, 24.17577012, 48.21430404)
      ..lineTo(24.86464939, 48.21430404)
      ..quadraticBezierTo(27.21570832, 44.02886953, 30.89231915, 41.02026248)
      ..quadraticBezierTo(34.56892999, 38.01165544, 39.24623058, 36.41993803)
      ..quadraticBezierTo(43.92353116, 34.82822062, 49.11096538, 34.82822062)
      ..quadraticBezierTo(57.64883833, 34.82822062, 64.45801116, 38.89102208)
      ..quadraticBezierTo(71.26718399, 42.95382353, 75.24518548, 50.11004394)
      ..quadraticBezierTo(79.22318697, 57.26626435, 79.22318697, 66.49563647)
      ..quadraticBezierTo(79.22318697, 76.05637267, 74.84988498, 83.61312142)
      ..quadraticBezierTo(70.47658298, 91.16987016, 62.61194164, 95.53796821)
      ..quadraticBezierTo(54.7473003, 99.90606626, 44.26806636, 99.90606626)
      ..close()
      ..moveTo(44.17413262, 85.74772105)
      ..quadraticBezierTo(49.36421061, 85.74772105, 53.46226111, 83.22313236)
      ..quadraticBezierTo(57.5603116, 80.69854367, 59.94790562, 76.41913958)
      ..quadraticBezierTo(62.33549965, 72.13973549, 62.33549965, 66.82440455)
      ..quadraticBezierTo(62.33549965, 61.59257558, 60.0105321, 57.35492248)
      ..quadraticBezierTo(57.68556455, 53.11726937, 53.62926504, 50.63443166)
      ..quadraticBezierTo(49.57296553, 48.15159396, 44.38288754, 48.15159396)
      ..quadraticBezierTo(40.51054956, 48.15159396, 37.18748825, 49.63372996)
      ..quadraticBezierTo(33.86442694, 51.11586597, 31.36984752, 53.72656457)
      ..quadraticBezierTo(28.87526809, 56.33726317, 27.48837577, 59.7255589)
      ..quadraticBezierTo(26.10148344, 63.11385462, 26.10148344, 66.90790652)
      ..quadraticBezierTo(26.10148344, 72.01448255, 28.44732649, 76.29388663)
      ..quadraticBezierTo(30.79316953, 80.57329072, 34.90296174, 83.16050588)
      ..quadraticBezierTo(39.01275395, 85.74772105, 44.17413262, 85.74772105)
      ..close(),
    // seven.tf; 1 closed contour(s).
    '7': Path()
      ..moveTo(16.76531704, 98.6013779)
      ..lineTo(58.11879371, 16.6720217)
      ..lineTo(58.11879371, 15.98314243)
      ..lineTo(10.11140643, 15.98314243)
      ..lineTo(10.11140643, 1.40209539)
      ..lineTo(76.29028194, 1.40209539)
      ..lineTo(76.29028194, 16.40065226)
      ..lineTo(34.88462252, 98.6013779)
      ..close(),
    // eight.tf; 3 closed contour(s).
    '8': Path()
      ..moveTo(43.15648526, 99.90606626)
      ..quadraticBezierTo(32.62506856, 99.90606626, 24.49166572, 96.35731632)
      ..quadraticBezierTo(16.35826288, 92.80856638, 11.76316625, 86.62956424)
      ..quadraticBezierTo(7.16806963, 80.4505621, 7.16806963, 72.58068098)
      ..quadraticBezierTo(7.16806963, 66.49561258, 9.83484499, 61.33817568)
      ..quadraticBezierTo(12.50162034, 56.18073879, 17.10063485, 52.72853053)
      ..quadraticBezierTo(21.69964936, 49.27632228, 27.44287412, 48.29780601)
      ..lineTo(27.44287412, 47.7289638)
      ..quadraticBezierTo(19.90962076, 46.01981727, 15.30017447, 39.98824157)
      ..quadraticBezierTo(10.69072819, 33.95666587, 10.69072819, 26.11810396)
      ..quadraticBezierTo(10.69072819, 18.61093003, 14.89181036, 12.73722448)
      ..quadraticBezierTo(19.09289254, 6.86351894, 26.42260687, 3.48046299)
      ..quadraticBezierTo(33.75232121, 0.09740703, 43.15648526, 0.09740703)
      ..quadraticBezierTo(52.50063077, 0.09740703, 59.84208683, 3.48046299)
      ..quadraticBezierTo(67.18354289, 6.86351894, 71.40550055, 12.7489662)
      ..quadraticBezierTo(75.62745821, 18.63441346, 75.62745821, 26.11810396)
      ..quadraticBezierTo(75.62745821, 33.9801493, 70.973653, 39.99998329)
      ..quadraticBezierTo(66.31984779, 46.01981727, 58.95881425, 47.7289638)
      ..lineTo(58.95881425, 48.29780601)
      ..quadraticBezierTo(64.59505361, 49.27632228, 69.19406812, 52.72853053)
      ..quadraticBezierTo(73.79308263, 56.18073879, 76.51335068, 61.33817568)
      ..quadraticBezierTo(79.23361874, 66.49561258, 79.23361874, 72.58068098)
      ..quadraticBezierTo(79.23361874, 80.4505621, 74.59677113, 86.62956424)
      ..quadraticBezierTo(69.95992353, 92.80856638, 61.81477897, 96.35731632)
      ..quadraticBezierTo(53.66963441, 99.90606626, 43.15648526, 99.90606626)
      ..close()
      ..moveTo(43.15648526, 86.48875919)
      ..quadraticBezierTo(48.65187179, 86.48875919, 52.70295542, 84.57999152)
      ..quadraticBezierTo(56.75403904, 82.67122386, 59.00203045, 79.25422881)
      ..quadraticBezierTo(61.25002187, 75.83723376, 61.25002187, 71.3177675)
      ..quadraticBezierTo(61.25002187, 66.65478073, 58.897653, 63.07599764)
      ..quadraticBezierTo(56.54528412, 59.49721455, 52.45244952, 57.43318467)
      ..quadraticBezierTo(48.35961491, 55.36915479, 43.15648526, 55.36915479)
      ..quadraticBezierTo(37.91682051, 55.36915479, 33.8239859, 57.42144295)
      ..quadraticBezierTo(29.7311513, 59.47373111, 27.37878242, 63.0525142)
      ..quadraticBezierTo(25.02641355, 66.6312973, 25.02641355, 71.3177675)
      ..quadraticBezierTo(25.02641355, 75.83723376, 27.25352947, 79.24248709)
      ..quadraticBezierTo(29.4806454, 82.64774042, 33.57348, 84.56824981)
      ..quadraticBezierTo(37.66631461, 86.48875919, 43.15648526, 86.48875919)
      ..close()
      ..moveTo(43.15648526, 42.15538674)
      ..quadraticBezierTo(47.65246809, 42.15538674, 51.12687373, 40.34707865)
      ..quadraticBezierTo(54.60127936, 38.53877055, 56.62355826, 35.29007744)
      ..quadraticBezierTo(58.64583716, 32.04138432, 58.64583716, 27.82982259)
      ..quadraticBezierTo(58.64583716, 23.59477743, 56.68618473, 20.45306972)
      ..quadraticBezierTo(54.72653231, 17.311362, 51.23125118, 15.55654661)
      ..quadraticBezierTo(47.73597006, 13.80173121, 43.15648526, 13.80173121)
      ..quadraticBezierTo(38.55873291, 13.80173121, 35.06345179, 15.55654661)
      ..quadraticBezierTo(31.56817066, 17.311362, 29.62025995, 20.45306972)
      ..quadraticBezierTo(27.67234925, 23.59477743, 27.67234925, 27.82982259)
      ..quadraticBezierTo(27.67234925, 32.04138432, 29.64113544, 35.27833572)
      ..quadraticBezierTo(31.60992164, 38.51528712, 35.12607826, 40.33533693)
      ..quadraticBezierTo(38.64223488, 42.15538674, 43.15648526, 42.15538674)
      ..close(),
    // nine.tf; 2 closed contour(s).
    '9': Path()
      ..moveTo(41.25163548, 100.0)
      ..quadraticBezierTo(32.09797733, 100.0, 25.01745895, 96.39776931)
      ..quadraticBezierTo(17.93694056, 92.79553861, 13.56885446, 86.52522262)
      ..quadraticBezierTo(9.20076836, 80.25490662, 8.14396601, 72.30414343)
      ..lineTo(25.33955787, 72.30414343)
      ..quadraticBezierTo(26.62859856, 77.94043057, 30.72533911, 81.42398193)
      ..quadraticBezierTo(34.82207966, 84.90753328, 41.25163548, 84.90753328)
      ..quadraticBezierTo(48.0073395, 84.90753328, 52.7107673, 80.91256225)
      ..quadraticBezierTo(57.4141951, 76.91759121, 59.88268315, 69.47822381)
      ..quadraticBezierTo(62.3511712, 62.0388564, 62.3511712, 51.70566729)
      ..lineTo(61.66229192, 51.70566729)
      ..quadraticBezierTo(59.33471643, 55.84935081, 55.64636388, 58.85795786)
      ..quadraticBezierTo(51.95801133, 61.86656491, 47.31332795, 63.5000333)
      ..quadraticBezierTo(42.66864457, 65.13350169, 37.41597594, 65.13350169)
      ..quadraticBezierTo(28.90158642, 65.13350169, 22.03892089, 61.04982475)
      ..quadraticBezierTo(15.17625536, 56.9661478, 11.19825387, 49.79818567)
      ..quadraticBezierTo(7.22025239, 42.63022355, 7.22025239, 33.46608585)
      ..quadraticBezierTo(7.22025239, 23.88186621, 11.63530536, 16.27162476)
      ..quadraticBezierTo(16.05035833, 8.66138331, 23.94761689, 4.26980183)
      ..quadraticBezierTo(31.84487544, -0.12177965, 42.34237692, 0.0034733)
      ..quadraticBezierTo(49.25979732, 0.04522428, 55.83670791, 2.46019574)
      ..quadraticBezierTo(62.4136185, 4.87516719, 67.68846062, 10.27526227)
      ..quadraticBezierTo(72.96330275, 15.67535734, 76.09324486, 24.72336392)
      ..quadraticBezierTo(79.22318697, 33.7713705, 79.22318697, 47.13921026)
      ..quadraticBezierTo(79.22318697, 59.65640659, 76.5772871, 69.44940504)
      ..quadraticBezierTo(73.93138724, 79.24240348, 68.95923377, 86.06592597)
      ..quadraticBezierTo(63.9870803, 92.88944846, 56.96396056, 96.44472423)
      ..quadraticBezierTo(49.94084082, 100.0, 41.25163548, 100.0)
      ..close()
      ..moveTo(42.06055182, 51.76837737)
      ..quadraticBezierTo(45.95637323, 51.76837737, 49.30031003, 50.26536588)
      ..quadraticBezierTo(52.64424683, 48.76235438, 55.12708454, 46.15165578)
      ..quadraticBezierTo(57.60992225, 43.54095718, 59.01769006, 40.15266145)
      ..quadraticBezierTo(60.42545787, 36.76436572, 60.42545787, 32.92856284)
      ..quadraticBezierTo(60.42545787, 27.90548878, 58.07048106, 23.66783568)
      ..quadraticBezierTo(55.71550424, 19.43018258, 51.63832924, 16.84296741)
      ..quadraticBezierTo(47.56115424, 14.25575225, 42.31105772, 14.25575225)
      ..quadraticBezierTo(37.16794659, 14.25575225, 33.06728816, 16.75946545)
      ..quadraticBezierTo(28.96662972, 19.26317865, 26.5790357, 23.54258273)
      ..quadraticBezierTo(24.19144167, 27.82198682, 24.19144167, 33.09556678)
      ..quadraticBezierTo(24.19144167, 38.32739575, 26.51640922, 42.56504885)
      ..quadraticBezierTo(28.84137677, 46.80270196, 32.86766702, 49.28553966)
      ..quadraticBezierTo(36.89395726, 51.76837737, 42.06055182, 51.76837737)
      ..close(),
    // colon.tf; 2 closed contour(s).
    ':': Path()
      ..moveTo(18.10646883, 99.70774312)
      ..quadraticBezierTo(13.70187151, 99.70774312, 10.66718503, 96.69654007)
      ..quadraticBezierTo(7.63249855, 93.68533702, 7.63249855, 89.30422315)
      ..quadraticBezierTo(7.63249855, 84.92310927, 10.66718503, 81.91190623)
      ..quadraticBezierTo(13.70187151, 78.90070318, 18.10646883, 78.90070318)
      ..quadraticBezierTo(22.51106614, 78.90070318, 25.54575262, 81.91190623)
      ..quadraticBezierTo(28.5804391, 84.92310927, 28.5804391, 89.30422315)
      ..quadraticBezierTo(28.5804391, 93.68533702, 25.54575262, 96.69654007)
      ..quadraticBezierTo(22.51106614, 99.70774312, 18.10646883, 99.70774312)
      ..close()
      ..moveTo(18.10646883, 49.84504504)
      ..quadraticBezierTo(13.70187151, 49.84504504, 10.66718503, 46.83384199)
      ..quadraticBezierTo(7.63249855, 43.82263895, 7.63249855, 39.44152507)
      ..quadraticBezierTo(7.63249855, 35.0604112, 10.66718503, 32.04920815)
      ..quadraticBezierTo(13.70187151, 29.0380051, 18.10646883, 29.0380051)
      ..quadraticBezierTo(22.51106614, 29.0380051, 25.54575262, 32.04920815)
      ..quadraticBezierTo(28.5804391, 35.0604112, 28.5804391, 39.44152507)
      ..quadraticBezierTo(28.5804391, 43.82263895, 25.54575262, 46.83384199)
      ..quadraticBezierTo(22.51106614, 49.84504504, 18.10646883, 49.84504504)
      ..close(),
    // hyphen.tf; 1 closed contour(s).
    '-': Path()
      ..moveTo(64.94475691, 51.11074564)
      ..lineTo(64.94475691, 65.13340613)
      ..lineTo(21.24817654, 65.13340613)
      ..lineTo(21.24817654, 51.11074564)
      ..close(),
  };
}
