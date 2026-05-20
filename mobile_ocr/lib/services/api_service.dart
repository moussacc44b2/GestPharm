import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('backend_url') ?? 'http://10.0.2.2:8000/api';
  }

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // --- Auth ---
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final baseUrl = await _getBaseUrl();

    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    final body = jsonDecode(response.body);

    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', body['access_token']);
      return {'success': true};
    } else {
      return {'success': false, 'message': body['message'] ?? 'Login failed'};
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();

    if (token != null) {
      await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
    }

    await prefs.remove('auth_token');
  }

  // --- Purchases ---
  static Future<Map<String, dynamic>> submitPurchase({
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    String? invoiceNumber,
    int? supplierId,
  }) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();

    if (token == null) {
      return {'success': false, 'message': 'Not authenticated'};
    }

    final payload = {
      'total_amount': totalAmount,
      'items': items,
      'invoice_number': invoiceNumber,
      'supplier_id': supplierId,
    }..removeWhere((_, v) => v == null);

    final response = await http.post(
      Uri.parse('$baseUrl/purchases'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 201) {
      return {'success': true};
    } else {
      final body = jsonDecode(response.body);
      return {'success': false, 'message': body['message'] ?? 'Failed to submit'};
    }
  }

  // --- Suppliers ---
  static Future<List<dynamic>> fetchSuppliers() async {
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();

    if (token == null) {
      return [];
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/suppliers'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is List) {
          return body;
        } else if (body is Map && body.containsKey('data')) {
          return body['data'];
        }
      }
    } catch (e) {
      // Return empty list on network or parsing error
    }
    return [];
  }

  // --- Barcode Scanner ---
  static Future<Map<String, dynamic>> lookupBarcode(String barcode) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();

    if (token == null) {
      return {'success': false, 'message': 'Not authenticated'};
    }

    final response = await http.get(
      Uri.parse('$baseUrl/inventory/by-barcode/$barcode'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    final body = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {'success': true, 'data': body};
    } else {
      return {'success': false, 'message': body['message'] ?? 'Barcode not found'};
    }
  }

  static Future<Map<String, dynamic>> pushToCart(int inventoryItemId, {int quantity = 1}) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();

    if (token == null) {
      return {'success': false, 'message': 'Not authenticated'};
    }

    final response = await http.post(
      Uri.parse('$baseUrl/barcode-cart'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'inventory_item_id': inventoryItemId,
        'quantity': quantity,
      }),
    );

    if (response.statusCode == 201) {
      return {'success': true};
    } else {
      final body = jsonDecode(response.body);
      return {'success': false, 'message': body['message'] ?? 'Failed to add to cart'};
    }
  }

  static Future<Map<String, dynamic>> pushBarcodeToCart(String barcode, {int quantity = 1}) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();

    if (token == null) {
      return {'success': false, 'message': 'Not authenticated'};
    }

    final response = await http.post(
      Uri.parse('$baseUrl/barcode-cart'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'barcode': barcode,
        'quantity': quantity,
      }),
    );

    final body = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return {'success': true, 'data': body};
    } else {
      return {'success': false, 'message': body['message'] ?? 'Failed to add to cart'};
    }
  }
}
