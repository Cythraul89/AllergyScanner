import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';

/// Shown once, before anything else, and reachable again from About.
///
/// This is a functional requirement, not a formality (REQUIREMENTS §1.3): the
/// app matches text against unverified data and must not be mistaken for a
/// safety assessment.
class DisclaimerScreen extends ConsumerWidget {
  const DisclaimerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.appTitle, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  Text(
                    l10n.disclaimerIntro,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  _Bullet(l10n.disclaimerBulletOffData),
                  _Bullet(l10n.disclaimerBulletRecognition),
                  _Bullet(l10n.disclaimerBulletExactWords),
                  const SizedBox(height: 16),
                  Text(
                    l10n.disclaimerReadPackaging,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _acknowledge(ref),
                      child: Text(l10n.disclaimerAcknowledge),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _acknowledge(WidgetRef ref) {
    return ref
        .read(settingsDaoProvider)
        .acknowledgeDisclaimer(DateTime.now().toUtc());
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
