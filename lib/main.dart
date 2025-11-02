// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // Add this import at the top if not present
import 'package:package_info_plus/package_info_plus.dart'; // Add this import at the top
// import 'package:apk_installer/apk_installer.dart'; // removed: no in-app APK installs
// import 'package:path_provider/path_provider.dart';
// import 'dart:io';
import 'screens/scan_product_screen.dart';
import 'services/product_lookup.dart';
import 'services/recall_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' as gma;
import 'services/secure_prefs.dart';
import 'services/http_client.dart';
import 'services/consent_manager.dart';
import 'services/device_security.dart';

// Compile-time feature flags for store-specific builds
const bool kAdsEnabled = bool.fromEnvironment('ADS', defaultValue: false);
const bool kDonationsEnabled = bool.fromEnvironment('DONATIONS', defaultValue: true);
const String kBannerAdUnitId = String.fromEnvironment(
  'ADMOB_BANNER_ANDROID_ID',
  defaultValue: 'ca-app-pub-3940256099942544/6300978111', // Google test banner id
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kAdsEnabled) {
    await ConsentManager.requestConsentAndShowIfRequired();
    await gma.MobileAds.instance.initialize();
  }
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    // Warn users if device appears rooted/jailbroken
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeviceSecurity.warnIfCompromised(context);
    });
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString('themeMode') ?? 'system';
    setState(() {
      switch (themeString) {
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        default:
          _themeMode = ThemeMode.system;
      }
    });
  }

  Future<void> _setTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = mode;
    });
    await prefs.setString('themeMode', mode.name);
  }

  @override
  Widget build(BuildContext context) {
  // Build light/dark themes with Material 3
  final ThemeData lightTheme = ThemeData.light(useMaterial3: true);
  final ThemeData darkTheme = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      home: GroceryListScreen(
        onThemeChanged: _setTheme,
        currentThemeMode: _themeMode,
      ),
      routes: {
        '/allergyInfo': (context) => const AllergyInfoScreen(),
        '/resources': (context) => const LowIncomeResourcesScreen(),
        '/update': (context) => const UpdateScreen(),
  '/credits': (context) => const CreditsScreen(),
        '/scan': (context) => const ScanProductScreen(),
  '/allergyList': (context) => const UserAllergyListScreen(),
  '/recalls': (context) => const RecallManagementScreen(),
      },
    );
  }
}

// Add this helper map to associate foods with icons (place near your other data/maps):
final Map<String, IconData> foodIcons = {
  'Milk': Icons.local_drink,
  'Eggs': Icons.egg,
  'Peanuts': Icons.spa,
  'Tree nuts': Icons.nature,
  'Wheat': Icons.grain,
  'Soy': Icons.spa,
  'Fish': Icons.set_meal,
  'Shellfish': Icons.set_meal,
  'Strawberries': Icons.local_florist,
  'Tomatoes': Icons.local_florist,
  'Sesame': Icons.spa,
  // Add more as needed
};

// Update GroceryListScreen to accept theme controls
class GroceryListScreen extends StatefulWidget {
  final void Function(ThemeMode)? onThemeChanged;
  final ThemeMode? currentThemeMode;

  const GroceryListScreen({super.key, this.onThemeChanged, this.currentThemeMode});

  @override
  State<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends State<GroceryListScreen> {
  // Active lists for the currently selected profile (contents change on profile switch)
  final List<_GroceryItem> _mainItems = [];
  final List<_GroceryItem> _taggedItems = [];

  // Profiles: keep separate lists per person to avoid mixing items
  // Key: profile name (unique), Value: list for that profile
  final Map<String, List<_GroceryItem>> _mainByProfile = {};
  final Map<String, List<_GroceryItem>> _taggedByProfile = {};
  final List<String> _profiles = [];
  String _currentProfile = 'Everyone';
  final TextEditingController _itemController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  // Regular items (auto-load) feature state/keys
  static const String _kCountsKey = 'regular_item_counts';
  static const String _kAutoLoadKey = 'auto_load_regulars';
  static const String _kRegularThresholdKey = 'regular_min_count';
  static const String _kRegularMaxItemsKey = 'regular_max_items';
  static const String _kRegularExcludeKey = 'regular_exclude_list';
  static const String _kRegularAddModeKey = 'regular_add_mode'; // 'auto' or 'prompt'
  static const String _kRegularOnlyIfEmptyKey = 'regular_only_if_empty';
  static const String _kRegularInfoShownKey = 'regular_info_shown_v1';

  bool _autoLoadRegulars = false;
  int _regularMinCount = 3; // becomes regular after >=3 purchases
  int _regularMaxItems = 20; // cap number of autoloaded items
  String _regularAddMode = 'auto';
  bool _autoloadOnlyIfEmpty = true;
  Set<String> _regularExclude = {};

  // Add this map after FoodReactionDatabase to suggest alternatives:
  final Map<String, List<String>> allergyAlternatives = {
    'Milk': ['Oat milk', 'Almond milk', 'Soy milk', 'Coconut milk'],
    'Eggs': ['Flaxseed meal', 'Chia seeds', 'Applesauce', 'Commercial egg replacer'],
    'Peanuts': ['Sunflower seed butter', 'Soy nut butter', 'Pea butter'],
    'Tree nuts': ['Pumpkin seeds', 'Sunflower seeds'],
    'Wheat': ['Rice flour', 'Oat flour', 'Almond flour', 'Gluten-free flour'],
    'Soy': ['Coconut aminos', 'Pea protein', 'Sunflower lecithin'],
    'Fish': ['Chicken', 'Tofu', 'Tempeh'],
    'Shellfish': ['Chicken', 'Tofu', 'Jackfruit'],
    'Strawberries': ['Blueberries', 'Raspberries', 'Blackberries'],
    'Tomatoes': ['Roasted red peppers', 'Pumpkin puree'],
    'Sesame': ['Sunflower seeds', 'Pumpkin seeds'],
    // Add more as needed
  };

  // Keywords for non-food items often associated with contact/fragrance allergies
  static const Set<String> _nonFoodAllergyKeywords = {
    'lotion','cream','moisturizer','moisturiser','deodorant','antiperspirant','sunscreen','sunblock',
    'perfume','fragrance','parfum','cologne','shampoo','conditioner','cleanser','soap','body wash','wash','toner','serum','balm','oil'
  };

  String _normalizeItemKey(String s) => s.trim().toLowerCase();

  Future<bool> _hasPromptedExistingAllergy(String normalizedKey) async {
    return SecurePrefs.getAllergyPrompted(_currentProfile, normalizedKey);
  }

  Future<void> _setPromptedExistingAllergy(String normalizedKey) async {
    await SecurePrefs.setAllergyPrompted(_currentProfile, normalizedKey, true);
  }

  Future<void> _addUserAllergyPreference(String normalizedKey) async {
    final current = await SecurePrefs.getAllergyList(_currentProfile);
    if (!current.contains(normalizedKey)) {
      current.add(normalizedKey);
      await SecurePrefs.setAllergyList(_currentProfile, current);
    }
  }

  Future<List<String>> _getUserAllergyList() async {
    return SecurePrefs.getAllergyList(_currentProfile);
  }

  Future<void> _removeUserAllergyPreference(String normalizedKey) async {
    final current = await SecurePrefs.getAllergyList(_currentProfile);
    current.removeWhere((e) => e == normalizedKey);
    await SecurePrefs.setAllergyList(_currentProfile, current);
  }

  bool _looksLikeCommonAllergenTerm(String normalizedName) {
    // Exact match on known food allergens list
    final isFood = FoodReactionDatabase.commonReactions.any((e) => e.food.toLowerCase() == normalizedName);
    if (isFood) return true;
    // Contains non-food allergy keywords
    for (final k in _nonFoodAllergyKeywords) {
      if (normalizedName.contains(k)) return true;
    }
    return false;
  }

  void _addItem() async {
    final name = _itemController.text.trim();
    final tag = _tagController.text.trim();
    final price = _parsePrice(_priceController.text);

    if (name.isEmpty) return;

    // CHECK FOR RECALLS FIRST (before any other processing)
    final recallMatch = await RecallService.checkProduct(productName: name);
    if (recallMatch != null) {
      // Product is recalled - show warning and block
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Theme.of(context).colorScheme.error, size: 28),
              const SizedBox(width: 8),
              const Text('RECALL WARNING'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This product is part of an active recall:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                Text('Product: ${recallMatch.productName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (recallMatch.brand != null) Text('Brand: ${recallMatch.brand}'),
                const SizedBox(height: 8),
                if (recallMatch.reason != null) ...[
                  const Text('Reason:', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(recallMatch.reason!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                ],
                if (recallMatch.datePublished != null)
                  Text('Recall Date: ${recallMatch.datePublished}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '⚠️ This item cannot be added to your shopping list until confirmed safe.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                await RecallService.markRecallSafe(recallMatch.id);
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recall marked as safe. You can now add this item.')),
                  );
                }
              },
              child: const Text('Mark as Safe', style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
      );
      return; // Block adding the item
    }

    // One-time prompt for known allergen-prone items (food or non-food)
    final normalized = _normalizeItemKey(name);
    if (normalized.isNotEmpty && _looksLikeCommonAllergenTerm(normalized)) {
      final already = await _hasPromptedExistingAllergy(normalized);
      if (!already && mounted) {
        bool saidHasAllergy = false;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Existing allergy?'),
            content: Text('Do you or your household have an existing allergy related to "$name"?'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('No'),
              ),
              FilledButton(
                onPressed: () {
                  saidHasAllergy = true;
                  Navigator.pop(context);
                },
                child: const Text('Yes'),
              ),
            ],
          ),
        );
        await _setPromptedExistingAllergy(normalized);
        if (saidHasAllergy) {
          await _addUserAllergyPreference(normalized);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Saved allergy preference for "$name".')),
            );
          }
        }
      }
    }

    final commonReactions = FoodReactionDatabase.getReactionsForFood(name);
  // Query OpenFoodFacts/Open Beauty Facts for up-to-date info
    ScannedProduct? off; 
    if (name.isNotEmpty) {
      off = await ProductLookupService.searchAnyByName(name);
    }

    // Merge allergens from OFF and local database
    final offAllergenList = off?.allergens ?? const [];
    final mergedAllergens = {
      ...commonReactions,
      ...offAllergenList.map((e) => e),
    }.toList();
    // Precompute some optional fields for display
    final offName = off?.name;
    final offBrand = off?.brand;
    final offIngredients = off?.ingredientsText ?? '';
    final offNutri = off?.nutriScore;

    if (mergedAllergens.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Allergy Warning (OpenFoodFacts)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (offName != null)
                Text('Product: $offName${offBrand != null ? ' ($offBrand)' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (offName == null)
                Text('"$name" may contain allergens', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (mergedAllergens.isNotEmpty) ...[
                const Text('Allergens detected:'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: -8,
                  children: mergedAllergens.map((a) => Chip(
                    label: Text(a),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Theme.of(context).colorScheme.errorContainer,
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontWeight: FontWeight.w600),
                    side: BorderSide(color: Theme.of(context).colorScheme.error, width: 1.0),
                  )).toList(),
                ),
                const SizedBox(height: 8),
              ],
              if ((off?.productType ?? '').isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Chip(
                        label: Text(off!.productType!),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
                      ),
                      const SizedBox(width: 8),
                      if ((off.source ?? '').isNotEmpty)
                        Chip(
                          label: Text(off.source == 'obf' ? 'Open Beauty Facts' : 'Open Food Facts'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
                        ),
                      if ((off.usageHint ?? '').isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(off.usageHint!),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
                        ),
                      ],
                      if ((off.babyCautions).isNotEmpty) ...[
                        const SizedBox(width: 8),
                        ...off.babyCautions.take(2).map((c) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Chip(
                            label: Text(c),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                            labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
                            side: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 1.0),
                          ),
                        )),
                      ],
                      if ((off.maternityCautions).isNotEmpty) ...[
                        const SizedBox(width: 8),
                        ...off.maternityCautions.take(2).map((c) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Chip(
                            label: Text(c),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                            labelStyle: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer),
                            side: BorderSide(color: Theme.of(context).colorScheme.tertiary, width: 1.0),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
              ],
              if (offIngredients.isNotEmpty) ...[
                const Text('Ingredients (from OFF):', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(offIngredients, maxLines: 4, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
              ],
              if (offNutri != null) ...[
                Text('Nutri-Score: ${offNutri.toUpperCase()}'),
                const SizedBox(height: 4),
              ],
              const SizedBox(height: 16),
              const Text(
                'Are you purchasing this for someone else (not yourself)?',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            if (off != null)
              TextButton(
                onPressed: () async {
                  Navigator.pop(context, true);
                  await _showProductDetails(context, off!);
                },
                child: const Text('Details'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, for someone else'),
            ),
          ],
        ),
      );
      if (!mounted) return; // <-- Add this line

      if (confirmed != true) {
        // Recommend alternatives if available (prefer OFF allergen-based)
        final baseAllergen = mergedAllergens.firstWhere(
          (a) => allergyAlternatives.containsKey(a),
          orElse: () => name,
        );
        final alternatives = allergyAlternatives[baseAllergen];
        _itemController.clear();
        _tagController.clear();

        if (alternatives != null && alternatives.isNotEmpty) {
          bool needsMoreSpecifics = false;
          await showDialog(
            context: context,
            builder: (context) {
              return StatefulBuilder(
                builder: (context, setState) => AlertDialog(
                  title: Text('Alternatives for $baseAllergen'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Consider these safe alternatives for "${off?.name ?? name}":'),
                      const SizedBox(height: 8),
                      ...alternatives.map((alt) => ListTile(
                            title: Text(alt),
                            trailing: Icon(Icons.add),
                            onTap: () {
                              this.setState(() {
                                _mainItems.add(_GroceryItem(name: alt, tag: 'Option Chosen for $name'));
                              });
                              Navigator.pop(context);
                            },
                          )),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            needsMoreSpecifics = true;
                          });
                        },
                        child: const Text('Need more specific alternatives?'),
                      ),
                      if (needsMoreSpecifics)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'More Specific Alternatives:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              ..._getMoreSpecificAlternatives(name).map((alt) => ListTile(
                                    title: Text(alt),
                                    trailing: Icon(Icons.add),
                                    onTap: () {
                                      this.setState(() {
                                        _mainItems.add(_GroceryItem(name: alt, tag: 'Option Chosen for $name'));
                                      });
                                      Navigator.pop(context);
                                    },
                                  )),
                            ],
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              );
            },
          );
        }
        if (!mounted) return; // <-- Add this line
        return;
      }
    }

    if (name.isNotEmpty) {
      final userAllergyList = await _getUserAllergyList();
      setState(() {
        if (tag.isNotEmpty) {
      _taggedItems.add(_GroceryItem(name: off?.name ?? name, tag: tag, price: price));
        } else {
      final offAllergensLower = (off?.allergens ?? const []).map((e) => e.toLowerCase()).toSet();
      final commonAllergens = <String>['Milk','Eggs','Peanuts','Tree nuts','Wheat','Soy','Fish','Shellfish','Sesame'];
      final matched = commonAllergens.where((a) => offAllergensLower.contains(a.toLowerCase())).toList();
      final Set<String> mergedSet = {...matched, ...commonReactions};
      final bool userFlag = userAllergyList.contains(_normalizeItemKey(name));
      String mergedTag = '';
      if (mergedSet.isNotEmpty) {
        mergedTag = 'Allergen: ${mergedSet.join(', ')}';
      }
      if (userFlag) {
        mergedTag = mergedTag.isEmpty ? 'User allergy' : '$mergedTag; User allergy';
      }
      _mainItems.add(_GroceryItem(name: off?.name ?? name, tag: mergedTag, price: price));
        }
        _itemController.clear();
        _tagController.clear();
        _priceController.clear();
        _syncStoreFromCurrent();
      });
    }
  }

  void _addTaggedToMain(_GroceryItem item) {
    // Check if already exists in main list
    if (_mainItems.any((i) => i.name == item.name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} is already in your main list.')),
      );
      return;
    }
    setState(() {
      _mainItems.add(_GroceryItem(name: item.name, tag: item.tag, price: item.price));
      _syncStoreFromCurrent();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Warning: "${item.name}" has a Discomfort: "${item.tag}"',
          style: const TextStyle(color: Colors.yellow),
        ),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _uncheckAll() async {
    // Record purchased items to counts
    final purchased = _mainItems.where((i) => i.checked).map((i) => i.name).toList(growable: false);
    if (purchased.isNotEmpty) {
      await _incrementCountsFor(purchased);
    }
    setState(() {
      // Remove all checked items from main and tagged lists
      _mainItems.removeWhere((item) => item.checked);
      _taggedItems.removeWhere((item) => item.checked);
      // Uncheck the rest
      for (var item in _mainItems) {
        item.checked = false;
      }
      for (var item in _taggedItems) {
        item.checked = false;
      }
      _syncStoreFromCurrent();
    });
  }

  @override
  void dispose() {
    _itemController.dispose();
    _tagController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _showPermissionsOnFirstLaunch();
    _initProfiles();
  _loadAutoLoadSetting();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoloadRegulars();
    });
  }

  Future<void> _initProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('current_profile');
    final profilesJson = prefs.getString('profiles_list');
    List<String> loadedProfiles = [];
    if (profilesJson != null && profilesJson.isNotEmpty) {
      try {
        final list = jsonDecode(profilesJson);
        if (list is List) {
          loadedProfiles = list.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    if (loadedProfiles.isEmpty) {
      loadedProfiles = ['Everyone'];
    }
    // Ensure "Everyone" exists and is first
    if (!loadedProfiles.contains('Everyone')) {
      loadedProfiles.insert(0, 'Everyone');
    } else {
      loadedProfiles
        ..remove('Everyone')
        ..insert(0, 'Everyone');
    }
    _profiles
      ..clear()
      ..addAll(loadedProfiles);
    // Load lists per profile
    for (final p in _profiles) {
      final key = _encodeProfileKey(p);
      final mainStr = prefs.getString('profile_main_$key');
      final taggedStr = prefs.getString('profile_tagged_$key');
      _mainByProfile[p] = _deserializeItems(mainStr);
      _taggedByProfile[p] = _deserializeItems(taggedStr);
    }
    // Fallback to empty lists for missing
    _mainByProfile.putIfAbsent('Everyone', () => <_GroceryItem>[]);
    _taggedByProfile.putIfAbsent('Everyone', () => <_GroceryItem>[]);
    // Activate saved or default profile without persisting
    _switchProfile(saved ?? 'Everyone', persist: false);
  }

  void _switchProfile(String name, {bool persist = true}) async {
    if (name.isEmpty) return;
    if (!_profiles.contains(name)) {
      _profiles.add(name);
    }
    // Ensure store lists exist
    _mainByProfile.putIfAbsent(name, () => <_GroceryItem>[]);
    _taggedByProfile.putIfAbsent(name, () => <_GroceryItem>[]);
  // Save current active lists to store before switching and persist them
  _syncStoreFromCurrent();
  await _persistCurrentProfileData();
    // Change current and pull lists into active buffers
    setState(() {
      _currentProfile = name;
      _mainItems
        ..clear()
        ..addAll(_mainByProfile[name] ?? const <_GroceryItem>[]);
      _taggedItems
        ..clear()
        ..addAll(_taggedByProfile[name] ?? const <_GroceryItem>[]);
    });
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_profile', _currentProfile);
  await _persistProfilesList();
    }
  }

  void _syncStoreFromCurrent() {
    // Keep the backing store in sync with visible lists for current profile
    _mainByProfile[_currentProfile] = List<_GroceryItem>.from(_mainItems);
    _taggedByProfile[_currentProfile] = List<_GroceryItem>.from(_taggedItems);
  }

  // Profile selector UI
  Future<void> _showProfileSelector() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final controller = TextEditingController();
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_alt),
                  const SizedBox(width: 8),
                  const Text('Profiles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                    onPressed: () {
                      final name = controller.text.trim();
                      if (name.isEmpty) return;
                      _switchProfile(name);
                      Navigator.pop(context);
                    },
                  )
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'New profile name',
                  prefixIcon: Icon(Icons.person_add),
                ),
                onSubmitted: (_) {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  _switchProfile(name);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _profiles.length,
                  itemBuilder: (context, i) {
                    final name = _profiles[i];
                    return ListTile(
                      leading: Icon(name == _currentProfile ? Icons.radio_button_checked : Icons.radio_button_off),
                      title: Text(name),
                      trailing: name != 'Everyone'
                          ? IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                setState(() {
                                  _mainByProfile.remove(name);
                                  _taggedByProfile.remove(name);
                                  _profiles.remove(name);
                                  if (_currentProfile == name) {
                                    _switchProfile('Everyone');
                                  }
                                });
                                await _persistProfilesList();
                              },
                            )
                          : null,
                      onTap: () {
                        _switchProfile(name);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // Permissions dialog helpers
  void showPermissionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy & Permissions'),
        content: const Text(
          'We respect your privacy. This app stores your preferences locally on your device.\n\n'
          'Permissions used:\n'
          '- Camera: Scan barcodes to look up products.\n'
          '- Internet: Fetch product info, recalls, and open links.\n\n'
          'Advertising (Play build only):\n'
          'If ads are enabled, Google Mobile Ads may process device identifiers subject to your consent. You can manage consent from the app menu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermissionsOnFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('permissions_shown') ?? false;
    if (!shown) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showPermissionsDialog(context);
      });
      await prefs.setBool('permissions_shown', true);
    }
  }

  String _encodeProfileKey(String name) => Uri.encodeComponent(name);

  Future<void> _persistProfilesList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profiles_list', jsonEncode(_profiles));
  }

  List<Map<String, dynamic>> _serializeItems(List<_GroceryItem> items) =>
      items
          .map((e) => {
                'name': e.name,
                'tag': e.tag,
                'checked': e.checked,
                'price': e.price,
              })
          .toList();

  List<_GroceryItem> _deserializeItems(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return <_GroceryItem>[];
    try {
      final data = jsonDecode(jsonStr);
      if (data is List) {
        return data.map<_GroceryItem>((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final item = _GroceryItem(
            name: m['name'] as String? ?? '',
            tag: m['tag'] as String? ?? '',
            price: (m['price'] is num) ? (m['price'] as num).toDouble() : 0.0,
          );
          item.checked = (m['checked'] as bool?) ?? false;
          return item;
        }).toList();
      }
    } catch (_) {}
    return <_GroceryItem>[];
  }

  Future<void> _persistCurrentProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _encodeProfileKey(_currentProfile);
    await prefs.setString('profile_main_$key', jsonEncode(_serializeItems(_mainItems)));
    await prefs.setString('profile_tagged_$key', jsonEncode(_serializeItems(_taggedItems)));
  }

  // ===== Prices: helpers & UI =====
  double _parsePrice(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'[^0-9\.-]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  String _fmtCurrency(double value) => '\$${value.toStringAsFixed(2)}';

  double get _totalAll => _mainItems.fold(0.0, (s, i) => s + (i.price));
  double get _totalChecked => _mainItems.where((i) => i.checked).fold(0.0, (s, i) => s + (i.price));
  double get _totalRemaining => _mainItems.where((i) => !i.checked).fold(0.0, (s, i) => s + (i.price));

  Widget _totalChip(String label, double amount) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label: ${_fmtCurrency(amount)}'),
      visualDensity: VisualDensity.compact,
      backgroundColor: cs.surfaceContainerHighest,
      labelStyle: TextStyle(color: cs.onSurface),
      side: BorderSide(color: cs.outline, width: 1.0),
    );
  }

  Future<void> _editItemPrice(_GroceryItem item) async {
    final controller = TextEditingController(text: item.price == 0 ? '' : item.price.toStringAsFixed(2));
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set price for "${item.name}"'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '\$ ', hintText: 'e.g. 2.49'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                item.price = _parsePrice(controller.text);
                _syncStoreFromCurrent();
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allChecked = _mainItems.isNotEmpty && _mainItems.every((item) => item.checked);

  return Scaffold(
      appBar: AppBar(
        title: const Text('Grocery List'),
        actions: [
          Tooltip(
            message: 'Profile: $_currentProfile',
            child: IconButton(
              icon: const Icon(Icons.person),
              onPressed: _showProfileSelector,
            ),
          ),
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              final result = await Navigator.pushNamed(context, '/scan');
              if (!mounted) return;
              if (result == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No product found for that barcode. Try searching by name.')),
                );
                return;
              }
              if (result is ScannedProduct) {
                final displayName = result.name?.isNotEmpty == true
                    ? result.name!
                    : 'Item ${result.barcode}';
                
                // CHECK FOR RECALLS FIRST
                final recallMatch = await RecallService.checkProduct(
                  barcode: result.barcode,
                  productName: displayName,
                );
                
                if (recallMatch != null) {
                  // Product is recalled - show warning and block adding
                  final shouldProceed = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => AlertDialog(
                      title: Row(
                        children: [
                          Icon(Icons.warning, color: Theme.of(context).colorScheme.error, size: 28),
                          const SizedBox(width: 8),
                          const Text('RECALL WARNING'),
                        ],
                      ),
                      content: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'This product is part of an active recall:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('Product: ${recallMatch.productName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (recallMatch.brand != null) Text('Brand: ${recallMatch.brand}'),
                            const SizedBox(height: 8),
                            if (recallMatch.reason != null) ...[
                              const Text('Reason:', style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(recallMatch.reason!, style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 8),
                            ],
                            if (recallMatch.datePublished != null)
                              Text('Recall Date: ${recallMatch.datePublished}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '⚠️ This item cannot be added to your shopping list until confirmed safe.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Close'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await RecallService.markRecallSafe(recallMatch.id);
                            Navigator.pop(context, true);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Recall marked as safe. You can now add this item.')),
                              );
                            }
                          },
                          child: const Text('Mark as Safe', style: TextStyle(color: Colors.orange)),
                        ),
                      ],
                    ),
                  );
                  
                  if (shouldProceed != true) return; // Blocked - don't show product dialog
                }
                
                final knownReactions = FoodReactionDatabase.getReactionsForFood(displayName);
                final offAllergens = result.allergens.map((e) => e.toLowerCase()).toSet();
                final commonAllergens = <String>['Milk','Eggs','Peanuts','Tree nuts','Wheat','Soy','Fish','Shellfish','Sesame'];
                final matched = commonAllergens.where((a) => offAllergens.contains(a.toLowerCase())).toList();

                final allergensMerged = {...matched, ...knownReactions}.toList();

                final add = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(displayName),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((result.imageUrl ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(result.imageUrl!, height: 140, fit: BoxFit.cover),
                              ),
                            ),
                          if (allergensMerged.isNotEmpty) ...[
                            const Text('Allergens detected:'),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: -8,
                              children: allergensMerged.map((a) => Chip(
                                label: Text(a),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                                labelStyle: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontWeight: FontWeight.w600),
                                side: BorderSide(color: Theme.of(context).colorScheme.error, width: 1.0),
                              )).toList(),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if ((result.ingredientsText ?? '').isNotEmpty) ...[
                            const Text('Ingredients:'),
                            Text(result.ingredientsText!, maxLines: 5, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 8),
                          ],
                          if ((result.nutriScore ?? '').isNotEmpty) Text('Nutri-Score: ${result.nutriScore!.toUpperCase()}'),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Alternatives'),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _showProductDetails(context, result);
                        },
                        child: const Text('Details'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Add to list'),
                      ),
                    ],
                  ),
                );

                if (add == true) {
                  final tag = allergensMerged.isNotEmpty ? 'Allergen: ${allergensMerged.join(', ')}' : '';
                  setState(() {
                    _mainItems.add(_GroceryItem(name: displayName, tag: tag));
                    _syncStoreFromCurrent();
                  });
                } else if (add == false) {
                  // Show alternatives dialog (based on detected allergens)
                  // Pick the first matched allergen that we have alternatives for
                  final baseAllergen = allergensMerged.firstWhere(
                    (a) => allergyAlternatives.containsKey(a),
                    orElse: () => displayName,
                  );
                  final alternatives = allergyAlternatives[baseAllergen] ?? const <String>[];
                  if (alternatives.isNotEmpty) {
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Alternatives for $baseAllergen'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: alternatives.map((alt) => ListTile(
                            title: Text(alt),
                            trailing: const Icon(Icons.add),
                            onTap: () {
                              setState(() {
                                _mainItems.add(_GroceryItem(name: alt, tag: 'Option Chosen for $baseAllergen'));
                                _syncStoreFromCurrent();
                              });
                              Navigator.pop(context);
                            },
                          )).toList(),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    );
                  }
                }
              }
            },
          ),
          // Theme toggle button
          PopupMenuButton<ThemeMode>(
            icon: const Icon(Icons.dark_mode),
            tooltip: 'Theme',
            onSelected: (mode) {
              widget.onThemeChanged?.call(mode);
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: ThemeMode.system,
                checked: widget.currentThemeMode == ThemeMode.system,
                child: const Text('System'),
              ),
              CheckedPopupMenuItem(
                value: ThemeMode.light,
                checked: widget.currentThemeMode == ThemeMode.light,
                child: const Text('Light'),
              ),
              CheckedPopupMenuItem(
                value: ThemeMode.dark,
                checked: widget.currentThemeMode == ThemeMode.dark,
                child: const Text('Dark'),
              ),
            ],
          ),
          // Quick Regular Items menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.history_toggle_off),
            tooltip: 'Regular Items',
            onSelected: (value) async {
              switch (value) {
                case 'load':
                  await _loadRegularsNow();
                  break;
                case 'settings':
                  _showRegularItemsSettings();
                  break;
                case 'clear':
                  await _clearRegularCounts();
                  break;
                case 'help':
                  await _showRegularInfoDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'load', child: ListTile(leading: Icon(Icons.playlist_add), title: Text('Load regulars'))),
              const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings), title: Text('Settings'))),
              const PopupMenuItem(value: 'help', child: ListTile(leading: Icon(Icons.help_outline), title: Text('How it works'))),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'clear', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.redAccent), title: Text('Clear history'))),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'More Info',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text('More Info & Links'),
                  children: [
                    SimpleDialogOption(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/allergyInfo');
                      },
                      child: const ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('Allergy Info'),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/resources');
                      },
                      child: const ListTile(
                        leading: Icon(Icons.location_city),
                        title: Text('Find Low Income Resources'),
                      ),
                    ),
                    if (kDonationsEnabled)
                      SimpleDialogOption(
                      onPressed: () async {
                        Navigator.pop(context);
                        final uri = Uri.parse('https://www.paypal.com/donate/?business=WZACHCSCA5SMS&no_recurring=0&currency_code=USD');
                        const browsers = [
                          'app.vanadium.browser',
                          'com.android.chrome',
                          'org.mozilla.firefox',
                          'com.opera.browser',
                          'com.brave.browser',
                          'com.microsoft.emmx',
                        ];
                        bool launched = false;
                        for (final pkg in browsers) {
                          final intent = AndroidIntent(
                            action: 'action_view',
                            data: uri.toString(),
                            package: pkg,
                          );
                          try {
                            await intent.launch();
                            launched = true;
                            break;
                          } catch (_) {}
                        }
                        if (!launched) {
                          if (!mounted) return; // <-- Add this line
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } else {
                            if (!mounted) return; // <-- Add this line
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Could not open PayPal link.')),
                            );
                          }
                        }
                      },
                      child: const ListTile(
                        leading: Icon(Icons.volunteer_activism),
                        title: Text('Donate (PayPal)'),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () async {
                        Navigator.pop(context);
                        final uri = Uri.parse('https://github.com/WoofahRayetCode/grocery_guardian');
                        try {
                          // Try to launch without canLaunchUrl for reliability
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } catch (e) {
                          // Show error with details
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not open GitHub Releases. Error: ${e.toString()}')),
                          );
                        }
                      },
                      child: const ListTile(
                        leading: Icon(Icons.code),
                        title: Text("Developer's GitHub"),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        Navigator.pop(context);
                        showPermissionsDialog(context);
                      },
                      child: const ListTile(
                        leading: Icon(Icons.privacy_tip),
                        title: Text('View App Permissions'),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () async {
                        Navigator.pop(context);
                        final count = await ProductLookupCache.totalEntryCount();
                        final removed = await ProductLookupCache.clearAll();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Cleared $removed product cache entr${removed == 1 ? 'y' : 'ies'} (was $count)')),
                        );
                      },
                      child: const ListTile(
                        leading: Icon(Icons.cleaning_services),
                        title: Text('Clear product caches (OFF + OBF)'),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/credits');
                      },
                      child: const ListTile(
                        leading: Icon(Icons.emoji_events_outlined),
                        title: Text('Credits'),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/allergyList');
                      },
                      child: const ListTile(
                        leading: Icon(Icons.warning_amber_rounded),
                        title: Text('My allergy items'),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/recalls');
                      },
                      child: const ListTile(
                        leading: Icon(Icons.report_problem),
                        title: Text('Recalled Products'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.system_update),
            tooltip: 'Check for Updates',
            onPressed: () => Navigator.pushNamed(context, '/update'),
          ),
        ],
      ),
  body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemController,
                    decoration: const InputDecoration(
                      labelText: 'Food Item',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
          child: TextField(
                    controller: _tagController,
                    decoration: const InputDecoration(
            labelText: 'Discomfort (optional)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      prefixText: '\$ ',
                    ),
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addItem,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: -8,
                children: [
                  _totalChip('Remaining', _totalRemaining),
                  _totalChip('Selected', _totalChecked),
                  _totalChip('All', _totalAll),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Empty-state helper to load regulars quickly
            if (_mainItems.isEmpty && _taggedItems.isEmpty)
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.history_toggle_off),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Regular items', style: TextStyle(fontWeight: FontWeight.w600)),
                            SizedBox(height: 2),
                            Text('Load items you buy frequently or adjust settings', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _showRegularItemsSettings,
                        icon: const Icon(Icons.settings),
                        label: const Text('Settings'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _loadRegularsNow,
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Load'),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  // Main grocery list
                  Expanded(
                    flex: 1, // Make both sides equal
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Main Grocery List',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _mainItems.isEmpty
                              ? const Text('No items.')
                              : ListView.builder(
                                  itemCount: _mainItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _mainItems[index];
                                    return GestureDetector(
                                      onLongPress: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Delete Item?'),
                                            content: Text('Remove "${item.name}" from your main list?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  setState(() {
                                                    _mainItems.removeAt(index);
                                                    _syncStoreFromCurrent();
                                                  });
                                                  Navigator.pop(context);
                                                },
                                                child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      child: CheckboxListTile(
                                        visualDensity: VisualDensity.compact,
                                        contentPadding: EdgeInsets.zero,
                                        value: item.checked,
                                        onChanged: (checked) {
                                          setState(() {
                                            item.checked = checked ?? false;
                                            _syncStoreFromCurrent();
                                          });
                                        },
                                        title: Row(
                                          children: [
                                            // Add the icon if available
                                            if (foodIcons.containsKey(item.name))
                                              Padding(
                                                padding: const EdgeInsets.only(right: 6.0),
                                                child: Icon(foodIcons[item.name], size: 18, color: Colors.blueGrey),
                                              ),
                                            Expanded(
                                              child: Text(
                                                item.name,
                                                style: item.checked
                                                    ? const TextStyle(
                                                        decoration: TextDecoration.lineThrough,
                                                        color: Colors.grey,
                                                        fontSize: 15,
                                                      )
                                                    : const TextStyle(fontSize: 15),
                                                overflow: TextOverflow.ellipsis, // Optional: fade or ellipsis for very long names
                                                maxLines: 2, // Optional: allow wrapping to 2 lines
                                              ),
                                            ),
                                            if (item.tag.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(left: 8.0),
                                                child: Icon(Icons.warning, color: Colors.red[700], size: 16),
                                              ),
                                            Padding(
                                              padding: const EdgeInsets.only(left: 8.0),
                                              child: InkWell(
                                                onTap: () => _editItemPrice(item),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    item.price > 0 ? _fmtCurrency(item.price) : 'Add price',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: item.price > 0 ? Colors.grey[800] : Theme.of(context).colorScheme.primary,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        subtitle: item.tag.isNotEmpty
                                            ? Text(
                                                item.tag.startsWith('Option Chosen for')
                                                    ? item.tag // Show only the tag for alternatives, no "Warning:"
                                                    : 'Warning: ${item.tag}',
                                                style: const TextStyle(color: Colors.red, fontSize: 13),
                                              )
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 16),
                  // Tagged foods list
                  Expanded(
                    flex: 1, // Make both sides equal
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tagged Foods',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _taggedItems.isEmpty
                              ? const Text('No tagged foods.')
                              : ListView.builder(
                                  itemCount: _taggedItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _taggedItems[index];
                                    return ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Colors.black,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Tag: ${item.tag}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.red,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: () => _editItemPrice(item),
                                            child: Padding(
                                              padding: const EdgeInsets.only(right: 6.0),
                                              child: Text(
                                                item.price > 0 ? _fmtCurrency(item.price) : 'Add price',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: item.price > 0 ? Colors.grey[700] : Theme.of(context).colorScheme.primary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add_shopping_cart, size: 20),
                                            tooltip: 'Add to main list',
                                            onPressed: () => _addTaggedToMain(item),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                            tooltip: 'Remove',
                                            onPressed: () {
                                              setState(() {
                                                _taggedItems.removeAt(index);
                                                _syncStoreFromCurrent();
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                      onLongPress: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Delete Tagged Food?'),
                                            content: Text('Remove "${item.name}" from your tagged foods?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  setState(() {
                                                    _taggedItems.removeAt(index);
                                                    _syncStoreFromCurrent();
                                                  });
                                                  Navigator.pop(context);
                                                },
                                                child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // Add this floatingActionButton for the Completed button at the bottom right
      floatingActionButton: allChecked
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.check_circle),
              label: const Text('Completed'),
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear List?'),
                    content: const Text('Are you sure you want to remove all completed items from your list?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Yes, clear list'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _uncheckAll();
                }
              },
            )
          : null,
    );
  }

  // ================= Regular items persistence & behavior =================
  Future<void> _showRegularInfoDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regular Items — How it works'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This feature helps you rebuild your list faster by remembering what you buy often.'),
              const SizedBox(height: 12),
              const Text('• Counting purchases: Items are counted when you tap "Completed" (checked items only).'),
              const SizedBox(height: 6),
              Text('• Becomes regular after $_regularMinCount purchases (configurable).'),
              const SizedBox(height: 6),
              Text('• Max items per load: $_regularMaxItems (configurable).'),
              const SizedBox(height: 6),
              Text('• Add mode: ${_regularAddMode == 'prompt' ? 'Ask which to add' : 'Add automatically'}. Change any time.'),
              const SizedBox(height: 6),
              Text('• Only when list is empty: ${_autoloadOnlyIfEmpty ? 'On' : 'Off'} (configurable).'),
              const SizedBox(height: 6),
              const Text('• Exclude list: Add items you never want autoloaded.'),
              const SizedBox(height: 12),
              const Text('Tip: Use the Regular Items menu in the top bar to Load now, open Settings, or Clear history.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showRegularItemsSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
  Future<void> _loadAutoLoadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoLoadRegulars = prefs.getBool(_kAutoLoadKey) ?? false;
      _regularMinCount = prefs.getInt(_kRegularThresholdKey) ?? _regularMinCount;
      _regularMaxItems = prefs.getInt(_kRegularMaxItemsKey) ?? _regularMaxItems;
      _regularAddMode = prefs.getString(_kRegularAddModeKey) ?? _regularAddMode;
      _autoloadOnlyIfEmpty = prefs.getBool(_kRegularOnlyIfEmptyKey) ?? _autoloadOnlyIfEmpty;
      final excl = prefs.getStringList(_kRegularExcludeKey) ?? const [];
      _regularExclude = excl.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    });
  }

  Future<void> _setAutoLoadSetting(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoLoadKey, enabled);
    setState(() {
      _autoLoadRegulars = enabled;
    });
    if (enabled) {
      final shown = prefs.getBool(_kRegularInfoShownKey) ?? false;
      if (!shown) {
        await _showRegularInfoDialog();
        await prefs.setBool(_kRegularInfoShownKey, true);
      }
    }
  }

  Future<Map<String, int>> _readCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCountsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeCounts(Map<String, int> counts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCountsKey, jsonEncode(counts));
  }

  Future<void> _incrementCountsFor(List<String> itemNames) async {
    if (itemNames.isEmpty) return;
    final counts = await _readCounts();
    for (final name in itemNames) {
      final key = name.trim();
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    await _writeCounts(counts);
  }

  Future<List<String>> _getRegulars({int? minCount, int? maxItems}) async {
    final counts = await _readCounts();
    final threshold = minCount ?? _regularMinCount;
    final cap = maxItems ?? _regularMaxItems;
    final list = counts.entries
        .where((e) => e.value >= threshold && !_regularExclude.contains(e.key))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(cap).map((e) => e.key).toList();
  }

  Future<void> _maybeAutoloadRegulars() async {
    if (!_autoLoadRegulars) return;
    if (_autoloadOnlyIfEmpty && (_mainItems.isNotEmpty || _taggedItems.isNotEmpty)) return;
    final regulars = await _getRegulars();
    if (regulars.isEmpty) return;
    if (_regularAddMode == 'prompt') {
      await _promptAddRegulars(regulars, reason: _autoloadOnlyIfEmpty ? 'List is empty' : 'Autoload enabled');
      return;
    }
    int added = 0;
    setState(() {
      for (final name in regulars) {
        if (_mainItems.any((i) => i.name.toLowerCase() == name.toLowerCase())) continue;
        _mainItems.add(_GroceryItem(name: name, tag: ''));
        added++;
      }
    });
    if (!mounted) return;
    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded $added regular item${added == 1 ? '' : 's'}')),
      );
    }
  }

  Future<void> _loadRegularsNow() async {
    final regulars = await _getRegulars();
    if (regulars.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No regular items yet. Shop a few times first.')),
      );
      return;
    }
    if (_regularAddMode == 'prompt') {
      await _promptAddRegulars(regulars, reason: 'Load now');
    } else {
      int added = 0;
      setState(() {
        for (final name in regulars) {
          if (_mainItems.any((i) => i.name.toLowerCase() == name.toLowerCase())) continue;
          _mainItems.add(_GroceryItem(name: name, tag: ''));
          added++;
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(added == 0 ? 'All regular items already on your list.' : 'Added $added regular item${added == 1 ? '' : 's'}')),
      );
    }
  }

  Future<void> _clearRegularCounts() async {
    await _writeCounts({});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Regular item history cleared.')),
    );
  }

  void _showRegularItemsSettings() {
    showDialog(
      context: context,
      builder: (context) {
        bool localAuto = _autoLoadRegulars;
        int localThreshold = _regularMinCount;
        int localMaxItems = _regularMaxItems;
        String localAddMode = _regularAddMode;
        bool localOnlyIfEmpty = _autoloadOnlyIfEmpty;
        final TextEditingController exclController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Regular Items'),
            content: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Auto-load regularly bought items'),
                  subtitle: const Text('Adds frequent items when the list is empty'),
                  value: localAuto,
                  onChanged: (v) {
                    setLocal(() => localAuto = v);
                    _setAutoLoadSetting(v);
                  },
                ),
                const Divider(),
                // Add mode
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Add mode'),
                  subtitle: const Text('Choose how regulars are added'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'auto',
                        label: Text('Auto-add'),
                        icon: Icon(Icons.flash_auto),
                      ),
                      ButtonSegment<String>(
                        value: 'prompt',
                        label: Text('Ask each time'),
                        icon: Icon(Icons.help_outline),
                      ),
                    ],
                    selected: {localAddMode},
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        final cs = Theme.of(context).colorScheme;
                        return states.contains(WidgetState.selected)
                            ? cs.primary
                            : cs.surfaceContainerHighest;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        final cs = Theme.of(context).colorScheme;
                        return states.contains(WidgetState.selected)
                            ? cs.onPrimary
                            : cs.onSurface;
                      }),
                      textStyle: WidgetStateProperty.resolveWith((states) {
                        return TextStyle(
                          fontWeight: states.contains(WidgetState.selected)
                              ? FontWeight.w600
                              : FontWeight.w500,
                        );
                      }),
                      elevation: WidgetStateProperty.resolveWith((states) {
                        return states.contains(WidgetState.selected) ? 2.0 : 0.0;
                      }),
                      side: WidgetStateProperty.resolveWith((states) {
                        final cs = Theme.of(context).colorScheme;
                        final color = states.contains(WidgetState.selected) ? cs.primary : cs.outline;
                        final width = states.contains(WidgetState.selected) ? 2.0 : 1.2;
                        return BorderSide(color: color, width: width);
                      }),
                      overlayColor: WidgetStateProperty.resolveWith((states) {
                        final cs = Theme.of(context).colorScheme;
                        if (states.contains(WidgetState.pressed)) {
                          return cs.primary.withValues(alpha: 0.12);
                        }
                        if (states.contains(WidgetState.hovered)) {
                          return cs.primary.withValues(alpha: 0.08);
                        }
                        return null;
                      }),
                    ),
                    onSelectionChanged: (selection) async {
                      final v = selection.firstOrNull ?? localAddMode;
                      setLocal(() => localAddMode = v);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString(_kRegularAddModeKey, v);
                      setState(() => _regularAddMode = v);
                    },
                  ),
                ),
                const Divider(),
                // Only if empty
                SwitchListTile(
                  title: const Text('Only when list is empty'),
                  value: localOnlyIfEmpty,
                  onChanged: (v) async {
                    setLocal(() => localOnlyIfEmpty = v);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool(_kRegularOnlyIfEmptyKey, v);
                    setState(() => _autoloadOnlyIfEmpty = v);
                  },
                ),
                const Divider(),
                // Threshold
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Regular threshold'),
                  subtitle: const Text('Times purchased before it becomes regular'),
                  trailing: DropdownButton<int>(
                    value: localThreshold,
                    items: [1,2,3,4,5,6,7,8,9,10]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v.toString())))
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      setLocal(() => localThreshold = v);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt(_kRegularThresholdKey, v);
                      setState(() => _regularMinCount = v);
                    },
                  ),
                ),
                // Max items
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Max items to add'),
                  trailing: DropdownButton<int>(
                    value: localMaxItems,
                    items: const [5,10,15,20,30,50]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v.toString())))
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      setLocal(() => localMaxItems = v);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt(_kRegularMaxItemsKey, v);
                      setState(() => _regularMaxItems = v);
                    },
                  ),
                ),
                const Divider(),
                // Exclude list management
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Exclude items (never autoload):', style: Theme.of(context).textTheme.bodyMedium),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: -8,
      children: _regularExclude.map((e) => InputChip(
        label: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
        onDeleted: () async {
                          final newSet = {..._regularExclude}..remove(e);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setStringList(_kRegularExcludeKey, newSet.toList());
                          setLocal(() {});
                          setState(() => _regularExclude = newSet);
                        },
                      )).toList(),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: exclController,
                        decoration: const InputDecoration(hintText: 'Item name', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final name = exclController.text.trim();
                        if (name.isEmpty) return;
                        final newSet = {..._regularExclude, name};
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setStringList(_kRegularExcludeKey, newSet.toList());
                        exclController.clear();
                        setLocal(() {});
                        setState(() => _regularExclude = newSet);
                      },
                      icon: const Icon(Icons.block),
                      label: const Text('Exclude'),
                    ),
                  ],
                ),
              ],
            ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await _loadRegularsNow();
                },
                icon: const Icon(Icons.playlist_add),
                label: const Text('Load now'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await _clearRegularCounts();
                },
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                label: const Text('Clear history'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _promptAddRegulars(List<String> candidates, {String? reason}) async {
    // Filter out items already present
    final existing = _mainItems.map((e) => e.name.toLowerCase()).toSet();
    final filtered = candidates.where((e) => !existing.contains(e.toLowerCase())).toList();
    if (filtered.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All regular items already on your list.')));
      return;
    }
    final selected = <String>{...filtered};
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add regular items?'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reason != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(reason, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 320,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final name = filtered[i];
                      return CheckboxListTile(
                        dense: true,
                        title: Text(name),
                        value: selected.contains(name),
                        onChanged: (v) {
                          setLocal(() {
                            if (v == true) {
                              selected.add(name);
                            } else {
                              selected.remove(name);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  for (final name in selected) {
                    if (_mainItems.any((i) => i.name.toLowerCase() == name.toLowerCase())) continue;
                    _mainItems.add(_GroceryItem(name: name, tag: ''));
                  }
                });
                Navigator.pop(context);
              },
              icon: const Icon(Icons.add),
              label: Text('Add ${selected.length}')
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getMoreSpecificAlternatives(String food) {
    switch (food) {
      case 'Milk':
        return [
          'Oat milk (best for coffee/cereal)',
          'Almond milk (nutty flavor, good for baking)',
          'Soy milk (high protein, good for cooking)',
          'Coconut milk (rich, good for curries/desserts)',
        ];
      case 'Eggs':
        return [
          'Flaxseed meal (best for baking, 1 tbsp flax + 3 tbsp water = 1 egg)',
          'Chia seeds (similar to flax, 1 tbsp chia + 3 tbsp water = 1 egg)',
          'Unsweetened applesauce (¼ cup = 1 egg, for sweet recipes)',
          'Commercial egg replacer (follow package instructions)',
        ];
      case 'Peanuts':
        return [
          'Sunflower seed butter (nut-free, similar texture)',
          'Soy nut butter (if not allergic to soy)',
          'Pea butter (legume-based, nut-free)',
        ];
      case 'Wheat':
        return [
          'Rice flour (neutral, good for baking)',
          'Oat flour (mild flavor, good for pancakes)',
          'Almond flour (nutty, moist, for cakes/cookies)',
          'Certified gluten-free flour blends',
        ];
      // Add more cases as needed for other foods
      default:
        return ['No more specific alternatives found.'];
    }
  }

  Future<void> checkForGithubReleasesUpdate(BuildContext context) async {
  final url = 'https://api.github.com/repos/WoofahRayetCode/grocery_guardian/releases/latest';
  try {
    final response = await SecureHttp.instance.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final tagName = data['tag_name'] ?? 'Unknown';
      final htmlUrl = data['html_url'];
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Update Available'),
          content: Text('A new release is available: $tagName\nWould you like to view or download it?\n\nYou can also force download the current version.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final uri = Uri.parse(htmlUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open release link.')),
                  );
                }
              },
              child: const Text('View/Download'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                // Force download the current APK asset from the latest release
                final assets = data['assets'] as List<dynamic>? ?? [];
                final apkAsset = assets.firstWhere(
                  (a) => (a['name'] as String?)?.endsWith('.apk') ?? false,
                  orElse: () => null,
                );
                if (apkAsset != null) {
                  final apkUrl = apkAsset['browser_download_url'];
                  final uri = Uri.parse(apkUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not download APK.')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No APK found in this release.')),
                  );
                }
              },
              child: const Text('Force Download APK'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check for updates: ${response.statusCode}')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error checking for updates: $e')),
    );
  }
}
}

class _GroceryItem {
  final String name;
  final String tag;
  double price;
  bool checked;

  _GroceryItem({required this.name, required this.tag, this.price = 0.0}) : checked = false;
}

class FoodReactionDatabase {
  static final List<FoodReaction> commonReactions = [
    FoodReaction(food: 'Milk', reactions: ['Lactose intolerance', 'Milk allergy', 'Digestive upset']),
    FoodReaction(food: 'Eggs', reactions: ['Egg allergy', 'Skin rash']),
    FoodReaction(food: 'Peanuts', reactions: ['Peanut allergy', 'Anaphylaxis']),
    FoodReaction(food: 'Tree nuts', reactions: ['Nut allergy', 'Anaphylaxis']),
    FoodReaction(food: 'Wheat', reactions: ['Gluten intolerance', 'Celiac disease', 'Wheat allergy']),
    FoodReaction(food: 'Soy', reactions: ['Soy allergy']),
    FoodReaction(food: 'Fish', reactions: ['Fish allergy']),
    FoodReaction(food: 'Shellfish', reactions: ['Shellfish allergy']),
    FoodReaction(food: 'Strawberries', reactions: ['Oral allergy syndrome']),
    FoodReaction(food: 'Tomatoes', reactions: ['Oral allergy syndrome']),
    FoodReaction(food: 'Sesame', reactions: ['Sesame allergy']),
    // Add more as needed
  ];

  static List<String> getReactionsForFood(String foodName) {
    final match = commonReactions.firstWhere(
      (entry) => entry.food.toLowerCase() == foodName.toLowerCase(),
      orElse: () => FoodReaction(food: foodName, reactions: []),
    );
    return match.reactions;
  }
}

class FoodReaction {
  final String food;
  final List<String> reactions;
  FoodReaction({required this.food, required this.reactions});
}

// New screen for allergy info
class AllergyInfoScreen extends StatelessWidget {
  const AllergyInfoScreen({super.key});

  static final Map<String, String> allergyLinks = {
    'Milk': 'https://www.foodallergy.org/living-food-allergies/food-allergy-essentials/common-allergens/milk',
    'Eggs': 'https://www.foodallergy.org/living-food-allergies/food-allergy-essentials/common-allergens/egg',
    'Peanuts': 'https://www.foodallergy.org/living-food-allergies/food-allergy-essentials/common-allergens/peanut',
    'Tree nuts': 'https://www.foodallergy.org/living-food-allergies/food-allergy-essentials/common-allergens/tree-nut',
    'Wheat': 'https://www.foodallergy.org/living-food-allergies/food-allergy-essentials/common-allergens/wheat',
    'Soy': 'https://www.foodallergy.org/living-food-allergies/food-allergy-essentials/common-allergens/soy',
    'Fish': 'https://www.foodallergy.org/living-food-allergies/food-allergy-essentials/common-allergens/fish',
    'Shellfish': 'https://www.foodallergy.org/living-food-allergies/food-allergy-essentials/common-allergens/shellfish',
    'Strawberries': 'https://www.aaaai.org/tools-for-the-public/conditions-library/allergies/food-allergy',
    'Tomatoes': 'https://www.aaaai.org/tools-for-the-public/conditions-library/allergies/food-allergy',
    'Sesame': 'https://www.foodallergy.org/living-food-allergies/food-allergy-essentials/common-allergens/sesame',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Common Food Allergy Reactions'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: FoodReactionDatabase.commonReactions.length,
        itemBuilder: (context, index) {
          final reaction = FoodReactionDatabase.commonReactions[index];
          final link = allergyLinks[reaction.food];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              title: Text(
                reaction.food,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...reaction.reactions.map((r) => Text('\u2022 $r', style: const TextStyle(fontSize: 14))),
                  if (link != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () async {
                              final uri = Uri.parse(link);
                              // List of common Android browser package names
                              const browsers = [
                                'app.vanadium.browser', // Vanadium (GrapheneOS)
                                'com.android.chrome',   // Chrome
                                'org.mozilla.firefox',  // Firefox
                                'com.opera.browser',    // Opera
                                'com.brave.browser',    // Brave
                                'com.microsoft.emmx',   // Edge
                              ];
                              bool launched = false;
                              for (final pkg in browsers) {
                                final intent = AndroidIntent(
                                  action: 'action_view',
                                  data: uri.toString(),
                                  package: pkg,
                                );
                                try {
                                  await intent.launch();
                                  launched = true;
                                  break;
                                } catch (_) {}
                              }
                              if (!launched) {
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Could not open link.')),
                                  );
                                }
                              }
                            },
                            child: Text(
                              'Learn more',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () async {
                              // Open OFF search for this allergen term
                              final q = Uri.encodeComponent(reaction.food);
                              final uri = Uri.parse('https://world.openfoodfacts.org/cgi/search.pl?search_terms=$q&search_simple=1');
                              try {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } catch (_) {}
                            },
                            child: Text(
                              'Search OFF',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: kAdsEnabled ? const SizedBox(height: 52, child: AdBanner()) : null,
    );
  }
}

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});
  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  gma.BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (kAdsEnabled) {
      _ad = gma.BannerAd(
        size: gma.AdSize.banner,
        adUnitId: kBannerAdUnitId,
        listener: gma.BannerAdListener(
          onAdLoaded: (ad) => setState(() => _loaded = true),
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            setState(() => _loaded = false);
          },
        ),
        request: const gma.AdRequest(),
      )..load();
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kAdsEnabled || !_loaded || _ad == null) return const SizedBox.shrink();
    return gma.AdWidget(ad: _ad!);
  }
}

// Per-profile user allergy items management
class UserAllergyListScreen extends StatefulWidget {
  const UserAllergyListScreen({super.key});

  @override
  State<UserAllergyListScreen> createState() => _UserAllergyListScreenState();
}

class _UserAllergyListScreenState extends State<UserAllergyListScreen> {
  List<String> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Access parent state via closest GroceryListScreen state
    final state = context.findAncestorStateOfType<_GroceryListScreenState>();
    if (state == null) return;
    final items = await state._getUserAllergyList();
    setState(() => _items = items);
  }

  Future<void> _remove(String key) async {
    final state = context.findAncestorStateOfType<_GroceryListScreenState>();
    if (state == null) return;
    await state._removeUserAllergyPreference(key);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Removed from allergy list')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My allergy items')),
      body: _items.isEmpty
          ? const Center(child: Text('No saved allergy items for this profile.'))
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final name = _items[i];
                return ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text(name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => _remove(name),
                  ),
                );
              },
            ),
    );
  }
}

// New screen for low-income resources
class LowIncomeResourcesScreen extends StatefulWidget {
  const LowIncomeResourcesScreen({super.key});

  @override
  State<LowIncomeResourcesScreen> createState() => _LowIncomeResourcesScreenState();
}

class _LowIncomeResourcesScreenState extends State<LowIncomeResourcesScreen> {
  final TextEditingController _zipController = TextEditingController();
  String? _zip;
  bool _loading = false;
  List<String> _resources = [];

  // Dummy resource lookup. Replace with API call or more data as needed.
  Future<void> _fetchResources(String zip) async {
    setState(() {
      _loading = true;
      _resources = [];
    });
    await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
    if (!mounted) return; // Add this line

    // Example: You can expand this with real data or API integration
    final Map<String, List<String>> resourceData = {
      '10001': [
        'NYC Food Bank: https://www.foodbanknyc.org/',
        'SNAP Info: https://www.ny.gov/services/apply-snap',
        'Local Pantry: 123 Main St, New York, NY',
      ],
      '94110': [
        'SF-Marin Food Bank: https://www.sfmfoodbank.org/',
        'CalFresh (SNAP): https://www.getcalfresh.org/',
        'Mission Food Hub: 701 Alabama St, San Francisco, CA',
      ],
    };

    setState(() {
      _resources = resourceData[zip] ??
          [
            'Find a food pantry: https://www.feedingamerica.org/find-your-local-foodbank',
            'Apply for SNAP: https://www.fns.usda.gov/snap/state-directory',
            'Call 211 for local assistance programs',
          ];
      _loading = false;
      _zip = zip;
    });
  }

  @override
  void dispose() {
    _zipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Low Income Resources'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                       const Text(
              'Enter your ZIP code to find local food and assistance resources:',
              style: TextStyle(fontSize: 16),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _zipController,
                    keyboardType: TextInputType.number,
                    maxLength: 5,
                    decoration: const InputDecoration(
                      labelText: 'ZIP Code',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final zip = _zipController.text.trim();
                    if (zip.length == 5 && int.tryParse(zip) != null) {
                      _fetchResources(zip);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid 5-digit ZIP code.')),
                      );
                    }
                  },
                  child: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_resources.isNotEmpty)
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      'Resources for ZIP $_zip:',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    ..._resources.map((r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: InkWell(
                            onTap: () => _handleResourceTap(r.split(' ').last),
                            child: Text(
                              r,
                              style: TextStyle(
                                color: r.contains('http') ? Theme.of(context).colorScheme.primary : Colors.black,
                                decoration: r.contains('http') ? TextDecoration.underline : null,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        )),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper to handle resource link taps
  Future<void> _handleResourceTap(String url) async {
    if (url.startsWith('http')) {
      final uri = Uri.parse(url);
      const browsers = [
        'app.vanadium.browser',
        'com.android.chrome',
        'org.mozilla.firefox',
        'com.opera.browser',
        'com.brave.browser',
        'com.microsoft.emmx',
      ];
      bool launched = false;
      for (final pkg in browsers) {
        final intent = AndroidIntent(
          action: 'action_view',
          data: uri.toString(),
          package: pkg,
        );
        try {
          await intent.launch();
          launched = true;
          break;
        } catch (e) {
          if (kDebugMode) debugPrint('Browser launch error ($pkg): $e');
        }
      }
      if (!launched) {
        try {
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            if (!mounted) return;
            if (kDebugMode) debugPrint('Could not open link: $url');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open link.')),
            );
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Error launching url: $e');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error launching url: $e')),
          );
        }
      }
    }
  }
}

// New screen for app updates
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

// Simple Credits screen
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Credits')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const ListTile(
            leading: Icon(Icons.emoji_events_outlined),
            title: Text('Grocery Guardian'),
            subtitle: Text('Developed by WoofahRayetCode'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Open Food Facts'),
            subtitle: const Text('Product data for food (CC-BY-SA). openfoodfacts.org'),
            onTap: () async {
              final uri = Uri.parse('https://world.openfoodfacts.org/');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Open Beauty Facts'),
            subtitle: const Text('Product data for cosmetics/personal care (ODbL/CC-BY-SA). openbeautyfacts.org'),
            onTap: () async {
              final uri = Uri.parse('https://world.openbeautyfacts.org/');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'This app uses public, community-maintained datasets. Trademarks and data belong to their respective owners.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('Open source'),
            subtitle: Text('GitHub: WoofahRayetCode/grocery_guardian'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.design_services),
            title: Text('Icons'),
            subtitle: Text('Material Icons'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.favorite_outline),
            title: Text('Special Thanks'),
            subtitle: Text('Community testers, contributors, and supporters who helped shape the app.'),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('NepheliaNyx'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PersonThanksScreen(name: 'NepheliaNyx'),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Darh_JarJar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PersonThanksScreen(name: 'Darh_JarJar'),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Pam'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PersonThanksScreen(name: 'Pam'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// Simple details page for a person in Special Thanks
class PersonThanksScreen extends StatelessWidget {
  final String name;
  const PersonThanksScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.favorite, color: Colors.redAccent),
                const SizedBox(width: 8),
                Text(
                  'Special Thanks',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Huge thanks to $name for support and contributions to Grocery Guardian.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateScreenState extends State<UpdateScreen> {
  bool _loading = false;
  String? _latestTag;
  String? _releaseNotes;
  String? _apkUrl;
  String? _error;
  String? _appVersion; // Add this field

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = info.version;
    });
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _loading = true;
      _error = null;
      _latestTag = null;
      _releaseNotes = null;
      _apkUrl = null;
    });
    final url = 'https://api.github.com/repos/WoofahRayetCode/grocery_guardian/releases/latest';
    try {
      final response = await SecureHttp.instance.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _latestTag = data['tag_name'] ?? 'Unknown';
          _releaseNotes = data['body'] ?? 'No release notes.';
          final assets = data['assets'] as List<dynamic>? ?? [];
          final apkAsset = assets.firstWhere(
            (a) => (a['name'] as String?)?.endsWith('.apk') ?? false,
            orElse: () => null,
          );
          _apkUrl = apkAsset != null ? apkAsset['browser_download_url'] : null;
        });
      } else {
        setState(() {
          _error = 'Failed to check for updates: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error checking for updates: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Update')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_appVersion != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Text(
                  'Current App Version: $_appVersion',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ElevatedButton.icon(
              icon: const Icon(Icons.system_update),
              label: const Text('Check for Updates'),
              onPressed: _loading ? null : _checkForUpdate,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open APK in browser'),
              onPressed: (_loading || _apkUrl == null)
                  ? null
                  : () async {
                      final uri = Uri.parse(_apkUrl!);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('View Releases on GitHub'),
              onPressed: () async {
                final uri = Uri.parse('https://github.com/WoofahRayetCode/grocery_guardian/releases');
                try {
                  // Try to launch without canLaunchUrl for reliability
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  // Show error with details
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not open GitHub Releases. Error: ${e.toString()}')),
                  );
                }
              },
            ),
            const SizedBox(height: 24),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_latestTag != null)
              Text('Latest Release: $_latestTag', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (_releaseNotes != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Text(_releaseNotes!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const String appBuildTime = '2024-06-23T12:00:00Z'; // Update this for each build
final DateTime appBuildDateTime = DateTime.parse(appBuildTime);

Future<DateTime?> fetchLatestReleaseTime() async {
  final url = 'https://api.github.com/repos/WoofahRayetCode/grocery_guardian/releases/latest';
  final response = await SecureHttp.instance.get(Uri.parse(url));
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return DateTime.parse(data['published_at']);
  }
  return null;
}

Future<void> checkForTimeBasedUpdate(BuildContext context) async {
  final latestReleaseTime = await fetchLatestReleaseTime();
  if (latestReleaseTime == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not check for updates.')),
    );
    return;
  }

  if (latestReleaseTime.isAfter(appBuildDateTime)) {
    // Show update available dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Available'),
        content: Text(
          'A new version was released on ${latestReleaseTime.toLocal()}.\nWould you like to update?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final url = 'https://github.com/WoofahRayetCode/grocery_guardian/releases/latest';
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('App is up to date.')),
    );
  }
}

// In-app APK download/install removed to reduce security flags and VT false positives.

Future<void> _showProductDetails(BuildContext context, ScannedProduct product) async {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name ?? 'Product', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if ((product.imageUrl ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(product.imageUrl!, height: 180, fit: BoxFit.cover),
                ),
              ],
              if ((product.brand ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Brand: ${product.brand}'),
              ],
              if ((product.nutriScore ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Nutri-Score: ${product.nutriScore!.toUpperCase()}'),
              ],
              if ((product.usageHint ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Use: ${product.usageHint}', style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
              if (product.babyCautions.isNotEmpty || product.maternityCautions.isNotEmpty || product.babyRecommendations.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Advisories', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: -8,
                  children: [
                    ...product.babyCautions.map((c) => Chip(
                      label: Text(c),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
                      side: BorderSide(color: Theme.of(context).colorScheme.secondary, width: 1.0),
                    )),
                    ...product.maternityCautions.map((c) => Chip(
                      label: Text(c),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer),
                      side: BorderSide(color: Theme.of(context).colorScheme.tertiary, width: 1.0),
                    )),
                    ...product.babyRecommendations.map((c) => Chip(
                      label: Text(c),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
                    )),
                  ],
                ),
              ],
              if ((product.ingredientsText ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Ingredients', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(product.ingredientsText!),
              ],
              if (product.nutriments.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Nutriments (per 100g)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: -8,
                  children: [
                    _nutriChip(context, product.nutriments, 'energy-kcal_100g', 'kcal'),
                    _nutriChip(context, product.nutriments, 'fat_100g', 'g fat'),
                    _nutriChip(context, product.nutriments, 'sugars_100g', 'g sugars'),
                    _nutriChip(context, product.nutriments, 'salt_100g', 'g salt'),
                    _nutriChip(context, product.nutriments, 'proteins_100g', 'g protein'),
                  ].where((w) => w != null).cast<Widget>().toList(),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget? _nutriChip(BuildContext context, Map<String, dynamic> n, String key, String label) {
  final v = n[key];
  if (v == null) return null;
  final num? value = v is num ? v : num.tryParse(v.toString());
  if (value == null) return null;
  final cs = Theme.of(context).colorScheme;
  return Chip(
    label: Text('${value.toStringAsFixed(1)} $label', style: TextStyle(color: cs.onSurface)),
    backgroundColor: cs.surfaceContainerHighest,
    side: BorderSide(color: cs.outline, width: 1.0),
    visualDensity: VisualDensity.compact,
  );
}

// Recall Management Screen
class RecallManagementScreen extends StatefulWidget {
  const RecallManagementScreen({super.key});

  @override
  State<RecallManagementScreen> createState() => _RecallManagementScreenState();
}

class _RecallManagementScreenState extends State<RecallManagementScreen> {
  List<RecallItem> _recalls = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecalls();
  }

  Future<void> _loadRecalls() async {
    setState(() => _loading = true);
    final recalls = await RecallService.loadRecalledProducts();
    if (!mounted) return;
    setState(() {
      _recalls = recalls;
      _loading = false;
    });
  }

  Future<void> _refreshFromAPI() async {
    setState(() => _loading = true);
    await RecallService.refreshRecallData();
    await _loadRecalls();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recall data refreshed from FDA')),
    );
  }

  Future<void> _markAsSafe(RecallItem item) async {
    await RecallService.markRecallSafe(item.id);
    await _loadRecalls();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.productName} marked as safe')),
    );
  }

  Future<void> _addManualRecall() async {
    final nameController = TextEditingController();
    final brandController = TextEditingController();
    final reasonController = TextEditingController();
    final barcodeController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Recalled Product'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Product Name *',
                  hintText: 'e.g., XYZ Brand Peanut Butter',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: brandController,
                decoration: const InputDecoration(
                  labelText: 'Brand',
                  hintText: 'Optional',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason for Recall',
                  hintText: 'e.g., Salmonella contamination',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: barcodeController,
                decoration: const InputDecoration(
                  labelText: 'Barcode (optional)',
                  hintText: 'If known',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Product name is required')),
                );
                return;
              }
              final brand = brandController.text.trim();
              final reason = reasonController.text.trim();
              final barcode = barcodeController.text.trim();
              
              await RecallService.addManualRecall(
                productName: name,
                brand: brand.isNotEmpty ? brand : null,
                reason: reason.isNotEmpty ? reason : null,
                barcodes: barcode.isNotEmpty ? [barcode] : null,
              );
              
              Navigator.pop(context);
              await _loadRecalls();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added $name to recall list')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recalled Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh from FDA',
            onPressed: _refreshFromAPI,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add manual recall',
            onPressed: _addManualRecall,
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'clear') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear All Recalls?'),
                    content: const Text('This will remove all recalled products from your list. Continue?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Clear All', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await RecallService.clearAllRecalls();
                  await _loadRecalls();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All recalls cleared')),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_forever, color: Colors.red),
                  title: Text('Clear all recalls'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _recalls.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 64, color: Colors.green[300]),
                        const SizedBox(height: 16),
                        const Text(
                          'No recalled products',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Products you scan will be checked against your recall list. Add items manually or refresh from FDA.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _refreshFromAPI,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Check FDA for Recalls'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _recalls.length,
                  itemBuilder: (context, index) {
                    final recall = _recalls[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ExpansionTile(
                        leading: Icon(Icons.warning, color: Theme.of(context).colorScheme.error),
                        title: Text(
                          recall.productName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: recall.brand != null ? Text(recall.brand!) : null,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (recall.reason != null) ...[
                                  const Text('Reason:', style: TextStyle(fontWeight: FontWeight.w600)),
                                  Text(recall.reason!, style: const TextStyle(color: Colors.red)),
                                  const SizedBox(height: 8),
                                ],
                                if (recall.datePublished != null) ...[
                                  Text('Recall Date: ${recall.datePublished}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  const SizedBox(height: 8),
                                ],
                                if (recall.affectedBarcodes.isNotEmpty) ...[
                                  const Text('Affected Barcodes:', style: TextStyle(fontWeight: FontWeight.w600)),
                                  Text(recall.affectedBarcodes.join(', ')),
                                  const SizedBox(height: 8),
                                ],
                                if (recall.description != null && recall.description!.isNotEmpty) ...[
                                  const Text('Description:', style: TextStyle(fontWeight: FontWeight.w600)),
                                  Text(recall.description!),
                                  const SizedBox(height: 8),
                                ],
                                Text('Added: ${recall.addedAt.toString().split('.')[0]}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _markAsSafe(recall),
                                      icon: const Icon(Icons.check_circle, color: Colors.green),
                                      label: const Text('Mark as Safe', style: TextStyle(color: Colors.green)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
