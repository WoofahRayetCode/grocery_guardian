import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ScannedProduct {
  final String barcode;
  final String? name;
  final String? brand;
  final List<String> allergens; // standardized allergen tags
  final String? ingredientsText;
  final Map<String, dynamic> nutriments; // calories, fat, etc.
  final String? nutriScore;
  final String? imageUrl;
  final String? productType; // e.g., Food, Personal care
  final String? source; // 'off' | 'obf'
  final String? usageHint; // e.g., Leave-on / Rinse-off (cosmetics)
  final List<String> babyCautions; // e.g., Honey for <1y, fragrance on infant skin
  final List<String> maternityCautions; // e.g., Retinoids, high-salicylates
  final List<String> babyRecommendations; // e.g., Formula type info

  ScannedProduct({
    required this.barcode,
    this.name,
    this.brand,
    required this.allergens,
    this.ingredientsText,
    required this.nutriments,
    this.nutriScore,
    this.imageUrl,
    this.productType,
    this.source,
  this.usageHint,
  this.babyCautions = const [],
  this.maternityCautions = const [],
  this.babyRecommendations = const [],
  });

  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        'name': name,
        'brand': brand,
        'allergens': allergens,
        'ingredientsText': ingredientsText,
        'nutriments': nutriments,
        'nutriScore': nutriScore,
        'imageUrl': imageUrl,
        'productType': productType,
        'source': source,
  'usageHint': usageHint,
  'babyCautions': babyCautions,
  'maternityCautions': maternityCautions,
  'babyRecommendations': babyRecommendations,
      };

  static ScannedProduct fromJson(Map<String, dynamic> json) => ScannedProduct(
        barcode: json['barcode'] as String? ?? '',
        name: json['name'] as String?,
        brand: json['brand'] as String?,
        allergens: (json['allergens'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        ingredientsText: json['ingredientsText'] as String?,
        nutriments: Map<String, dynamic>.from(json['nutriments'] as Map? ?? {}),
        nutriScore: json['nutriScore'] as String?,
        imageUrl: json['imageUrl'] as String?,
        productType: json['productType'] as String?,
        source: json['source'] as String?,
  usageHint: json['usageHint'] as String?,
  babyCautions: (json['babyCautions'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  maternityCautions: (json['maternityCautions'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  babyRecommendations: (json['babyRecommendations'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

class OpenFoodFactsService {
  static const String _base = 'https://world.openfoodfacts.org/api/v2/product';
  static const String _searchBase = 'https://world.openfoodfacts.org/cgi/search.pl';
  static const String _cachePrefixBarcode = 'off_cache_barcode_';
  static const String _cachePrefixSearch = 'off_cache_search_';
  static const Duration _ttl = Duration(days: 7);

  // Fetch product by barcode using OFF v2 API
  static Future<ScannedProduct?> fetchByBarcode(String barcode) async {
    final cacheKey = '$_cachePrefixBarcode$barcode';
    final cached = await _readCache(cacheKey);
    if (cached != null) return cached;
    try {
      final uri = Uri.parse('$_base/$barcode.json');
      final resp = await http.get(uri, headers: {
        'User-Agent': 'GroceryGuardian/0.1 (+https://github.com/WoofahRayetCode/grocery_guardian)'
      });
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map) return null;
      final product = data['product'];
      if (product == null) return null;

  final parsed = _parseProduct(product, fallbackBarcode: barcode);
      if (parsed != null) {
        await _writeCache(cacheKey, parsed);
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  // Simple search by name (first match). Note: OpenFoodFacts search is best-effort.
  static Future<ScannedProduct?> searchByName(String name) async {
    final cacheKey = '$_cachePrefixSearch${name.toLowerCase()}';
    final cached = await _readCache(cacheKey);
    if (cached != null) return cached;
    try {
      final params = {
        'search_terms': name,
        'search_simple': '1',
        'json': '1',
        'page_size': '1',
        'fields': [
          'code',
          'product_name',
          'brands',
          'allergens_tags',
          'ingredients_text',
          'nutriments',
          'nutriscore_grade',
          'image_front_url',
          'categories_tags',
        ].join(','),
      };
      final uri = Uri.parse(_searchBase).replace(queryParameters: params);
      final resp = await http.get(uri, headers: {
        'User-Agent': 'GroceryGuardian/0.1 (+https://github.com/WoofahRayetCode/grocery_guardian)'
      });
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map) return null;
      final products = data['products'];
      if (products is! List || products.isEmpty) return null;
      final product = products.first as Map;
      final parsed = _parseProduct(product);
      if (parsed != null) {
        await _writeCache(cacheKey, parsed);
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  static ScannedProduct? _parseProduct(Map product, {String? fallbackBarcode}) {
    final code = (product['code'] as String?) ?? fallbackBarcode ?? '';
    final productName = (product['product_name'] as String?)?.trim();
    final brand = (product['brands'] as String?)?.split(',').first.trim();
  final allergens = _extractAllergens(product);
  final ingredientsText = (product['ingredients_text'] as String?)?.trim();
  final categoriesTags = (product['categories_tags'] is List)
    ? (product['categories_tags'] as List).whereType<String>().toList()
    : const <String>[];
  final nutriments = Map<String, dynamic>.from(product['nutriments'] ?? const {});
  final nutriScore = product['nutriscore_grade'] as String?;
  final imageUrl = product['image_front_url'] as String?;
    final babyCautions = _inferFoodBabyCautions(
      name: productName,
      ingredientsText: ingredientsText,
      categoriesTags: categoriesTags,
    );
    final maternityCautions = _inferFoodMaternityCautions(
      name: productName,
      ingredientsText: ingredientsText,
      categoriesTags: categoriesTags,
    );
    final babyRecommendations = _inferFoodBabyRecommendations(
      name: productName,
      ingredientsText: ingredientsText,
      categoriesTags: categoriesTags,
    );
    return ScannedProduct(
      barcode: code,
      name: productName,
      brand: brand,
      allergens: allergens,
      ingredientsText: ingredientsText,
      nutriments: nutriments,
      nutriScore: nutriScore,
      imageUrl: imageUrl,
      productType: 'Food',
      source: 'off',
  usageHint: null,
      babyCautions: babyCautions,
      maternityCautions: maternityCautions,
  babyRecommendations: babyRecommendations,
    );
  }

  static List<String> _inferFoodBabyCautions({String? name, String? ingredientsText, List<String>? categoriesTags}) {
    final t = (ingredientsText ?? '').toLowerCase();
    final cautions = <String>[];
    if (t.contains('honey')) {
      cautions.add('Infants under 1 year: avoid honey');
    }
    return cautions;
  }

  static List<String> _inferFoodMaternityCautions({String? name, String? ingredientsText, List<String>? categoriesTags}) {
    final n = (name ?? '').toLowerCase();
    final t = (ingredientsText ?? '').toLowerCase();
    final cats = (categoriesTags ?? const <String>[]).map((e) => e.toLowerCase()).toList();
    final cautions = <String>[];
    // High-mercury fish names
    const mercuryFish = ['swordfish', 'king mackerel', 'tilefish', 'shark', 'marlin', 'bigeye tuna'];
    if (mercuryFish.any((k) => n.contains(k) || cats.any((c) => c.contains(k)))) {
      cautions.add('High-mercury fish: limit/avoid during pregnancy and breastfeeding');
    }
    // Unpasteurized foods
    if (t.contains('unpasteurized') || t.contains('unpasteurised') || t.contains('raw milk')) {
      cautions.add('Unpasteurized: avoid during pregnancy');
    }
    // Liver products (vitamin A)
    if (n.contains('liver') || n.contains('pâté') || n.contains('pate') || t.contains('liver')) {
      cautions.add('Liver: high vitamin A — avoid in pregnancy');
    }
    // Raw fish (sushi)
    if ((n.contains('sushi') || (n.contains('raw') && n.contains('fish'))) || cats.any((c) => c.contains('sushi'))) {
      cautions.add('Raw fish: avoid during pregnancy');
    }
    return cautions;
  }

  static List<String> _inferFoodBabyRecommendations({String? name, String? ingredientsText, List<String>? categoriesTags}) {
    final n = (name ?? '').toLowerCase();
    final t = (ingredientsText ?? '').toLowerCase();
    final cats = (categoriesTags ?? const <String>[]).map((e) => e.toLowerCase()).toList();
    final recs = <String>[];
    final isFormula = n.contains('infant formula') || n.contains('baby formula') || n.contains('follow-on formula') || n.contains('toddler formula') || n.contains('baby milk') || cats.any((c) => c.contains('infant-formula') || c.contains('baby-food') || c.contains('follow-on-formula'));
    if (isFormula) {
      final soy = n.contains('soy') || t.contains('soya') || t.contains('soy');
      final milk = n.contains('milk') || t.contains('milk') || t.contains('casein') || t.contains('whey') || t.contains('lactose');
      final hypo = n.contains('hypoallergenic') || t.contains('hypoallergenic') || t.contains('hydrolyzed') || t.contains('hydrolysed') || n.contains('ha');
      final iron = n.contains('iron') || t.contains('iron') || t.contains('ferrous');
      if (milk) recs.add('Cow’s milk-based formula');
      if (soy) recs.add('Soy-based formula');
      if (hypo) recs.add('Hypoallergenic/partially hydrolyzed');
      if (iron) recs.add('Iron-fortified');
    }
    return recs;
  }

  static Future<ScannedProduct?> _readCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final ts = DateTime.fromMillisecondsSinceEpoch(decoded['ts'] as int);
      if (DateTime.now().difference(ts) > _ttl) {
        // expired
        await prefs.remove(key);
        return null;
      }
      final prod = ScannedProduct.fromJson(Map<String, dynamic>.from(decoded['data'] as Map));
      return prod;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String key, ScannedProduct product) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'data': product.toJson(),
      });
      await prefs.setString(key, payload);
    } catch (_) {
      // ignore
    }
  }

  static List<String> _extractAllergens(Map product) {
    // OFF exposes 'allergens_tags' like "en:milk", "en:gluten", "en:peanuts"
    final raw = product['allergens_tags'];
    if (raw is List) {
      return raw
          .whereType<String>()
          .map((e) => e.contains(':') ? e.split(':').last : e)
          .map((e) => e.replaceAll('-', ' '))
          .map((e) => _capitalize(e))
          .toList();
    }
    return const [];
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  static Future<int> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      int removed = 0;
      for (final k in keys) {
        if (k.startsWith(_cachePrefixBarcode) || k.startsWith(_cachePrefixSearch)) {
          await prefs.remove(k);
          removed++;
        }
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> cacheEntryCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      int count = 0;
      for (final k in keys) {
        if (k.startsWith(_cachePrefixBarcode) || k.startsWith(_cachePrefixSearch)) {
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Test helper to construct a ScannedProduct using parser heuristics.
  /// Not intended for production use beyond unit tests.
  static ScannedProduct debugParseProduct(Map product) {
    return _parseProduct(product, fallbackBarcode: product['code'] as String? ?? 'debug')!;
  }
}

// Open Beauty Facts (cosmetics & personal care) integration
class OpenBeautyFactsService {
  static const String _base = 'https://world.openbeautyfacts.org/api/v2/product';
  static const String _searchBase = 'https://world.openbeautyfacts.org/cgi/search.pl';
  static const String _cachePrefixBarcode = 'obf_cache_barcode_';
  static const String _cachePrefixSearch = 'obf_cache_search_';
  static const Duration _ttl = Duration(days: 7);

  static Future<ScannedProduct?> fetchByBarcode(String barcode) async {
    final cacheKey = '$_cachePrefixBarcode$barcode';
    final cached = await _readCache(cacheKey);
    if (cached != null) return cached;
    try {
      final uri = Uri.parse('$_base/$barcode.json');
      final resp = await http.get(uri, headers: {
        'User-Agent': 'GroceryGuardian/0.1 (+https://github.com/WoofahRayetCode/grocery_guardian)'
      });
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map) return null;
      final product = data['product'];
      if (product == null) return null;

      final parsed = _parseProduct(product, fallbackBarcode: barcode);
      if (parsed != null) {
        await _writeCache(cacheKey, parsed);
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  static Future<ScannedProduct?> searchByName(String name) async {
    final cacheKey = '$_cachePrefixSearch${name.toLowerCase()}';
    final cached = await _readCache(cacheKey);
    if (cached != null) return cached;
    try {
      final params = {
        'search_terms': name,
        'search_simple': '1',
        'json': '1',
        'page_size': '1',
        'fields': [
          'code',
          'product_name',
          'brands',
          'allergens_tags',
          'ingredients_text',
          'image_front_url',
          'categories_tags',
        ].join(','),
      };
      final uri = Uri.parse(_searchBase).replace(queryParameters: params);
      final resp = await http.get(uri, headers: {
        'User-Agent': 'GroceryGuardian/0.1 (+https://github.com/WoofahRayetCode/grocery_guardian)'
      });
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map) return null;
      final products = data['products'];
      if (products is! List || products.isEmpty) return null;
      final product = products.first as Map;
      final parsed = _parseProduct(product);
      if (parsed != null) {
        await _writeCache(cacheKey, parsed);
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  static ScannedProduct? _parseProduct(Map product, {String? fallbackBarcode}) {
    final code = (product['code'] as String?) ?? fallbackBarcode ?? '';
    final productName = (product['product_name'] as String?)?.trim();
    final brand = (product['brands'] as String?)?.split(',').first.trim();
  final ingredientsText = (product['ingredients_text'] as String?)?.trim();
    final imageUrl = product['image_front_url'] as String?;
  final categoriesTags = (product['categories_tags'] is List)
    ? (product['categories_tags'] as List).whereType<String>().toList()
    : const <String>[];
  final usageHint = _inferUsageHint(productName, categoriesTags);
  final babyCautions = _inferBeautyBabyCautions(productName, categoriesTags, ingredientsText);
  final maternityCautions = _inferBeautyMaternityCautions(ingredientsText);
  final babyRecommendations = _inferBeautyBabyRecommendations(productName, categoriesTags, ingredientsText);
    // Allergen extraction: use allergens_tags if present, else scan ingredients
    List<String> allergens = [];
    final rawTags = product['allergens_tags'];
    if (rawTags is List) {
      allergens = rawTags
          .whereType<String>()
          .map((e) => e.contains(':') ? e.split(':').last : e)
          .map((e) => e.replaceAll('-', ' '))
          .map((e) => OpenFoodFactsService._capitalize(e))
          .toList();
    } else if ((ingredientsText ?? '').isNotEmpty) {
      allergens = _extractCosmeticAllergensFromIngredients(ingredientsText!);
    }
    return ScannedProduct(
      barcode: code,
      name: productName,
      brand: brand,
      allergens: allergens,
      ingredientsText: ingredientsText,
      nutriments: const {},
      nutriScore: null,
      imageUrl: imageUrl,
      productType: 'Personal care',
      source: 'obf',
      usageHint: usageHint,
  babyCautions: babyCautions,
  maternityCautions: maternityCautions,
  babyRecommendations: babyRecommendations,
    );
  }

  static String? _inferUsageHint(String? name, List<String> categoriesTags) {
    final hay = ((name ?? '') + ' ' + categoriesTags.join(' ')).toLowerCase();
    const rinseOff = [
      'shampoo', 'shower', 'body-wash', 'body_wash', 'gel-douche', 'gel_douche', 'cleanser',
      'soap', 'face-wash', 'face_wash', 'toothpaste', 'rinse-off', 'mouthwash', 'conditioner',
      'hair-mask', 'hair_mask', 'scrub', 'exfoliant', 'wash', 'gel nettoyant'
    ];
    const leaveOn = [
      'lotion', 'cream', 'moisturizer', 'moisturiser', 'deodorant', 'antiperspirant', 'sunscreen',
      'sun-cream', 'suncream', 'makeup', 'foundation', 'lipstick', 'balm', 'serum', 'oil', 'perfume',
      'aftershave', 'toner', 'leave-in'
    ];
    if (rinseOff.any((k) => hay.contains(k))) return 'Rinse-off';
    if (leaveOn.any((k) => hay.contains(k))) return 'Leave-on';
    return null;
  }

  static List<String> _extractCosmeticAllergensFromIngredients(String text) {
    final t = text.toLowerCase();
    final Set<String> hits = {};
    // Common contact/fragrance allergens (subset of EU 26 + common irritants)
    const List<String> patterns = [
      'fragrance', 'parfum', 'perfume',
      'linalool', 'limonene', 'citral', 'eugenol', 'coumarin', 'cinnamal', 'cinnamyl alcohol',
      'farnesol', 'geraniol', 'hexyl cinnamal', 'hydroxycitronellal', 'isoeugenol',
      'anisyl alcohol', 'benzyl alcohol', 'benzyl benzoate', 'benzyl salicylate', 'butylphenyl methylpropional',
      'amyl cinnamal', 'amylcinnamyl alcohol', 'citronellol', 'evernia prunastri', 'evernia furfuracea',
      'methylisothiazolinone', 'methylchloroisothiazolinone', 'cocamidopropyl betaine', 'lanolin',
      'nickel', 'balsam peru', 'formaldehyde', 'quaternium-15', 'dmdm hydantoin', 'imidazolidinyl urea', 'diazolidinyl urea',
      // Also include some food-origin allergens that may appear in cosmetics
      'milk', 'whey', 'casein', 'egg', 'almond', 'peanut', 'wheat', 'gluten', 'soy', 'sesame'
    ];
    for (final p in patterns) {
      if (t.contains(p)) {
        hits.add(OpenFoodFactsService._capitalize(p.replaceAll('-', ' ')));
      }
    }
    return hits.toList()..sort();
  }

  static List<String> _inferBeautyBabyCautions(String? name, List<String> categoriesTags, String? ingredientsText) {
    final hay = ((name ?? '') + ' ' + categoriesTags.join(' ') + ' ' + (ingredientsText ?? '')).toLowerCase();
    final List<String> cautions = [];
    final isBabyTargeted = hay.contains('baby') || hay.contains('infant') || hay.contains('newborn');
    // If baby-targeted product includes fragrance/essential oils, caution
    final fragranceTerms = ['fragrance', 'parfum', 'perfume', 'essential oil', 'lavender oil', 'tea tree oil', 'eucalyptus', 'menthol', 'peppermint oil', 'camphor'];
    if (isBabyTargeted && fragranceTerms.any((k) => hay.contains(k))) {
      cautions.add('Fragrance/essential oils may irritate infant skin');
    }
    // Talc caution for baby powders
    if (isBabyTargeted && hay.contains('talc')) {
      cautions.add('Avoid talc for babies due to inhalation risk');
    }
    // EU-26 fragrance allergens present in baby-targeted product
    const eu26 = ['linalool','limonene','citral','eugenol','coumarin','cinnamal','cinnamyl alcohol','farnesol','geraniol','hexyl cinnamal','hydroxycitronellal','isoeugenol','anisyl alcohol','benzyl alcohol','benzyl benzoate','benzyl salicylate','butylphenyl methylpropional','amyl cinnamal','amylcinnamyl alcohol','citronellol','evernia prunastri','evernia furfuracea'];
    if (isBabyTargeted && eu26.any((k) => hay.contains(k))) {
      cautions.add('EU-listed fragrance allergens present');
    }
    return cautions;
  }

  static List<String> _inferBeautyMaternityCautions(String? ingredientsText) {
    final t = (ingredientsText ?? '').toLowerCase();
    final List<String> cautions = [];
    final retinoids = ['retinol','retinal','retinoate','tretinoin','adapalene','tazarotene','isotretinoin'];
    final salicylates = ['salicylic acid','beta hydroxy'];
    final others = ['hydroquinone','formaldehyde','phthalate','minoxidil'];
    final chemicalSunscreens = ['oxybenzone','avobenzone','octinoxate','octocrylene','homosalate'];
    final ahas = ['glycolic acid','lactic acid','alpha hydroxy'];
    if (retinoids.any((k) => t.contains(k))) cautions.add('Contains retinoids: generally avoided in pregnancy');
    if (salicylates.any((k) => t.contains(k))) cautions.add('Contains salicylates: check usage during pregnancy');
    if (others.any((k) => t.contains(k))) cautions.add('Ingredient to review during pregnancy');
    if (chemicalSunscreens.any((k) => t.contains(k))) cautions.add('Chemical sunscreen: review during pregnancy');
    if (ahas.any((k) => t.contains(k))) cautions.add('AHA acids: check usage during pregnancy');
    if (t.contains('peppermint oil')) cautions.add('Breastfeeding: peppermint oil may affect milk supply');
    if (t.contains('lanolin')) cautions.add('Breastfeeding: lanolin may cause sensitivity; patch test');
    return cautions;
  }

  static List<String> _inferBeautyBabyRecommendations(String? name, List<String> categoriesTags, String? ingredientsText) {
    // Currently no cosmetic recommendations for babies beyond cautions; return empty.
    return const [];
  }

  /// Test helper to construct a ScannedProduct using parser heuristics.
  /// Not intended for production use beyond unit tests.
  static ScannedProduct debugParseProduct(Map product) {
    return _parseProduct(product, fallbackBarcode: product['code'] as String? ?? 'debug')!;
  }

  static Future<ScannedProduct?> _readCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final ts = DateTime.fromMillisecondsSinceEpoch(decoded['ts'] as int);
      if (DateTime.now().difference(ts) > _ttl) {
        await prefs.remove(key);
        return null;
      }
      final prod = ScannedProduct.fromJson(Map<String, dynamic>.from(decoded['data'] as Map));
      return prod;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String key, ScannedProduct product) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'ts': DateTime.now().millisecondsSinceEpoch,
        'data': product.toJson(),
      });
      await prefs.setString(key, payload);
    } catch (_) {}
  }

  static Future<int> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      int removed = 0;
      for (final k in keys) {
        if (k.startsWith(_cachePrefixBarcode) || k.startsWith(_cachePrefixSearch)) {
          await prefs.remove(k);
          removed++;
        }
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> cacheEntryCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      int count = 0;
      for (final k in keys) {
        if (k.startsWith(_cachePrefixBarcode) || k.startsWith(_cachePrefixSearch)) {
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }
}

// Unified product lookup that tries OFF first, then OBF
class ProductLookupService {
  static Future<ScannedProduct?> fetchAnyByBarcode(String barcode) async {
    final off = await OpenFoodFactsService.fetchByBarcode(barcode);
    if (off != null) return off;
    final obf = await OpenBeautyFactsService.fetchByBarcode(barcode);
    return obf;
  }

  static Future<ScannedProduct?> searchAnyByName(String name) async {
    final off = await OpenFoodFactsService.searchByName(name);
    if (off != null) return off;
    final obf = await OpenBeautyFactsService.searchByName(name);
    return obf;
  }
}

class ProductLookupCache {
  static Future<int> clearAll() async {
    final a = await OpenFoodFactsService.clearCache();
    final b = await OpenBeautyFactsService.clearCache();
    return a + b;
  }

  static Future<int> totalEntryCount() async {
    final a = await OpenFoodFactsService.cacheEntryCount();
    final b = await OpenBeautyFactsService.cacheEntryCount();
    return a + b;
  }
}
