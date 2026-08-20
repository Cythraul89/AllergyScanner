import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';

/// Takes a photo of an ingredient list and recognises it on the device.
///
/// The system camera UI is used instead of an in-app preview with frame
/// streaming: a sharp still recognises better and needs none of the
/// `InputImage` rotation handling (doc/ARCHITECTURE.md §5.4). Registered only
/// where `ScanCapabilities.canRecognizeText` is true.
class TextCaptureScreen extends ConsumerStatefulWidget {
  const TextCaptureScreen({super.key});

  @override
  ConsumerState<TextCaptureScreen> createState() => _TextCaptureScreenState();
}

class _TextCaptureScreenState extends ConsumerState<TextCaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan ingredient list')),
      body: _busy
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Recognising text…'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: <Widget>[
                Text(
                  'Take a photo of the ingredient list.',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                const Text('For a good result:'),
                const SizedBox(height: 8),
                const Text('•  fill the frame with the list'),
                const Text('•  hold the camera parallel to the pack'),
                const Text('•  avoid glare and shadows'),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => _capture(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Take photo'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _capture(ImageSource.gallery),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Pick an image'),
                ),
                const SizedBox(height: 24),
                Text(
                  'You can correct the recognised text before it is checked. '
                  'The photo is deleted right after recognition and is never '
                  'uploaded.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
    );
  }

  Future<void> _capture(ImageSource source) async {
    final XFile? photo = await _picker.pickImage(source: source);
    if (photo == null || !mounted) return;

    setState(() => _busy = true);

    final String text = await ref
        .read(textRecognitionServiceProvider)
        .recognizeFile(photo.path);

    if (!mounted) return;
    setState(() => _busy = false);

    // An empty result goes to the review screen with a hint, not to an error
    // dialog — the user can still type what they see.
    context.go('/scan/review', extra: text);
  }
}
