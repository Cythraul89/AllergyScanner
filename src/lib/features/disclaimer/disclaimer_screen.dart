import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

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
                  Text('AllergyScanner', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  Text(
                    'This app matches text against terms you enter. It does '
                    'not decide whether a product is safe for you to eat.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  const _Bullet(
                    'Product data comes from Open Food Facts and is not '
                    'verified.',
                  ),
                  const _Bullet(
                    'Recognised text can be incomplete or wrong.',
                  ),
                  const _Bullet(
                    'Only the exact words you list are found — not their '
                    'synonyms, Latin names or E-numbers.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Always read the packaging.',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _acknowledge(ref),
                      child: const Text('I understand'),
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
