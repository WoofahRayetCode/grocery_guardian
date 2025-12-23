import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/product_lookup.dart';

class ScanProductScreen extends StatefulWidget {
  const ScanProductScreen({super.key});

  @override
  State<ScanProductScreen> createState() => _ScanProductScreenState();
}

class _ScanProductScreenState extends State<ScanProductScreen> {
  bool _handled = false;
  bool _loading = false;
  
  // Controller for better lifecycle management and resource optimization
  late final MobileScannerController _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal, // Balance between speed and battery
      detectionTimeoutMs: 500, // Avoid processing same barcode too quickly
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Barcode')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) async {
              if (_handled) return;
              final barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;
              // Prefer numeric EAN/UPC codes when multiple are detected
              final numeric = barcodes
                  .map((b) => b.rawValue)
                  .whereType<String>()
                  .firstWhere(
                    (v) => RegExp(r'^\d{8,14} ?$').hasMatch(v),
                    orElse: () => (barcodes.first.rawValue ?? ''),
                  )
                  .replaceAll('\u0000', '');
              final raw = numeric.trim();
              if (raw.isEmpty) return;
              
              // Capture context references before async operations
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              
              setState(() {
                _handled = true;
                _loading = true;
              });

              // Fetch product (food first, then beauty)
              final product = await ProductLookupService.fetchAnyByBarcode(raw);
              if (!mounted) return;

              if (product != null) {
                navigator.pop(product);
                return;
              }

              // Not found: offer a search-by-name fallback and allow retry
              setState(() => _loading = false);
              if (!mounted) return;
              
              await showDialog<void>(
                context: navigator.context,
                builder: (ctx) {
                  String query = '';
                  return AlertDialog(
                    title: const Text('No product found'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Barcode: $raw'),
                        const SizedBox(height: 8),
                        const Text('We could not find this in Open Food Facts or Open Beauty Facts.'),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Search by name',
                            hintText: 'e.g., Herbal body moisturizer',
                          ),
                          onChanged: (v) => query = v.trim(),
                          onSubmitted: (_) => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final dialogNavigator = Navigator.of(ctx);
                          final parentNavigator = navigator;
                          final messenger = scaffoldMessenger;
                          
                          dialogNavigator.pop();
                          if (query.isEmpty) return;
                          if (!mounted) return;
                          setState(() => _loading = true);
                          final byName = await ProductLookupService.searchAnyByName(query);
                          if (!mounted) return;
                          setState(() => _loading = false);
                          if (byName != null) {
                            parentNavigator.pop(byName);
                          } else {
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('No matches found by name. Try a different term.')),
                              );
                            }
                            // Allow retry scanning
                            if (!mounted) return;
                            setState(() => _handled = false);
                          }
                        },
                        child: const Text('Search'),
                      ),
                    ],
                  );
                },
              );

              // After dialog, if we did not navigate away, allow another scan
              if (mounted) {
                setState(() {
                  _handled = false;
                  _loading = false;
                });
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Not found. You can search by name or try another scan.')),
                );
              }
            },
          ),
          if (_loading)
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0x88000000), shape: BoxShape.circle),
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.all(16),
              child: const Text(
                'Align the barcode within the frame',
                style: TextStyle(color: Colors.white),
              ),
            ),
          )
        ],
      ),
    );
  }
}
