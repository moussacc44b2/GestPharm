import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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

  /// New method to parse table data using ML Kit structured text
  List<Map<String, dynamic>> parseTableData(RecognizedText recognizedText) {
    final List<TextLine> allLines = [];
    for (var block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }

    if (allLines.isEmpty) return [];

    // 1. Sort lines by Y-coordinate (top to bottom)
    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    // 2. Group into rows based on vertical proximity
    final List<List<TextLine>> rows = [];
    if (allLines.isNotEmpty) {
      List<TextLine> currentRow = [allLines[0]];
      for (int i = 1; i < allLines.length; i++) {
        final prev = currentRow.last;
        final curr = allLines[i];
        
        final prevCenterY = prev.boundingBox.top + prev.boundingBox.height / 2;
        final currCenterY = curr.boundingBox.top + curr.boundingBox.height / 2;
        
        // Tolerance: half the height of the previous line
        if ((currCenterY - prevCenterY).abs() < prev.boundingBox.height * 0.8) {
          currentRow.add(curr);
        } else {
          rows.add(currentRow);
          currentRow = [curr];
        }
      }
      rows.add(currentRow);
    }

    // 3. Parse each row
    final List<Map<String, dynamic>> items = [];
    for (var rowLines in rows) {
      // Sort elements within the row by X-coordinate (left to right)
      rowLines.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      
      final item = _parseRowFromStructuredLines(rowLines);
      if (item != null) {
        items.add(item);
      }
    }

    return items;
  }

  Map<String, dynamic>? _parseRowFromStructuredLines(List<TextLine> lines) {
    String name = "";
    final List<double> allNumbers = [];
    
    final skipKeywords = RegExp(
      r'total|tax|tva|subtotal|invoice|facture|date|ref|page|n°|no\.|prix|quantite|qty|unit|total|montant',
      caseSensitive: false,
    );

    for (var line in lines) {
      final text = line.text.trim();
      if (skipKeywords.hasMatch(text)) continue; // Don't return null, just skip this specific text

      final numbers = _extractNumbers(text);
      if (numbers.isEmpty) {
        // Build the product name from non-numeric parts
        if (text.length > 2) {
          name = name.isEmpty ? text : "$name $text";
        }
      } else {
        allNumbers.addAll(numbers);
      }
    }

    if (name.isEmpty || allNumbers.isEmpty) return null;

    double price = 0;
    int quantity = 1;

    if (allNumbers.length >= 3) {
      // Find A * B = C relationship
      bool foundMath = false;
      for (int i = 0; i < allNumbers.length; i++) {
        for (int j = 0; j < allNumbers.length; j++) {
          if (i == j) continue;
          for (int k = 0; k < allNumbers.length; k++) {
            if (k == i || k == j) continue;
            
            final a = allNumbers[i];
            final b = allNumbers[j];
            final total = allNumbers[k];

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
        final sorted = List<double>.from(allNumbers)..sort();
        // If no math, assume largest is total, second largest is price
        price = sorted[sorted.length - 2];
        quantity = sorted[0].round();
      }
    } else if (allNumbers.length == 2) {
      final n1 = allNumbers[0];
      final n2 = allNumbers[1];
      // Heuristic: Price is usually larger or has decimals
      if (n1 > n2 || n1.toString().contains('.')) {
        price = n1;
        quantity = n2.round();
      } else {
        price = n2;
        quantity = n1.round();
      }
    } else {
      price = allNumbers[0];
      quantity = 1;
    }

    // Clean up name: remove any leftover numbers that might have been part of the text
    for (final n in allNumbers) {
      final pattern = n % 1 == 0 ? n.toInt().toString() : n.toString().replaceAll('.', '[.,]');
      name = name.replaceFirst(RegExp('\\b$pattern\\b'), '').trim();
    }

    if (name.length < 2 || price == 0) return null;

    return {
      'name': name.replaceAll(RegExp(r'\s+'), ' '),
      'quantity': quantity,
      'price': price,
    };
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
