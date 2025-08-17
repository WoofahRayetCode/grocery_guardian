import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_guardian/services/product_lookup.dart';

void main() {
  group('Food heuristics (OFF)', () {
    test('Honey triggers infant caution', () {
      final p = OpenFoodFactsService.debugParseProduct({
        'code': '0001',
        'product_name': 'Baby cereal with honey',
        'ingredients_text': 'Whole grains, honey, vitamins',
        'nutriments': {},
      });
      expect(p.babyCautions.any((c) => c.toLowerCase().contains('honey')), true);
    });

    test('High-mercury fish triggers pregnancy caution', () {
      final p = OpenFoodFactsService.debugParseProduct({
        'code': '0002',
        'product_name': 'Swordfish steak',
        'ingredients_text': 'Swordfish',
        'nutriments': {},
        'categories_tags': ['en:fish', 'en:swordfish'],
      });
      expect(p.maternityCautions.any((c) => c.toLowerCase().contains('mercury')), true);
    });

    test('Unpasteurized triggers pregnancy caution', () {
      final p = OpenFoodFactsService.debugParseProduct({
        'code': '0003',
        'product_name': 'Raw milk cheese',
        'ingredients_text': 'Unpasteurized milk, salt',
        'nutriments': {},
      });
      expect(p.maternityCautions.any((c) => c.toLowerCase().contains('unpasteurized')), true);
    });

    test('Liver triggers vitamin A caution', () {
      final p = OpenFoodFactsService.debugParseProduct({
        'code': '0004',
        'product_name': 'Liver pate',
        'ingredients_text': 'Pork liver, spices',
        'nutriments': {},
      });
      expect(p.maternityCautions.any((c) => c.toLowerCase().contains('liver')), true);
    });

    test('Infant formula recommendations parsed', () {
      final p = OpenFoodFactsService.debugParseProduct({
        'code': '0005',
        'product_name': 'Infant formula milk iron-fortified',
        'ingredients_text': 'Dried milk, lactose, ferrous sulfate (iron)',
        'nutriments': {},
        'categories_tags': ['en:infant-formula'],
      });
      expect(p.babyRecommendations.isNotEmpty, true);
      expect(p.babyRecommendations.join(' ').toLowerCase().contains('iron'), true);
      expect(p.babyRecommendations.join(' ').toLowerCase().contains('milk'), true);
    });
  });

  group('Beauty heuristics (OBF)', () {
    test('Baby product with fragrance warns', () {
      final p = OpenBeautyFactsService.debugParseProduct({
        'code': '1001',
        'product_name': 'Baby lotion',
        'ingredients_text': 'Water, glycerin, parfum',
        'categories_tags': ['en:baby-care'],
      });
      expect(p.babyCautions.any((c) => c.toLowerCase().contains('fragrance')), true);
    });

    test('Talc in baby-targeted product warns', () {
      final p = OpenBeautyFactsService.debugParseProduct({
        'code': '1002',
        'product_name': 'Baby powder',
        'ingredients_text': 'Talc, fragrance',
        'categories_tags': ['en:baby-care'],
      });
      expect(p.babyCautions.any((c) => c.toLowerCase().contains('talc')), true);
    });

    test('Retinol warns for pregnancy', () {
      final p = OpenBeautyFactsService.debugParseProduct({
        'code': '1003',
        'product_name': 'Night serum',
        'ingredients_text': 'Aqua, Retinol, Glycerin',
        'categories_tags': ['en:face-serum'],
      });
      expect(p.maternityCautions.any((c) => c.toLowerCase().contains('retinoids')), true);
    });

    test('Lanolin flagged for breastfeeding sensitivity', () {
      final p = OpenBeautyFactsService.debugParseProduct({
        'code': '1004',
        'product_name': 'Nipple balm',
        'ingredients_text': 'Lanolin, tocopherol',
        'categories_tags': ['en:nipple-care'],
      });
      expect(p.maternityCautions.any((c) => c.toLowerCase().contains('lanolin')), true);
    });

    test('EU fragrance allergens flagged in baby product', () {
      final p = OpenBeautyFactsService.debugParseProduct({
        'code': '1005',
        'product_name': 'Baby cream',
        'ingredients_text': 'Aqua, Linalool, Limonene',
        'categories_tags': ['en:baby-care'],
      });
      expect(p.babyCautions.any((c) => c == 'Fragrance/essential oils may irritate infant skin'), false);
      expect(p.babyCautions.any((c) => c.toLowerCase().contains('eu-listed')), true);
    });
  });
}
