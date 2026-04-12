/// Centralized category-to-emoji mapping for the MyParivaar app.
///
/// Maps budget/expense categories and descriptions to relevant emojis
/// for visual display across the app. Used in budget rows, expense lists,
/// dashboard, and reports.
class CategoryEmoji {
  /// Primary category → emoji mapping
  static const Map<String, String> _categoryMap = {
    // Food & Groceries
    'food': '🍔',
    'groceries': '🛒',
    'dining': '🍽️',
    'restaurant': '🍽️',
    'coffee': '☕',
    'snacks': '🍿',

    // Transport
    'transport': '🚗',
    'transportation': '🚗',
    'fuel': '⛽',
    'petrol': '⛽',
    'auto': '🛺',
    'cab': '🚕',
    'taxi': '🚕',
    'parking': '🅿️',

    // Home & Utilities  
    'utilities': '⚡',
    'electricity': '⚡',
    'water': '💧',
    'gas': '🔥',
    'rent': '🏠',
    'housing': '🏠',
    'household': '🏡',
    'maintenance': '🔧',
    'repairs': '🛠️',

    // Shopping & Lifestyle
    'shopping': '🛍️',
    'clothing': '👔',
    'clothes': '👔',
    'fashion': '👗',
    'beauty': '💄',
    'cosmetics': '💄',

    // Healthcare
    'healthcare': '🏥',
    'health': '🏥',
    'medical': '💊',
    'medicine': '💊',
    'doctor': '👨‍⚕️',
    'hospital': '🏥',
    'pharmacy': '💊',
    'dental': '🦷',
    'fitness': '💪',
    'gym': '💪',

    // Entertainment
    'entertainment': '🎬',
    'movies': '🎬',
    'music': '🎵',
    'games': '🎮',
    'sports': '⚽',
    'streaming': '📺',
    'subscriptions': '🔄',

    // Education
    'education': '📚',
    'school': '🎓',
    'college': '🎓',
    'tuition': '📖',
    'books': '📖',
    'courses': '📚',
    'classes': '🎓',
    'training': '📝',

    // Finance & Income
    'income': '💰',
    'salary': '💵',
    'investment': '📈',
    'investments': '📈',
    'savings': '🏦',
    'insurance': '🛡️',
    'tax': '🧾',
    'taxes': '🧾',
    'fees': '📋',
    'emi': '🏦',
    'loan': '🏦',

    // Gifts & Social
    'gifts': '🎁',
    'donation': '❤️',
    'charity': '❤️',
    'wedding': '💍',
    'party': '🎉',
    'celebration': '🎉',

    // Travel
    'travel': '✈️',
    'vacation': '🏖️',
    'holiday': '🏖️',
    'hotel': '🏨',
    'flight': '✈️',

    // Pets
    'pets': '🐾',
    'pet': '🐾',
    'vet': '🐾',

    // Kids & Family
    'kids': '👶',
    'childcare': '👶',
    'nanny': '👶',
    'babysitter': '👶',

    // Technology
    'tech': '💻',
    'technology': '💻',
    'mobile': '📱',
    'internet': '🌐',
    'wifi': '📶',
    'software': '💻',

    // Misc
    'other': '📦',
    'others': '📦',
    'miscellaneous': '📦',
    'general': '📦',
    'personal': '👤',
    'given': '🤝',
  };

  /// Keyword patterns for smart fallback matching on descriptions
  static const Map<String, String> _keywordMap = {
    'uber': '🚕',
    'ola': '🚕',
    'swiggy': '🍔',
    'zomato': '🍔',
    'amazon': '🛍️',
    'flipkart': '🛍️',
    'netflix': '📺',
    'spotify': '🎵',
    'youtube': '📺',
    'hotstar': '📺',
    'airtel': '📱',
    'jio': '📱',
    'bsnl': '📱',
    'milk': '🥛',
    'vegetable': '🥬',
    'fruit': '🍎',
    'rice': '🍚',
    'bread': '🍞',
    'water': '💧',
    'electric': '⚡',
    'petrol': '⛽',
    'diesel': '⛽',
    'school': '🎓',
    'class': '🎓',
    'cello': '🎻',
    'piano': '🎹',
    'guitar': '🎸',
    'dance': '💃',
    'karate': '🥋',
    'swim': '🏊',
    'doctor': '👨‍⚕️',
    'hospital': '🏥',
    'medicine': '💊',
    'rent': '🏠',
    'emi': '🏦',
    'loan': '🏦',
    'insurance': '🛡️',
    'salary': '💵',
    'recharge': '📱',
    'bill': '🧾',
    'kevin': '👤',
  };

  static const String _defaultEmoji = '📦';

  /// Get emoji for a category name.
  /// Falls back to description/item-name keyword matching if category is generic.
  static String getCategoryEmoji(String category, {String? description, String? itemName}) {
    final cat = category.toLowerCase().trim();

    // Check for compound categories like "entertainment - 15th-21st"
    // or "utilities - household" or "other - kevin fees"
    final parts = cat.split(RegExp(r'\s*[-–—]\s*'));
    final mainCat = parts.first.trim();
    final subCat = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';

    // Direct category match
    if (_categoryMap.containsKey(mainCat)) {
      // If main category is generic (other/others), try sub-category
      if ((mainCat == 'other' || mainCat == 'others') && subCat.isNotEmpty) {
        final subEmoji = _matchSubCategory(subCat);
        if (subEmoji != null) return subEmoji;
      }
      return _categoryMap[mainCat]!;
    }

    // Try sub-category match
    if (subCat.isNotEmpty) {
      if (_categoryMap.containsKey(subCat)) return _categoryMap[subCat]!;
      final subEmoji = _matchSubCategory(subCat);
      if (subEmoji != null) return subEmoji;
    }

    // Try full category string keyword match
    final keywordMatch = _matchKeywords(cat);
    if (keywordMatch != null) return keywordMatch;

    // Try description
    if (description != null && description.isNotEmpty) {
      final descMatch = _matchKeywords(description.toLowerCase());
      if (descMatch != null) return descMatch;
    }

    // Try item name
    if (itemName != null && itemName.isNotEmpty) {
      final itemMatch = _matchKeywords(itemName.toLowerCase());
      if (itemMatch != null) return itemMatch;
    }

    return _defaultEmoji;
  }

  static String? _matchSubCategory(String subCat) {
    if (_categoryMap.containsKey(subCat)) return _categoryMap[subCat];
    return _matchKeywords(subCat);
  }

  static String? _matchKeywords(String text) {
    for (final entry in _keywordMap.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return null;
  }
}
