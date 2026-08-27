import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/scan.dart';
import '../../core/providers.dart';
import 'result_providers.dart';

/// Attaching a name, a shop and a photo to a scan after the fact.
///
/// Separate from the OCR capture photo, which is never stored (N10) — this
/// photo is opt-in, stays on-device until removed, and only leaves the
/// device inside a backup archive the user explicitly exports (N10a).
class ScanDetailsEditScreen extends ConsumerStatefulWidget {
  const ScanDetailsEditScreen({required this.scanId, super.key});

  final String scanId;

  @override
  ConsumerState<ScanDetailsEditScreen> createState() =>
      _ScanDetailsEditScreenState();
}

class _ScanDetailsEditScreenState
    extends ConsumerState<ScanDetailsEditScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _shopController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String? _existingPhotoPath;
  String? _newPhotoSourcePath;
  bool _removePhoto = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shopController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ScanResult? result = await ref
        .read(scanDaoProvider)
        .findResult(widget.scanId);
    final Scan? scan = result?.scan;
    if (!mounted) return;
    setState(() {
      _nameController.text = scan?.name ?? '';
      _shopController.text = scan?.shop ?? '';
      _existingPhotoPath = scan?.photoPath;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit details'),
        actions: <Widget>[
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _shopController,
                  decoration: const InputDecoration(
                    labelText: 'Shop (optional)',
                    border: OutlineInputBorder(),
                    helperText: 'Scans at the same shop are grouped together',
                  ),
                ),
                const SizedBox(height: 16),
                _buildPhotoSection(),
              ],
            ),
    );
  }

  Widget _buildPhotoSection() {
    if (_newPhotoSourcePath != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Image.file(File(_newPhotoSourcePath!), height: 160, fit: BoxFit.cover),
          const SizedBox(height: 8),
          _photoActionButtons(hasPhoto: true),
        ],
      );
    }
    if (_existingPhotoPath != null && !_removePhoto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FutureBuilder<File>(
            future: ref.read(scanPhotoServiceProvider).resolve(_existingPhotoPath!),
            builder: (BuildContext context, AsyncSnapshot<File> snapshot) {
              final File? file = snapshot.data;
              if (file == null) return const SizedBox(height: 160);
              return Image.file(file, height: 160, fit: BoxFit.cover);
            },
          ),
          const SizedBox(height: 8),
          _photoActionButtons(hasPhoto: true),
        ],
      );
    }
    return _photoActionButtons(hasPhoto: false);
  }

  Widget _photoActionButtons({required bool hasPhoto}) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: () => _pickPhoto(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(hasPhoto ? 'Retake photo' : 'Take photo'),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickPhoto(ImageSource.gallery),
          icon: const Icon(Icons.image_outlined),
          label: const Text('Pick an image'),
        ),
        if (hasPhoto)
          TextButton.icon(
            onPressed: () => setState(() {
              _newPhotoSourcePath = null;
              _removePhoto = true;
            }),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove photo'),
          ),
      ],
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    // Compressed on capture: kMaxScanHistory (500) entries could otherwise
    // mean hundreds of multi-MB photos, both on disk and in an in-memory
    // backup archive.
    final XFile? photo = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (photo == null || !mounted) return;
    setState(() {
      _newPhotoSourcePath = photo.path;
      _removePhoto = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(scanDetailsActionsProvider)
        .save(
          scanId: widget.scanId,
          existingPhotoPath: _existingPhotoPath,
          name: _emptyToNull(_nameController.text),
          shop: _emptyToNull(_shopController.text),
          newPhotoSourcePath: _newPhotoSourcePath,
          removePhoto: _removePhoto,
        );
    if (!mounted) return;
    context.pop();
  }

  static String? _emptyToNull(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
