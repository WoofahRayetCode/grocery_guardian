# Food Recall Tracking Feature

## Overview

Grocery Guardian now includes a comprehensive food recall tracking system that helps you avoid purchasing potentially unsafe products. The feature checks scanned items against a persistent recall list and blocks adding recalled items to your shopping list until confirmed safe.

## Key Features

### 1. **Automatic Recall Checking**
- When you scan a barcode or manually add an item, the app automatically checks it against your recall list
- Matching is done by both barcode (exact match) and product name (fuzzy keyword matching)
- If a match is found, a warning dialog appears with full recall details

### 2. **Blocking Unsafe Products**
- Products flagged as recalled **cannot be added** to your shopping list
- The warning dialog shows:
  - Product name and brand
  - Reason for recall (e.g., Listeria contamination)
  - Recall date
  - Clear warning message
- Options:
  - **Close**: Cancel adding the item
  - **Mark as Safe**: Remove from recall list if you've verified it's safe

### 3. **Persistent Recall List**
- Recalled products are stored persistently on device using SharedPreferences
- List survives app restarts
- Easy to manage through dedicated UI

### 4. **Recall Management Screen**
- Access via: **More Info → Recalled Products**
- Features:
  - View all recalled items with expandable details
  - Add manual recalls for products you know are unsafe
  - Mark items as safe to remove from list
  - Refresh from FDA API (fetches latest recall data)
  - Clear all recalls

### 5. **Manual Recall Entry**
- Add products manually if you hear about recalls from news/social media
- Required: Product name
- Optional: Brand, reason, barcode
- Useful for regional recalls or early warnings

### 6. **FDA API Integration** (Placeholder)
- Built-in structure to fetch recall data from FDA Food Enforcement API
- Automatic caching with 6-hour refresh interval
- Merges API data with manually-added recalls
- **Note**: Currently uses placeholder implementation; production requires real API calls

## How It Works

### Scanning Flow with Recall Check
1. User scans barcode or adds item manually
2. **Recall check runs first** (before allergen/price dialogs)
3. If recalled:
   - Show blocking warning dialog
   - User cannot proceed unless they mark as safe
4. If not recalled:
   - Continue with normal allergen/price flow

### Data Storage
- **Key**: `recalled_products_list`
- **Format**: JSON array of RecallItem objects
- **Fields per item**:
  - `id`: Unique identifier
  - `productName`: Display name
  - `brand`: Optional brand
  - `reason`: Reason for recall
  - `datePublished`: Recall date
  - `description`: Full description
  - `affectedBarcodes`: List of barcodes
  - `affectedKeywords`: Extracted keywords for fuzzy matching
  - `addedAt`: Timestamp when added to list

### Matching Algorithm
1. **Exact barcode match**: If scanned barcode is in `affectedBarcodes`
2. **Fuzzy name match**:
   - Extract keywords from both product name and recall name
   - Match if names contain each other
   - Match if 2+ keywords overlap

## Usage Examples

### Example 1: Scanning a Recalled Product
```
User scans barcode → App finds match in recall list
→ Warning dialog appears:
  "⚠️ RECALL WARNING
   Product: XYZ Peanut Butter
   Reason: Salmonella contamination
   This item cannot be added until confirmed safe."
→ User clicks "Close" → Item not added
```

### Example 2: Marking Product Safe
```
User scans previously recalled item
→ Warning appears
→ User clicks "Mark as Safe"
→ Item removed from recall list
→ Can now add to shopping list
```

### Example 3: Adding Manual Recall
```
User hears news about contaminated lettuce
→ Opens "More Info → Recalled Products"
→ Taps "+" icon
→ Enters: "Organic Romaine Lettuce", "Salmonella", Brand: "ABC Farms"
→ Product added to recall list
→ Next time they try to buy it, warning appears
```

## Integration Points

### Modified Files
1. **`lib/services/recall_service.dart`** (NEW)
   - RecallItem model
   - RecallService with all CRUD operations
   - FDA API integration (placeholder)
   - Matching logic

2. **`lib/main.dart`** (MODIFIED)
   - Added recall check in barcode scan handler
   - Added recall check in manual add item flow
   - Added RecallManagementScreen route
   - Added "Recalled Products" menu item

3. **Routes**
   - `/recalls` → RecallManagementScreen

## API Notes (For Production)

The current implementation includes a placeholder for FDA API integration. To enable:

1. **FDA Food Enforcement API**:
   - Endpoint: `https://api.fda.gov/food/enforcement.json`
   - Supports queries, pagination, date filters
   - No API key required (rate-limited)

2. **Example Query**:
   ```
   https://api.fda.gov/food/enforcement.json?limit=100&search=status:"Ongoing"
   ```

3. **Implementation**:
   - Update `RecallService.fetchRecallsFromAPI()`
   - Parse FDA response format
   - Extract: recall_number, product_description, reason_for_recall, report_date
   - Map to RecallItem objects

4. **Refresh Strategy**:
   - Auto-refresh every 6 hours (configurable via `_cacheDuration`)
   - Manual refresh via UI button
   - Cache timestamp stored in SharedPreferences

## Testing Recommendations

1. **Manual Recall Test**:
   - Add a test recall for "Test Peanut Butter"
   - Try to scan/add item with that name
   - Verify warning appears and blocking works

2. **Mark Safe Test**:
   - Add recall, trigger warning
   - Mark as safe
   - Verify item removed from list
   - Can now add item normally

3. **Persistence Test**:
   - Add recalls
   - Close app
   - Reopen
   - Verify recalls still present

4. **Fuzzy Matching Test**:
   - Add recall for "XYZ Brand Peanut Butter"
   - Try adding "XYZ Peanut"
   - Should still match and warn

## Future Enhancements

- [ ] Push notifications for new recalls
- [ ] Barcode-based matching with UPC database
- [ ] Region/country-specific recall sources (USDA, CFIA, FSA)
- [ ] Automatic expiration of old recalls (e.g., 90 days)
- [ ] Share recall warnings with household profiles
- [ ] Export/import recall lists
- [ ] Integration with grocery delivery APIs

## Dependencies

- `shared_preferences`: Persistent storage
- `http`: API calls (for FDA integration)
- Existing Flutter/Material UI components

## Security & Privacy

- All recall data stored locally on device
- No personal data transmitted
- FDA API calls (when enabled) are anonymous
- User can clear all data at any time
