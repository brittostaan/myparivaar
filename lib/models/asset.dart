/// Asset categories and data model for the MyParivaar asset tracker.

enum AssetCategory {
  property,
  bankLocker,
  bitcoin,
  jewellery,
  art,
  antique,
  vehicle,
  gold,
  stocks,
  mutualFunds,
  fixedDeposit,
  insurancePolicy,
  intellectualProperty,
  collectible,
  custom,
}

enum PropertyType { land, apartment, villa, house }

class Asset {
  final String id;
  final AssetCategory category;
  final String name;
  final String? description;
  final double estimatedValue;
  final String? location;
  final DateTime? acquiredDate;
  final String? notes;
  final PropertyType? propertyType;
  final String? customCategoryName;
  final Map<String, String> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Asset({
    required this.id,
    required this.category,
    required this.name,
    this.description,
    required this.estimatedValue,
    this.location,
    this.acquiredDate,
    this.notes,
    this.propertyType,
    this.customCategoryName,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory Asset.fromJson(Map<String, dynamic> json) {
    return Asset(
      id: json['id']?.toString() ?? '',
      category: _parseCategory(json['category'] as String?),
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      estimatedValue: (json['estimated_value'] as num?)?.toDouble() ?? 0.0,
      location: json['location'] as String?,
      acquiredDate: json['acquired_date'] != null
          ? DateTime.tryParse(json['acquired_date'] as String)
          : null,
      notes: json['notes'] as String?,
      propertyType: json['property_type'] != null
          ? _parsePropertyType(json['property_type'] as String)
          : null,
      customCategoryName: json['custom_category_name'] as String?,
      metadata: json['metadata'] != null
          ? Map<String, String>.from(json['metadata'] as Map)
          : const {},
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': _categoryKey(category),
        'name': name,
        'description': description,
        'estimated_value': estimatedValue,
        'location': location,
        'acquired_date': acquiredDate?.toIso8601String(),
        'notes': notes,
        'property_type':
            propertyType != null ? _propertyTypeKey(propertyType!) : null,
        'custom_category_name': customCategoryName,
        'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Asset copyWith({
    String? id,
    AssetCategory? category,
    String? name,
    String? description,
    double? estimatedValue,
    String? location,
    DateTime? acquiredDate,
    String? notes,
    PropertyType? propertyType,
    String? customCategoryName,
    Map<String, String>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Asset(
      id: id ?? this.id,
      category: category ?? this.category,
      name: name ?? this.name,
      description: description ?? this.description,
      estimatedValue: estimatedValue ?? this.estimatedValue,
      location: location ?? this.location,
      acquiredDate: acquiredDate ?? this.acquiredDate,
      notes: notes ?? this.notes,
      propertyType: propertyType ?? this.propertyType,
      customCategoryName: customCategoryName ?? this.customCategoryName,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get displayCategory {
    if (category == AssetCategory.custom && customCategoryName != null) {
      return customCategoryName!;
    }
    return categoryLabel(category);
  }

  static String categoryLabel(AssetCategory cat) {
    switch (cat) {
      case AssetCategory.property:
        return 'Property';
      case AssetCategory.bankLocker:
        return 'Bank Locker';
      case AssetCategory.bitcoin:
        return 'Bitcoin / Crypto';
      case AssetCategory.jewellery:
        return 'Jewellery';
      case AssetCategory.art:
        return 'Art';
      case AssetCategory.antique:
        return 'Antique';
      case AssetCategory.vehicle:
        return 'Vehicle';
      case AssetCategory.gold:
        return 'Gold & Precious Metals';
      case AssetCategory.stocks:
        return 'Stocks & Shares';
      case AssetCategory.mutualFunds:
        return 'Mutual Funds';
      case AssetCategory.fixedDeposit:
        return 'Fixed Deposit';
      case AssetCategory.insurancePolicy:
        return 'Insurance Policy';
      case AssetCategory.intellectualProperty:
        return 'Intellectual Property';
      case AssetCategory.collectible:
        return 'Collectible';
      case AssetCategory.custom:
        return 'Custom';
    }
  }

  static String propertyTypeLabel(PropertyType type) {
    switch (type) {
      case PropertyType.land:
        return 'Land';
      case PropertyType.apartment:
        return 'Apartment';
      case PropertyType.villa:
        return 'Villa';
      case PropertyType.house:
        return 'House';
    }
  }

  static AssetCategory _parseCategory(String? value) {
    switch ((value ?? '').toLowerCase().replaceAll('_', '')) {
      case 'property':
        return AssetCategory.property;
      case 'banklocker':
        return AssetCategory.bankLocker;
      case 'bitcoin':
        return AssetCategory.bitcoin;
      case 'jewellery':
        return AssetCategory.jewellery;
      case 'art':
        return AssetCategory.art;
      case 'antique':
        return AssetCategory.antique;
      case 'vehicle':
        return AssetCategory.vehicle;
      case 'gold':
        return AssetCategory.gold;
      case 'stocks':
        return AssetCategory.stocks;
      case 'mutualfunds':
        return AssetCategory.mutualFunds;
      case 'fixeddeposit':
        return AssetCategory.fixedDeposit;
      case 'insurancepolicy':
        return AssetCategory.insurancePolicy;
      case 'intellectualproperty':
        return AssetCategory.intellectualProperty;
      case 'collectible':
        return AssetCategory.collectible;
      default:
        return AssetCategory.custom;
    }
  }

  static PropertyType _parsePropertyType(String value) {
    switch (value.toLowerCase()) {
      case 'apartment':
        return PropertyType.apartment;
      case 'villa':
        return PropertyType.villa;
      case 'house':
        return PropertyType.house;
      default:
        return PropertyType.land;
    }
  }

  static String _categoryKey(AssetCategory cat) {
    switch (cat) {
      case AssetCategory.property:
        return 'property';
      case AssetCategory.bankLocker:
        return 'bank_locker';
      case AssetCategory.bitcoin:
        return 'bitcoin';
      case AssetCategory.jewellery:
        return 'jewellery';
      case AssetCategory.art:
        return 'art';
      case AssetCategory.antique:
        return 'antique';
      case AssetCategory.vehicle:
        return 'vehicle';
      case AssetCategory.gold:
        return 'gold';
      case AssetCategory.stocks:
        return 'stocks';
      case AssetCategory.mutualFunds:
        return 'mutual_funds';
      case AssetCategory.fixedDeposit:
        return 'fixed_deposit';
      case AssetCategory.insurancePolicy:
        return 'insurance_policy';
      case AssetCategory.intellectualProperty:
        return 'intellectual_property';
      case AssetCategory.collectible:
        return 'collectible';
      case AssetCategory.custom:
        return 'custom';
    }
  }

  static String _propertyTypeKey(PropertyType type) {
    switch (type) {
      case PropertyType.land:
        return 'land';
      case PropertyType.apartment:
        return 'apartment';
      case PropertyType.villa:
        return 'villa';
      case PropertyType.house:
        return 'house';
    }
  }
}
