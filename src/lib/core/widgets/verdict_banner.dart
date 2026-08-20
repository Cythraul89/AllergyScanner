import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../utils/formatters.dart';

/// Semantic colours for a verdict.
///
/// Colour never carries the verdict alone (R7.4, N9): every use of this class
/// shows the wording from [Formatters.verdictTitle] next to it, and the icon
/// differs per verdict as well.
class VerdictStyle {
  const VerdictStyle({
    required this.background,
    required this.foreground,
    required this.icon,
  });

  factory VerdictStyle.of(BuildContext context, ScanVerdict verdict) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    switch (verdict) {
      case ScanVerdict.hit:
        return VerdictStyle(
          background: colors.errorContainer,
          foreground: colors.onErrorContainer,
          icon: Icons.warning_amber_rounded,
        );
      case ScanVerdict.noMatch:
        // The one hardcoded colour the style guide allows: a semantic accent.
        return const VerdictStyle(
          background: Color(0xFFDCEFD9),
          foreground: Color(0xFF1B5E20),
          icon: Icons.check_circle_outline,
        );
      case ScanVerdict.unknown:
        return VerdictStyle(
          background: colors.surfaceContainerHighest,
          foreground: colors.onSurfaceVariant,
          icon: Icons.help_outline,
        );
    }
  }

  final Color background;
  final Color foreground;
  final IconData icon;
}

/// The headline of a result. [detail] carries the reason or the match count.
class VerdictBanner extends StatelessWidget {
  const VerdictBanner({required this.verdict, this.detail, super.key});

  final ScanVerdict verdict;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final VerdictStyle style = VerdictStyle.of(context, verdict);
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(style.icon, color: style.foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Formatters.verdictTitle(verdict),
                  style: text.titleMedium?.copyWith(
                    color: style.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    detail!,
                    style: text.bodyMedium?.copyWith(color: style.foreground),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact badge for a history row.
class VerdictBadge extends StatelessWidget {
  const VerdictBadge({required this.verdict, super.key});

  final ScanVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final VerdictStyle style = VerdictStyle.of(context, verdict);
    return Tooltip(
      message: Formatters.verdictLabel(verdict),
      child: CircleAvatar(
        radius: 16,
        backgroundColor: style.background,
        child: Icon(style.icon, size: 18, color: style.foreground),
      ),
    );
  }
}
