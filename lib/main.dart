// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // Add this import at the top if not present

void main() {
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
    return MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: _themeMode,
      home: GroceryListScreen(
        onThemeChanged: _setTheme,
        currentThemeMode: _themeMode,
      ),
      routes: {
        '/allergyInfo': (context) => const AllergyInfoScreen(),
        '/resources': (context) => const LowIncomeResourcesScreen(),
        '/update': (context) => const UpdateScreen(), // Add this line
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
  final List<_GroceryItem> _mainItems = [];
  final List<_GroceryItem> _taggedItems = [];
  final TextEditingController _itemController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();

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

  void _addItem() async {
    final name = _itemController.text.trim();
    final tag = _tagController.text.trim();

    final commonReactions = FoodReactionDatabase.getReactionsForFood(name);

    if (commonReactions.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Allergy Warning'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"$name" is a common food allergen!',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...commonReactions.map((r) => Text('• $r', style: const TextStyle(color: Colors.red))),
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
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, for someone else'),
            ),
          ],
        ),
      );
      if (!mounted) return; // <-- Add this line

      if (confirmed != true) {
        // Recommend alternatives if available
        final alternatives = allergyAlternatives[name];
        _itemController.clear();
        _tagController.clear();

        if (alternatives != null && alternatives.isNotEmpty) {
          bool needsMoreSpecifics = false;
          await showDialog(
            context: context,
            builder: (context) {
              return StatefulBuilder(
                builder: (context, setState) => AlertDialog(
                  title: const Text('Try These Alternatives'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Consider these safe alternatives for "$name":'),
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
      setState(() {
        if (tag.isNotEmpty) {
          _taggedItems.add(_GroceryItem(name: name, tag: tag));
        } else {
          _mainItems.add(_GroceryItem(name: name, tag: tag));
        }
        _itemController.clear();
        _tagController.clear();
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
      _mainItems.add(_GroceryItem(name: item.name, tag: item.tag));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Warning: "${item.name}" has a discomfort tag: "${item.tag}"',
          style: const TextStyle(color: Colors.yellow),
        ),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _uncheckAll() {
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
    });
  }

  @override
  void dispose() {
    _itemController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _showPermissionsOnFirstLaunch();
  }

  // Add this widget for the permissions info dialog:
  void showPermissionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('App Permissions & Privacy'),
        content: const Text(
          'This app does not collect or share your personal data.\n\n'
          'Permissions used:\n'
          '- Internet: To open external links for allergy info and resources.\n'
          '- No location, contacts, or storage access is requested.\n\n'
          'We respect your privacy.',
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

  @override
  Widget build(BuildContext context) {
    final allChecked = _mainItems.isNotEmpty && _mainItems.every((item) => item.checked);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grocery List'),
        actions: [
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
                          if (!mounted) return; // Guard State.context use
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } else {
                            if (!mounted) return; // Guard State.context use
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Could not open GitHub link.')),
                            );
                          }
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
                      labelText: 'Discomfort Tag (optional)',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addItem,
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                  _uncheckAll();
                }
              },
            )
          : null,
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
    final response = await http.get(Uri.parse(url));
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
  bool checked;

  _GroceryItem({required this.name, required this.tag}) : checked = false;
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
                  ...reaction.reactions.map((r) => Text('• $r', style: const TextStyle(fontSize: 14))),
                  if (link != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: GestureDetector(
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
                          // Fallback to default browser if none of the above worked
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
                    ),
                ],
              ),
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

class _UpdateScreenState extends State<UpdateScreen> {
  bool _loading = false;
  String? _latestTag;
  String? _releaseNotes;
  String? _apkUrl;
  String? _error;

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
      final response = await http.get(Uri.parse(url));
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

  Future<void> _forceDownloadApk() async {
    if (_apkUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No APK found in this release.')),
      );
      return;
    }
    final uri = Uri.parse(_apkUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not download APK.')),
      );
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
            ElevatedButton.icon(
              icon: const Icon(Icons.system_update),
              label: const Text('Check for Updates'),
              onPressed: _loading ? null : _checkForUpdate,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Force Download Current APK'),
              onPressed: _loading ? null : _forceDownloadApk,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('View Releases on GitHub'),
              onPressed: () async {
                final uri = Uri.parse('https://github.com/WoofahRayetCode/grocery_guardian/releases');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
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