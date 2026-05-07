class OcrService {
  // Multilingual keyword maps for column detection
  static const List<String> _nameKeywords = [
    'designation', 'produit', 'article', 'description', 'medicine', 'nom',
    'الوصف', 'البيان', 'المنتج', 'اسم الدواء', 'بيان', 'دواء'
  ];

  static const List<String> _qtyKeywords = [
    'quantite', 'quantité', 'qte', 'qty', 'units', 'nombre',
    'الكمية', 'كمية', 'العدد', 'عدد', 'حصص'
  ];

  static const List<String> _skipKeywords = [
    'total', 'tax', 'tva', 'subtotal', 'invoice', 'facture', 'date', 'ref', 'tel', 'fax','prix','pu',
    'address', 'adresse', 'page', 'n°', 'no.', 'المجموع', 'الفاتورة', 'التاريخ', 'الهاتف'
  ];

  /// Extract structured product data from noisy OCR text.
  List<Map<String, dynamic>> parseInvoiceText(String rawText) {
    final List<Map<String, dynamic>> items = [];
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // Step 1: Detect Table Structure / Headers
    int headerIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      bool isHeader = _nameKeywords.any((k) => line.contains(k)) || 
                     _qtyKeywords.any((k) => line.contains(k));
      if (isHeader) {
        headerIndex = i;
        break;
      }
    }

    // Start parsing from header or beginning
    int scanIndex = headerIndex != -1 ? headerIndex + 1 : 0;
    
    String pendingName = "";
    int pendingQty = -1;
    double pendingPrice = 0.0;

    final priceRegex = RegExp(r'\b(\d{1,6}[.,]\d{2})\b');
    final qtyRegex = RegExp(r'(?:^|\s)(\d{1,3})(?:\s|$)');

    for (int i = scanIndex; i < lines.length; i++) {
      final line = lines[i];
      final lowerLine = line.toLowerCase();

      // Skip noise
      if (_skipKeywords.any((k) => lowerLine.contains(k)) && !lowerLine.contains(' ')) continue;

      final priceMatch = priceRegex.firstMatch(line);
      final qtyMatch = qtyRegex.firstMatch(line);

      // Heuristic: If line has a price, it's usually the end of a product row
      if (priceMatch != null) {
        pendingPrice = double.tryParse(priceMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        String remainingText = line.replaceFirst(priceMatch.group(0)!, ' ');

        // Try to catch quantity in the same line
        final lineQtyMatch = qtyRegex.firstMatch(remainingText);
        if (lineQtyMatch != null) {
          pendingQty = int.tryParse(lineQtyMatch.group(1)!) ?? 1;
          remainingText = remainingText.replaceFirst(lineQtyMatch.group(0)!, ' ');
        }

        pendingName += " " + remainingText;
        
        _commitItem(items, pendingName, pendingQty, pendingPrice);
        
        // Reset for next product
        pendingName = "";
        pendingQty = -1;
        pendingPrice = 0.0;
      } else {
        // No price found, could be a continuation of name or a line with just quantity
        if (qtyMatch != null && line.length < 10) {
          pendingQty = int.tryParse(qtyMatch.group(1)!) ?? 1;
          String nameFragment = line.replaceFirst(qtyMatch.group(0)!, ' ');
          if (nameFragment.trim().length > 2) pendingName += " " + nameFragment;
        } else if (line.length > 2) {
          // Likely part of the product name
          pendingName += " " + line;
        }
      }
    }

    // Catch trailing data
    if (pendingName.trim().isNotEmpty) {
      _commitItem(items, pendingName, pendingQty, pendingPrice);
    }

    return items;
  }

  void _commitItem(List<Map<String, dynamic>> items, String rawName, int qty, double price) {
    // Sanitize name: remove symbols, extra spaces, handle Arabic/French chars
    final cleanName = rawName
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s\u0600-\u06FF\-]'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    if (cleanName.length >= 3 && !_isLikelyNoise(cleanName)) {
      items.add({
        'name': cleanName,
        'quantity': qty == -1 ? 1 : qty,
        'price': price,
      });
    }
  }

  bool _isLikelyNoise(String text) {
    final lower = text.toLowerCase();
    if (_skipKeywords.any((k) => lower.contains(k))) return true;
    if (RegExp(r'^\d+$').hasMatch(text)) return true; // Only numbers
    return false;
  }
}
