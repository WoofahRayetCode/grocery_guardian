import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Add this import

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const GroceryListScreen(),
      routes: {
        '/allergyInfo': (context) => const AllergyInfoScreen(),
        '/resources': (context) => const LowIncomeResourcesScreen(), // <-- Add this line
      },
    );
  }
}

class GroceryListScreen extends StatefulWidget {
  const GroceryListScreen({super.key});

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grocery List'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Allergy Info',
            onPressed: () {
              Navigator.pushNamed(context, '/allergyInfo');
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Uncheck All',
            onPressed: _uncheckAll,
          ),
          IconButton(
            icon: const Icon(Icons.volunteer_activism),
            tooltip: 'Low Income Resources',
            onPressed: () {
              Navigator.pushNamed(context, '/resources');
            },
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: "Developer's GitHub",
            onPressed: () async {
              final uri = Uri.parse('https://github.com/WoofahRayetCode');
              // Try common browsers first
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
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open GitHub link.')),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.privacy_tip),
            tooltip: 'View App Permissions',
            onPressed: () {
              showPermissionsDialog(context);
            },
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
            const SizedBox(height: 16),
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
}

class _GroceryItem {
  final String name;
  final String tag;
  bool checked;
  _GroceryItem({required this.name, required this.tag, this.checked = false});
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
                            onTap: () async {
                              final uri = Uri.tryParse(r.split(' ').last);
                              if (uri != null && uri.isAbsolute) {
                                // Try common browsers first
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
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Could not open link.')),
                                    );
                                  }
                                }
                              }
                            },
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
