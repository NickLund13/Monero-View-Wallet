/// Colors, type and the few shared widgets from docs/design/DESIGN.md.
library;

import 'package:flutter/material.dart';

/// The color tokens, one set per theme. Read them with `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.card,
    required this.text,
    required this.sec,
    required this.muted,
    required this.border,
    required this.divider,
    required this.track,
    required this.btn2,
    required this.input,
    required this.ring,
    required this.chev,
    required this.accentText,
    required this.link,
    required this.green,
    required this.amber,
    required this.red,
    required this.noteBg,
    required this.noteText,
    required this.seg,
  });

  static const dark = AppColors(
    bg: Color(0xFF101113),
    card: Color(0xFF1C1D21),
    text: Color(0xFFECECEE),
    sec: Color(0xFFB9BBC1),
    muted: Color(0xFFA3A5AC),
    border: Color(0xFF2A2B30),
    divider: Color(0xFF1F2024),
    track: Color(0xFF24252A),
    btn2: Color(0xFF2A2B30),
    input: Color(0xFF141518),
    ring: Color(0xFF5A5C63),
    chev: Color(0xFF6B6D74),
    accentText: accent,
    link: Color(0xFFF58A4B),
    green: Color(0xFF4CC38A),
    amber: Color(0xFFF5B14B),
    red: Color(0xFFFF7A6B),
    noteBg: Color(0xFF2A2216),
    noteText: Color(0xFFF5C98B),
    seg: Color(0xFF4A4B52),
  );

  /// Orange text is the accent × 0.72, so it meets 4.5:1 on the pale
  /// background. Buttons keep the brighter [accent].
  static const light = AppColors(
    bg: Color(0xFFF4F4F1),
    card: Color(0xFFFFFFFF),
    text: Color(0xFF16171A),
    sec: Color(0xFF43454C),
    muted: Color(0xFF5C5E66),
    border: Color(0xFFE1E1E5),
    divider: Color(0xFFE4E4E8),
    track: Color(0xFFE1E1E5),
    btn2: Color(0xFFECECEF),
    input: Color(0xFFF4F4F1),
    ring: Color(0xFF9A9CA3),
    chev: Color(0xFF9A9CA3),
    accentText: Color(0xFFAE4B18),
    link: Color(0xFFAE4B18),
    green: Color(0xFF1E7A4C),
    amber: Color(0xFFB26A00),
    red: Color(0xFFC8372A),
    noteBg: Color(0xFFFFF0D9),
    noteText: Color(0xFF6B4300),
    seg: Color(0xFFFFFFFF),
  );

  /// Primary buttons, selected radios, progress fill: the same in both themes.
  static const accent = Color(0xFFF26822);

  /// Text on an [accent] button, in both themes.
  static const onAccent = Color(0xFF141414);

  final Color bg;
  final Color card;
  final Color text;
  final Color sec;
  final Color muted;
  final Color border;
  final Color divider;
  final Color track;
  final Color btn2;
  final Color input;
  final Color ring;
  final Color chev;
  final Color accentText;
  final Color link;
  final Color green;
  final Color amber;
  final Color red;
  final Color noteBg;
  final Color noteText;

  /// The selected option of a segmented control.
  final Color seg;

  /// The tokens only ever change as a whole theme.
  @override
  AppColors copyWith() => this;

  /// Blends the two themes while the app switches between them.
  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: mix(bg, other.bg),
      card: mix(card, other.card),
      text: mix(text, other.text),
      sec: mix(sec, other.sec),
      muted: mix(muted, other.muted),
      border: mix(border, other.border),
      divider: mix(divider, other.divider),
      track: mix(track, other.track),
      btn2: mix(btn2, other.btn2),
      input: mix(input, other.input),
      ring: mix(ring, other.ring),
      chev: mix(chev, other.chev),
      accentText: mix(accentText, other.accentText),
      link: mix(link, other.link),
      green: mix(green, other.green),
      amber: mix(amber, other.amber),
      red: mix(red, other.red),
      noteBg: mix(noteBg, other.noteBg),
      noteText: mix(noteText, other.noteText),
      seg: mix(seg, other.seg),
    );
  }
}

extension AppTheme on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;

  /// Body copy and row labels.
  TextStyle get body => TextStyle(fontSize: 15, height: 1.4, color: colors.sec);

  /// Captions and small print.
  TextStyle get caption =>
      TextStyle(fontSize: 13, height: 1.35, color: colors.muted);

  /// A full-width secondary button: `card` background, 48 tall.
  ButtonStyle get secondaryButton => FilledButton.styleFrom(
    backgroundColor: colors.card,
    foregroundColor: colors.text,
    disabledBackgroundColor: colors.card,
    disabledForegroundColor: colors.muted,
    minimumSize: const Size.fromHeight(48),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: const TextStyle(
      fontFamily: _sans,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ),
  );
}

/// Settings → Appearance. System, the default, follows the phone. main()
/// keeps the choice between launches.
final appearance = ValueNotifier(ThemeMode.system);

// Both typefaces are bundled with the app (pubspec.yaml, assets/fonts/).
const _sans = 'IBM Plex Sans';

/// For amounts, addresses, block heights and node hosts. Without a [color] it
/// takes the surrounding text color.
TextStyle mono({
  double size = 15,
  Color? color,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: 'IBM Plex Mono',
  fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
  fontSize: size,
  color: color,
  fontWeight: weight,
);

final darkTheme = _theme(Brightness.dark, AppColors.dark);
final lightTheme = _theme(Brightness.light, AppColors.light);

ThemeData _theme(Brightness brightness, AppColors c) => ThemeData(
  useMaterial3: true,
  brightness: brightness,
  fontFamily: _sans,
  scaffoldBackgroundColor: c.bg,
  extensions: [c],
  colorScheme:
      (brightness == Brightness.dark
              ? const ColorScheme.dark()
              : const ColorScheme.light())
          .copyWith(
            primary: AppColors.accent,
            onPrimary: AppColors.onAccent,
            surface: c.bg,
            onSurface: c.text,
            error: c.red,
          ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: c.input,
    hintStyle: TextStyle(color: c.chev),
    contentPadding: const EdgeInsets.all(12),
    border: _inputBorder(c.border),
    enabledBorder: _inputBorder(c.border),
    focusedBorder: _inputBorder(AppColors.accent),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.onAccent,
      disabledBackgroundColor: c.btn2,
      disabledForegroundColor: c.muted,
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(
        fontFamily: _sans,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: c.link,
      minimumSize: const Size(44, 44),
      textStyle: const TextStyle(fontFamily: _sans, fontSize: 15),
    ),
  ),
  progressIndicatorTheme: ProgressIndicatorThemeData(
    color: AppColors.accent,
    linearTrackColor: c.track,
  ),
);

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(10),
  borderSide: BorderSide(color: color),
);

/// One screen: a Back link when there is somewhere to go back to, a title,
/// scrolling content, and an optional area pinned to the bottom.
class Screen extends StatelessWidget {
  const Screen({
    super.key,
    this.title,
    required this.children,
    this.bottom,
    this.canGoBack = true,
  });

  final String? title;
  final List<Widget> children;
  final Widget? bottom;
  final bool canGoBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                if (Navigator.canPop(context))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: canGoBack
                          ? () => Navigator.maybePop(context)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Back'),
                    ),
                  ),
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ...children,
              ],
            ),
          ),
          if (bottom != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: bottom,
            ),
        ],
      ),
    ),
  );
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.color});

  final Widget child;

  /// `card` unless given.
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color ?? context.colors.card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

/// A card of "label ... value" rows with dividers between them.
class FactsCard extends StatelessWidget {
  const FactsCard(this.rows, {super.key});

  final List<(String, Widget)> rows;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        for (final (i, (label, value)) in rows.indexed)
          Container(
            constraints: const BoxConstraints(minHeight: 50),
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : Border(top: BorderSide(color: context.colors.border)),
            ),
            child: Row(
              children: [
                Text(label, style: context.body),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: value),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 13,
        letterSpacing: 0.52,
        color: context.colors.muted,
      ),
    ),
  );
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    margin: const EdgeInsets.only(right: 8),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// The amber notice used wherever the balance or privacy needs a warning.
class Note extends StatelessWidget {
  const Note(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      color: c.noteBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: c.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, height: 1.4, color: c.noteText),
            ),
          ),
        ],
      ),
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "8 Oct 2026"
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "09:05"
String formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "1 output", "3 outputs"
String plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// A switch with a title and a caption under it. Tapping anywhere on the row
/// flips it. A null [onChanged] shows the switch but locks it.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.caption,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String caption;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: c.green,
                inactiveThumbColor: c.muted,
                inactiveTrackColor: c.card,
                trackOutlineColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.transparent
                      : c.ring,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card that opens another screen: a title and a chevron.
class NavRow extends StatelessWidget {
  const NavRow(this.title, {super.key, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 15)),
                ),
                Icon(Icons.chevron_right, color: c.chev),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
