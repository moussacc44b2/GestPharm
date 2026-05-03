class OcrService {
  /// Parses raw OCR text block-by-block and extracts medicine items.
  List<Map<String, dynamic>> parseInvoiceText(String rawText) {
    final List<Map<String, dynamic>> items = [];
    final lines = rawText.split('\n');

    // Regex patterns
    final priceRegex = RegExp(r'\b(\d{1,6}[.,]\d{2})\b');
    final qtyRegex = RegExp(r'(?:^|\s)(\d{1,4})(?:\s|$)');
    // Skip lines that are likely headers/footers
    final skipKeywords = RegExp(
      r'total|tax|tva|subtotal|invoice|facture|date|ref|tel|fax|address|adresse|page|n°|no\.',
      caseSensitive: false,
    );

    for (String rawLine in lines) {
      final line = rawLine.trim();
      if (line.length < 4) continue;
      if (skipKeywords.hasMatch(line)) continue;

      // 1. Extract price
      double price = 0;
      String processedLine = line;
      final priceMatch = priceRegex.firstMatch(line);
      if (priceMatch != null) {
        price = double.tryParse(priceMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        processedLine = processedLine.replaceFirst(priceMatch.group(0)!, ' ');
      }

      // 2. Extract quantity (look for standalone number)
      int quantity = 1;
      final qtyMatch = qtyRegex.firstMatch(processedLine);
      if (qtyMatch != null) {
        final parsed = int.tryParse(qtyMatch.group(1)!);
        if (parsed != null && parsed > 0 && parsed < 10000) {
          quantity = parsed;
          processedLine = processedLine.replaceFirst(qtyMatch.group(0)!, ' ');
        }
      }

      // 3. Extract name (remaining meaningful text)
      final name = processedLine
          .replaceAll(RegExp(r'[^a-zA-Z0-9\s\u0600-\u06FF\-]'), ' ')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();

      if (name.length >= 3) {
        items.add({
          'name': name,
          'quantity': quantity,
          'price': price,
        });
      }
    }

    return items;
  }
}
