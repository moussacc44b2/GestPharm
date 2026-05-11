class OcrService {
  /// Parses raw OCR text block-by-block and extracts medicine items.
  List<Map<String, dynamic>> parseInvoiceText(String rawText) {
    final List<Map<String, dynamic>> items = [];
    final lines = rawText.split('\n');

    final skipKeywords = RegExp(
      r'total|tax|tva|subtotal|invoice|facture|date|ref|tel|fax|address|adresse|page|n°|no\.',
      caseSensitive: false,
    );

    for (String rawLine in lines) {
      final line = rawLine.trim();
      if (line.length < 5 || skipKeywords.hasMatch(line)) continue;

      // 1. Extract all potential numbers
      final numbers = _extractNumbers(line);
      if (numbers.isEmpty) continue;

      // 2. Identify Name, Quantity, and Price using heuristics/math
      final extraction = _processRow(line, numbers);
      
      if (extraction.name.length >= 3 && extraction.price > 0) {
        items.add({
          'name': extraction.name,
          'quantity': extraction.quantity,
          'price': extraction.price,
        });
      }
    }

    return items;
  }

  List<double> _extractNumbers(String line) {
    // Matches integers or decimals with . or ,
    final numberRegex = RegExp(r'\b\d+(?:[.,]\d{1,2})?\b');
    return numberRegex
        .allMatches(line)
        .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '.')) ?? 0.0)
        .where((n) => n > 0 && n < 1000000)
        .toList();
  }

  _RowExtraction _processRow(String line, List<double> numbers) {
    double price = 0;
    int quantity = 1;
    String namePart = line;

    if (numbers.length >= 3) {
      // Try to find A * B = C relationship to identify Qty, Price, Total
      bool foundMath = false;
      for (int i = 0; i < numbers.length; i++) {
        for (int j = 0; j < numbers.length; j++) {
          if (i == j) continue;
          for (int k = 0; k < numbers.length; k++) {
            if (k == i || k == j) continue;
            
            final a = numbers[i];
            final b = numbers[j];
            final total = numbers[k];

            if ((a * b - total).abs() < 0.5) {
              // Usually price > quantity
              if (a >= b) {
                price = a;
                quantity = b.round();
              } else {
                price = b;
                quantity = a.round();
              }
              foundMath = true;
              break;
            }
          }
          if (foundMath) break;
        }
        if (foundMath) break;
      }

      if (!foundMath) {
        // Fallback: assume largest is total, second largest is price
        final sorted = List<double>.from(numbers)..sort();
        price = sorted[sorted.length - 2];
        quantity = sorted[0].round();
      }
    } else if (numbers.length == 2) {
      final n1 = numbers[0];
      final n2 = numbers[1];
      // Heuristic: Price is usually larger or has decimals
      if (n1 > n2) {
        price = n1;
        quantity = n2.round();
      } else {
        price = n2;
        quantity = n1.round();
      }
    } else {
      price = numbers[0];
      quantity = 1;
    }

    // Remove all identified numbers from line to get name
    for (final n in numbers) {
      final pattern = n % 1 == 0 ? n.toInt().toString() : n.toString().replaceAll('.', '[.,]');
      namePart = namePart.replaceFirst(RegExp('\\b$pattern\\b'), '');
    }

    final cleanName = namePart
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s\u0600-\u06FF\-]'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    return _RowExtraction(cleanName, quantity, price);
  }
}

class _RowExtraction {
  final String name;
  final int quantity;
  final double price;
  _RowExtraction(this.name, this.quantity, this.price);
}
