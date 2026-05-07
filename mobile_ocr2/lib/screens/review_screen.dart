import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ReviewScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;

  const ReviewScreen({super.key, required this.items});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late List<Map<String, dynamic>> _items;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Create mutable copies for editing
    _items = widget.items.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  double get _totalAmount {
    return _items.fold(0.0, (sum, item) {
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      return sum + (price * qty);
    });
  }

  Future<void> _sendToBackend() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items to send.')),
      );
      return;
    }

    setState(() => _isSending = true);

    final result = await ApiService.submitPurchase(
      items: _items,
      totalAmount: _totalAmount,
    );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (result['success'] == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
          title: const Text('Invoice Sent!', textAlign: TextAlign.center),
          content: const Text(
            'The invoice has been sent to GestPharm and is now available for review in the web interface.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // go back to scan screen
              },
              child: const Text('Scan Another'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to send'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Review (${_items.length} items)'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: colorScheme.onPrimaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Review extracted items. Edit quantities or prices if the OCR made a mistake. Remove any incorrect rows.',
                    style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          // Items List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return _ItemCard(
                  item: item,
                  onRemove: () => _removeItem(index),
                  onChanged: (key, value) {
                    setState(() => _items[index][key] = value);
                  },
                );
              },
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Estimated Total', style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '\$${_totalAmount.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: _isSending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_rounded),
                    label: Text(_isSending ? 'Sending...' : 'Send to GestPharm'),
                    onPressed: _isSending ? null : _sendToBackend,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onRemove;
  final void Function(String key, dynamic value) onChanged;

  const _ItemCard({required this.item, required this.onRemove, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onRemove,
                  color: colorScheme.error,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _editField(
                    context: context,
                    label: 'Qty',
                    value: item['quantity'].toString(),
                    isNumber: true,
                    onChanged: (v) => onChanged('quantity', int.tryParse(v) ?? 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _editField(
                    context: context,
                    label: 'Unit Price',
                    value: (item['price'] ?? 0.0).toString(),
                    isNumber: true,
                    onChanged: (v) => onChanged('price', double.tryParse(v) ?? 0.0),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _editField({
    required BuildContext context,
    required String label,
    required String value,
    required bool isNumber,
    required void Function(String) onChanged,
  }) {
    return TextFormField(
      initialValue: value,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }
}
