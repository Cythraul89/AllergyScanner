import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/product.dart';
import '../../core/providers.dart';
import '../../core/utils/scan_capabilities.dart';
import 'result_providers.dart';

/// Correcting a product locally. The correction wins over remote data from now
/// on and is never overwritten by a later lookup (R4.4, R4.6).
class ProductEditScreen extends ConsumerStatefulWidget {
  const ProductEditScreen({
    required this.scanId,
    required this.barcode,
    super.key,
  });

  final String scanId;
  final String barcode;

  @override
  ConsumerState<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends ConsumerState<ProductEditScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandsController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _ingredientsController = TextEditingController();

  Product? _existing;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Read once into the controllers: a watched stream would fight the user's
    // typing on every database event.
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandsController.dispose();
    _quantityController.dispose();
    _ingredientsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final Product? product = await ref
        .read(productDaoProvider)
        .findByBarcode(widget.barcode);
    if (!mounted) return;
    setState(() {
      _existing = product;
      _nameController.text = product?.productName ?? '';
      _brandsController.text = product?.brands ?? '';
      _quantityController.text = product?.quantity ?? '';
      _ingredientsController.text = product?.ingredientsText ?? '';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ScanCapabilities capabilities = ref.watch(scanCapabilitiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Correct product data'),
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
                Text('Barcode ${widget.barcode}'),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _brandsController,
                        decoration: const InputDecoration(
                          labelText: 'Brand',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _quantityController,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ingredientsController,
                  minLines: 5,
                  maxLines: 14,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'Ingredient text',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (capabilities.canRecognizeText)
                  OutlinedButton.icon(
                    onPressed: () => context.go('/scan/text'),
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Scan an ingredient list instead'),
                  ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your corrections are kept on this device and are '
                            'never overwritten by a later lookup. Nothing is '
                            'sent to Open Food Facts.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    await ref.read(productActionsProvider).saveCorrection(
      scanId: widget.scanId,
      barcode: widget.barcode,
      existing: _existing,
      productName: _emptyToNull(_nameController.text),
      brands: _emptyToNull(_brandsController.text),
      quantity: _emptyToNull(_quantityController.text),
      ingredientsText: _emptyToNull(_ingredientsController.text),
    );

    if (!mounted) return;
    context.pop();
  }

  static String? _emptyToNull(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
