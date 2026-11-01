import 'package:flutter/material.dart';

/// Editorial palette from the OpenDesign proclan-app prototype.
///
/// [dark] is the live theme. Screens read these getters during build, and the
/// shell rebuilds the tree after [apply].
class Red {
  static var dark = true;

  static void apply(bool value) {
    dark = value;
  }

  static Color get bg =>
      dark ? const Color(0xFF000000) : const Color(0xFFF4F4F5);
  static Color get surface =>
      dark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);
  static Color get surfaceWarm =>
      dark ? const Color(0xFF030303) : const Color(0xFFF0F0F1);
  static Color get fg =>
      dark ? const Color(0xFFFFFFFF) : const Color(0xFF09090B);
  static Color get fg2 =>
      dark ? const Color(0xFFE9ECF2) : const Color(0xFF27272A);
  static Color get muted =>
      dark ? const Color(0xFF8A919C) : const Color(0xFF52525B);
  static Color get meta =>
      dark ? const Color(0xFF7D848E) : const Color(0xFF6B6B74);
  static Color get border =>
      dark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);
  static Color get borderSoft =>
      dark ? const Color(0xFF232326) : const Color(0xFFECECEE);
  static Color get lineStrong =>
      dark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8);
  static Color get surfaceHover =>
      dark ? const Color(0xFF1F1F1F) : const Color(0xFFF7F7F8);
  static Color get accent =>
      dark ? const Color(0xFFFFFFFF) : const Color(0xFF09090B);
  static Color get accentOn =>
      dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  static Color get accentHover =>
      dark ? const Color(0xFFE9ECF2) : const Color(0xFF27272A);
  static Color get accentActive =>
      dark ? const Color(0xFFC9CCD1) : const Color(0xFF3F3F46);
  static Color get accentSoft =>
      dark ? const Color(0x14FFFFFF) : const Color(0x0D09090B);
  static Color get danger => const Color(0xFFDC2626);
  static Color get dangerFg =>
      dark ? const Color(0xFFFF6B74) : const Color(0xFFB91C1C);
  static Color get dangerSoft =>
      dark ? const Color(0x24DC2626) : const Color(0x0FDC2626);
  static Color get dangerLine =>
      dark ? const Color(0x52DC2626) : const Color(0x47DC2626);
  static Color get onDanger => const Color(0xFFFFFFFF);
  static Color get green =>
      dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
  static Color get greenSoft =>
      dark ? const Color(0x1F4ADE80) : const Color(0x1415803D);
  static Color get greenLine =>
      dark ? const Color(0x524ADE80) : const Color(0x3D15803D);
  static Color get scrim =>
      dark ? const Color(0xB8000000) : const Color(0x7309090B);

  static const ease = Cubic(0.2, 0, 0, 1);
  static const column = 960.0;
  static const articleColumn = 820.0;

  static const sansFallback = [
    'Inter',
    'DM Sans',
    'PingFang SC',
    'Hiragino Sans GB',
    'Heiti SC',
    'Noto Sans SC',
    'Microsoft YaHei',
    'sans-serif',
  ];

  static double gutter(double width) {
    final pad = width * 0.04;
    if (pad < 16) {
      return 16;
    }
    if (pad > 40) {
      return 40;
    }
    return pad;
  }

  static double em(double size, double factor) => size * factor;

  static TextStyle text({
    double size = 14,
    Color? color,
    double height = 1.5,
    double letterSpacing = 0,
    FontWeight weight = FontWeight.w400,
    bool tabular = false,
  }) {
    return TextStyle(
      fontFamily: 'PingFang SC',
      fontFamilyFallback: sansFallback,
      fontSize: size,
      height: height,
      letterSpacing: letterSpacing,
      fontWeight: weight,
      color: color ?? fg,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }
}

void showRedNotice(BuildContext context, String message) {
  final bottom = MediaQuery.paddingOf(context).bottom;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: Red.text(
          size: 11,
          color: Red.accentOn,
          height: 1.4,
          weight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
      backgroundColor: Red.accent,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      margin: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottom),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      duration: const Duration(milliseconds: 2200),
    ),
  );
}

/// Centers a column. Feed uses 960; article and account use 820.
class RedCenter extends StatelessWidget {
  const RedCenter({super.key, required this.child, this.maxWidth = Red.column});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

class MarkAvatar extends StatelessWidget {
  const MarkAvatar({
    super.key,
    required this.text,
    required this.size,
    required this.fontSize,
    this.radius = 4,
  });

  final String text;
  final double size;
  final double fontSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Red.surfaceWarm,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Red.border),
      ),
      child: Text(
        text,
        style: Red.text(
          size: fontSize,
          height: 1,
          weight: FontWeight.w600,
          color: Red.fg2,
        ),
      ),
    );
  }
}
