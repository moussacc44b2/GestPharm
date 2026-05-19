import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/beep_service.dart';
import '../services/api_service.dart';

class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key});

  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _scannerController;
  bool _isProcessing = false;
  String? _lastScannedCode;
  List<Map<String, dynamic>> _scannedHistory = [];
  late AnimationController _pulseController;
  Map<String, dynamic>? _activeScanAlert;
  
  // Track timestamps of scans in-memory to prevent duplicate scans with zero delay
  final Map<String, DateTime> _recentScans = {};

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final code = barcode.rawValue!;
    
    // 1. Instant local in-memory check to prevent duplicates (ignores same code within 2.5 seconds)
    final now = DateTime.now();
    if (_recentScans.containsKey(code)) {
      final lastScanTime = _recentScans[code]!;
      if (now.difference(lastScanTime).inMilliseconds < 2500) {
        return; // Ignore duplicate scan instantly with 0 latency
      }
    }
    _recentScans[code] = now;

    // 2. Immediate, light-speed auditory and tactile feedback (no network lag!)
    HapticFeedback.mediumImpact();
    BeepService.playSuccess();

    // Show temporary "Adding..." state instantly in the alert overlay
    setState(() {
      _activeScanAlert = {
        'success': true,
        'title': 'جاري الإضافة... / En cours',
        'message': 'يتم التحقق من المخزون والاتصال بالخادم...',
        'barcode': code,
      };
    });

    // Call single optimized API to add to cart in one fast background trip!
    final result = await ApiService.pushBarcodeToCart(code);

    if (!mounted) return;

    if (result['success'] == true) {
      final scanData = result['data'] ?? {};
      final inventoryItem = scanData['inventory_item'] ?? {};
      final medicine = inventoryItem['medicine'] ?? {};
      final medicineName = medicine['name'] ?? 'Unknown';
      final sellingPrice = inventoryItem['selling_price'] ?? '0.00';
      final stock = inventoryItem['quantity'] ?? 0;

      setState(() {
        _scannedHistory.insert(0, {
          'name': medicineName,
          'barcode': code,
          'price': sellingPrice,
          'stock': stock,
          'time': DateTime.now(),
        });
        
        _activeScanAlert = {
          'success': true,
          'title': 'تمت الإضافة للمبيعات! / Ajouté',
          'message': '$medicineName • ${double.tryParse(sellingPrice.toString())?.toStringAsFixed(2) ?? sellingPrice} DA',
          'barcode': code,
        };
      });
    } else {
      // Retroactive error handling: Play distinct error buzz and device vibration
      HapticFeedback.vibrate();
      BeepService.playError();

      final errMsg = result['message'] ?? '';
      String title = 'خطأ في المسح! / Erreur';
      String message = 'فشل إضافة المنتج للمبيعات';

      if (errMsg.contains('not found')) {
        title = 'المنتج غير مسجل! / Inexistant';
        message = 'الدواء غير موجود في قاعدة البيانات';
      } else if (errMsg.contains('no stock') || errMsg.contains('out of stock') || errMsg.contains('stock available')) {
        title = 'نفاد المخزون! / Hors Stock';
        message = 'الدواء مسجل ولكن لا تتوفر منه كمية بالمخزن';
      } else {
        message = errMsg;
      }

      setState(() {
        _activeScanAlert = {
          'success': false,
          'title': title,
          'message': message,
          'barcode': code,
        };
      });
    }

    // Auto-clear the alert overlay after 2.5 seconds (longer for errors so user reads it!)
    final currentAlert = _activeScanAlert;
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && _activeScanAlert == currentAlert) {
        setState(() => _activeScanAlert = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Scanner viewfinder
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Camera view
                    MobileScanner(
                      controller: _scannerController!,
                      onDetect: _onBarcodeDetected,
                    ),

                    // Scanning overlay
                    Center(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 280,
                            height: 150,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _isProcessing
                                    ? Colors.amber
                                    : Colors.white.withValues(
                                        alpha: 0.5 + _pulseController.value * 0.5,
                                      ),
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          );
                        },
                      ),
                    ),

                    // Status bar
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isProcessing
                                  ? Icons.hourglass_top_rounded
                                  : Icons.qr_code_scanner_rounded,
                              color: _isProcessing ? Colors.amber : Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _isProcessing
                                  ? 'Looking up medicine...'
                                  : 'Point camera at barcode',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            // Torch toggle
                            IconButton(
                              icon: const Icon(Icons.flash_on_rounded),
                              color: Colors.white,
                              iconSize: 22,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () =>
                                  _scannerController?.toggleTorch(),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Processing overlay
                    if (_isProcessing)
                      Container(
                        color: Colors.black26,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
                      ),

                    // Floating scan result overlay (non-blocking)
                    if (_activeScanAlert != null)
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: _activeScanAlert!['success'] == true
                                ? Colors.green.withOpacity(0.9)
                                : Colors.red.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _activeScanAlert!['success'] == true
                                    ? Icons.check_circle_rounded
                                    : Icons.error_outline_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _activeScanAlert!['title'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _activeScanAlert!['message'],
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _activeScanAlert!['barcode'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Scanned history
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.history_rounded,
                              color: colorScheme.onPrimaryContainer,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Sent to POS (${_scannedHistory.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          if (_scannedHistory.isNotEmpty)
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _scannedHistory.clear()),
                              icon: const Icon(Icons.clear_all, size: 18),
                              label: const Text('Clear'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _scannedHistory.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.qr_code_2_rounded,
                                    size: 48,
                                    color: colorScheme.onSurface
                                        .withValues(alpha: 0.2),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Scan a barcode to add to POS',
                                    style: TextStyle(
                                      color: colorScheme.onSurface
                                          .withValues(alpha: 0.4),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _scannedHistory.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final item = _scannedHistory[index];
                                return Card(
                                  elevation: 0,
                                  color: colorScheme.surface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: colorScheme.outline
                                          .withValues(alpha: 0.15),
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        color: Colors.green,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      item['name'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      item['barcode'],
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    trailing: Text(
                                      '${double.tryParse(item['price'].toString())?.toStringAsFixed(2) ?? item['price']} DA',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
