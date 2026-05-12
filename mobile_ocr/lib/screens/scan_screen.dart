import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../services/ocr_service.dart';
import '../services/api_service.dart';
import 'review_screen.dart';
import 'login_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isProcessing = false;
  final _picker = ImagePicker();
  final _ocrService = OcrService();
  String _statusMessage = 'Ready to scan';
  List<Map<String, dynamic>> _scannedItems = [];
  bool _isTableMode = false;

  Future<void> _pickAndScan(ImageSource source) async {
    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 2048,
    );
    if (image == null) return;

    final croppedFile = await _cropImage(image.path);
    if (croppedFile == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Analyzing invoice with AI...';
      _scannedItems = [];
    });

    try {
      // Run ML Kit OCR
      // Debug only (avoid_print can be enforced by lints)
      // ignore: avoid_print
      print('try');
      final inputImage = InputImage.fromFilePath(croppedFile.path);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await recognizer.processImage(inputImage);
      // ignore: avoid_print
      print('Running OCR on image: ${recognized.text}');

      recognizer.close();

      final rawText = recognized.text;
      print('OCR Raw Text: $rawText');

      if (rawText.trim().isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'No text found. Try a clearer image.';
        });
        // print('empty ocr result');
        return;
      }

      setState(() => _statusMessage = 'Extracting medicines...');

      // Parse the OCR text
      final List<Map<String, dynamic>> items;
      if (_isTableMode) {
        items = _ocrService.parseTableData(recognized);
      } else {
        items = _ocrService.parseInvoiceText(rawText);
      }
      print('Parsed Items: $items');

      setState(() {
        _isProcessing = false;
        _statusMessage = 'Ready to scan';
        _isTableMode = false; // Reset for next scan
        _scannedItems = items;
      });

      if (!mounted) return;

      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not extract any items. Please try again with a clearer image.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // We still offer to navigate to review screen via a button in the UI
      // or we can keep the automatic navigation if preferred, but since the user
      // asked to "display the list items" here, I'll let them see it first.
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error: ${e.toString()}';
      });
    }
  }

  Future<CroppedFile?> _cropImage(String path) async {
    return await ImageCropper().cropImage(
      sourcePath: path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Adjust Invoice',
          toolbarColor: Theme.of(context).colorScheme.primary,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(
          title: 'Adjust Invoice',
        ),
      ],
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.logout();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            onLogin: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              );
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GestPharm Scanner',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Hero Card
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: _isProcessing
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(strokeWidth: 3),
                            const SizedBox(height: 24),
                            Text(
                              _statusMessage,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                            ),
                          ],
                        )
                      : _scannedItems.isNotEmpty
                          ? Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Detected Items (${_scannedItems.length})',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => setState(() => _scannedItems = []),
                                        icon: const Icon(Icons.clear_all, size: 18),
                                        label: const Text('Clear'),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: ListView.separated(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: _scannedItems.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final item = _scannedItems[index];
                                      return Card(
                                        elevation: 0,
                                        color: colorScheme.surface,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(
                                            color: colorScheme.outline.withValues(alpha: 0.2),
                                          ),
                                        ),
                                        child: ListTile(
                                          title: Text(
                                            item['name'] ?? 'Unknown',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          trailing: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                'Qty: ${item['quantity']}',
                                                style: TextStyle(
                                                  color: colorScheme.primary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                '\$${(item['price'] ?? 0.0).toStringAsFixed(2)}',
                                                style: Theme.of(context).textTheme.labelSmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ReviewScreen(items: _scannedItems),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.rate_review),
                                      label: const Text('Review & Submit'),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.document_scanner_rounded,
                                    size: 64,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Scan Invoice',
                                  style: Theme.of(context).textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                  ),
                                  child: Text(
                                    'Take a photo or upload an invoice to automatically extract medicines and quantities.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyMedium
                                        ?.copyWith(
                                          color: colorScheme.onSurface.withValues(
                                            alpha: 0.6,
                                          ),
                                        ),
                                  ),
                                ),
                              ],
                            ),
                ),
              ),
              const SizedBox(height: 16),

              // Table Mode Toggle
              if (!_isProcessing && _scannedItems.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.table_chart_outlined,
                        size: 20,
                        color: _isTableMode ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Table Selection Mode',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Switch(
                        value: _isTableMode,
                        onChanged: (val) => setState(() => _isTableMode = val),
                      ),
                    ],
                  ),
                ),
              if (_isTableMode && !_isProcessing && _scannedItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 0),
                  child: Text(
                    'Tip: Crop specifically to the table data area for better results.',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_library_outlined),
                      label: Text(_isTableMode ? 'Gallery (Table)' : 'Gallery'),
                      onPressed: _isProcessing
                          ? null
                          : () => _pickAndScan(ImageSource.gallery),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.camera_alt_rounded),
                      label: Text(
                        _isProcessing 
                            ? 'Processing...' 
                            : (_isTableMode ? 'Scan Table' : 'Take Photo'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isProcessing
                          ? null
                          : () => _pickAndScan(ImageSource.camera),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
