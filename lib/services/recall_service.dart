import 'dart:convert';
import 'http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a food recall item from FDA/USDA or similar sources
class RecallItem {
  final String id; // Unique identifier (e.g., recall number or generated hash)
  final String productName;
  final String? brand;
  final String? reason; // e.g., "Listeria contamination"
  final String? datePublished;
  final String? description;
  final List<String> affectedBarcodes; // If available
  final List<String> affectedKeywords; // Product name keywords for fuzzy matching
  final DateTime addedAt; // When we added this to our list

  RecallItem({
    required this.id,
    required this.productName,
    this.brand,
    this.reason,
    this.datePublished,
    this.description,
    this.affectedBarcodes = const [],
    this.affectedKeywords = const [],
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'productName': productName,
        'brand': brand,
        'reason': reason,
        'datePublished': datePublished,
        'description': description,
        'affectedBarcodes': affectedBarcodes,
        'affectedKeywords': affectedKeywords,
        'addedAt': addedAt.millisecondsSinceEpoch,
      };

  static RecallItem fromJson(Map<String, dynamic> json) => RecallItem(
        id: json['id'] as String? ?? '',
        productName: json['productName'] as String? ?? '',
        brand: json['brand'] as String?,
        reason: json['reason'] as String?,
        datePublished: json['datePublished'] as String?,
        description: json['description'] as String?,
        affectedBarcodes: (json['affectedBarcodes'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        affectedKeywords: (json['affectedKeywords'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        addedAt: json['addedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int)
            : DateTime.now(),
      );
}

/// Service to manage food recall data and check scanned products against recalls
class RecallService {
  static const String _kRecallListKey = 'recalled_products_list';
  static const String _kRecallCacheKey = 'recall_cache_timestamp';
  static const Duration _cacheDuration = Duration(hours: 6); // Refresh recall data every 6 hours

  // FDA Food Recalls API endpoint (example - adjust based on actual API)
  // Note: This is a placeholder. In production, use official FDA/USDA APIs or scrape data responsibly.
  // For now, we'll use a mock/manual approach with local storage.
  static const String _fdaRecallsUrl = 'https://api.fda.gov/food/enforcement.json';

  /// Fetch recall data from FDA API (placeholder - requires real implementation)
  static Future<List<RecallItem>> fetchRecallsFromAPI() async {
    try {
      // Example API call structure (adjust query params as needed)
      final uri = Uri.parse('$_fdaRecallsUrl?limit=100');
      final resp = await SecureHttp.instance.get(uri, headers: {
        'User-Agent': 'GroceryGuardian/0.1 (+https://github.com/WoofahRayetCode/grocery_guardian)'
      }).timeout(const Duration(seconds: 10));
      
      if (resp.statusCode != 200) return [];
      
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = data['results'] as List?;
      if (results == null) return [];

      final recalls = <RecallItem>[];
      for (final item in results) {
        if (item is! Map) continue;
        
        final productDesc = item['product_description'] as String? ?? '';
        final reason = item['reason_for_recall'] as String? ?? '';
        final recallNumber = item['recall_number'] as String? ?? '';
        final reportDate = item['report_date'] as String? ?? '';
        
        // Extract keywords from product description
        final keywords = _extractKeywords(productDesc);
        
        recalls.add(RecallItem(
          id: recallNumber.isNotEmpty ? recallNumber : productDesc.hashCode.toString(),
          productName: productDesc,
          brand: null, // Extract from description if available
          reason: reason,
          datePublished: reportDate,
          description: productDesc,
          affectedBarcodes: const [], // Usually not provided by API
          affectedKeywords: keywords,
        ));
      }
      
      return recalls;
    } catch (e) {
      // Network error or parsing issue - return empty list
      return [];
    }
  }

  /// Extract searchable keywords from product description
  static List<String> _extractKeywords(String description) {
    final normalized = description.toLowerCase().trim();
    // Remove common filler words and split
    const stopWords = ['the', 'and', 'or', 'in', 'of', 'with', 'for', 'from', 'by', 'oz', 'lb', 'gram'];
    final words = normalized
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .toSet()
        .toList();
    return words;
  }

  /// Load recalled products from persistent storage
  static Future<List<RecallItem>> loadRecalledProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kRecallListKey);
      if (raw == null || raw.isEmpty) return [];
      
      final data = jsonDecode(raw) as List;
      return data.map((e) => RecallItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  /// Save recalled products to persistent storage
  static Future<void> saveRecalledProducts(List<RecallItem> recalls) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(recalls.map((e) => e.toJson()).toList());
      await prefs.setString(_kRecallListKey, encoded);
    } catch (_) {
      // Ignore save errors
    }
  }

  /// Add a new recall item to the list (deduplicate by ID)
  static Future<void> addRecallItem(RecallItem item) async {
    final current = await loadRecalledProducts();
    if (current.any((r) => r.id == item.id)) return; // Already exists
    
    current.add(item);
    await saveRecalledProducts(current);
  }

  /// Remove a recall item by ID
  static Future<void> removeRecallItem(String id) async {
    final current = await loadRecalledProducts();
    current.removeWhere((r) => r.id == id);
    await saveRecalledProducts(current);
  }

  /// Mark a recall as safe/resolved (remove from list)
  static Future<void> markRecallSafe(String id) async {
    await removeRecallItem(id);
  }

  /// Check if a product (by barcode or name) matches any active recalls
  /// Returns matching recall item if found, null otherwise
  static Future<RecallItem?> checkProduct({String? barcode, String? productName}) async {
    final recalls = await loadRecalledProducts();
    if (recalls.isEmpty) return null;

    // Check by barcode first (exact match)
    if (barcode != null && barcode.isNotEmpty) {
      for (final recall in recalls) {
        if (recall.affectedBarcodes.contains(barcode)) {
          return recall;
        }
      }
    }

    // Check by product name (fuzzy keyword matching)
    if (productName != null && productName.isNotEmpty) {
      final nameNormalized = productName.toLowerCase().trim();
      final nameKeywords = _extractKeywords(nameNormalized);
      
      for (final recall in recalls) {
        // Match if product name contains recall keywords or vice versa
        final recallNameLower = recall.productName.toLowerCase();
        if (recallNameLower.contains(nameNormalized) || nameNormalized.contains(recallNameLower)) {
          return recall;
        }
        
        // Or if keywords overlap significantly
        final matchingKeywords = nameKeywords.where((k) => recall.affectedKeywords.contains(k)).toList();
        if (matchingKeywords.length >= 2) {
          return recall;
        }
      }
    }

    return null;
  }

  /// Refresh recall data from API and merge with local list
  static Future<void> refreshRecallData() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRefresh = prefs.getInt(_kRecallCacheKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Check if cache is still valid
    if (lastRefresh != null && (now - lastRefresh) < _cacheDuration.inMilliseconds) {
      return; // No need to refresh
    }

    final apiRecalls = await fetchRecallsFromAPI();
    if (apiRecalls.isEmpty) return; // API failed or no new recalls

    final current = await loadRecalledProducts();
    final existingIds = current.map((r) => r.id).toSet();
    
    // Merge: add new recalls from API that aren't already in our list
    for (final recall in apiRecalls) {
      if (!existingIds.contains(recall.id)) {
        current.add(recall);
      }
    }
    
    await saveRecalledProducts(current);
    await prefs.setInt(_kRecallCacheKey, now);
  }

  /// Manually add a product to the recall list (for user-reported issues)
  static Future<void> addManualRecall({
    required String productName,
    String? brand,
    String? reason,
    List<String>? barcodes,
  }) async {
    final id = '${productName}_${DateTime.now().millisecondsSinceEpoch}';
    final keywords = _extractKeywords(productName);
    
    final item = RecallItem(
      id: id,
      productName: productName,
      brand: brand,
      reason: reason ?? 'User-reported issue',
      datePublished: DateTime.now().toString().split(' ')[0],
      description: 'Manually added by user',
      affectedBarcodes: barcodes ?? const [],
      affectedKeywords: keywords,
    );
    
    await addRecallItem(item);
  }

  /// Get count of active recalls
  static Future<int> getRecallCount() async {
    final recalls = await loadRecalledProducts();
    return recalls.length;
  }

  /// Clear all recall data
  static Future<void> clearAllRecalls() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRecallListKey);
    await prefs.remove(_kRecallCacheKey);
  }
}
