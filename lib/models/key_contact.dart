/// Data model for key professional/household contacts.

enum ContactCategory {
  lawyer,
  auditor,
  propertyDocumentWriter,
  charteredAccountant,
  financialAdvisor,
  insuranceAgent,
  taxConsultant,
  bankManager,
  realEstateAgent,
  architect,
  contractor,
  doctor,
  dentist,
  veterinarian,
  electrician,
  plumber,
  mechanic,
  tutor,
  custom,
}

class KeyContact {
  final String id;
  final ContactCategory category;
  final String name;
  final String? firmName;
  final String phone;
  final String? alternatePhone;
  final String? email;
  final String? address;
  final String? specialization;
  final String? licenseNumber;
  final String? notes;
  final String? customCategoryName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const KeyContact({
    required this.id,
    required this.category,
    required this.name,
    this.firmName,
    required this.phone,
    this.alternatePhone,
    this.email,
    this.address,
    this.specialization,
    this.licenseNumber,
    this.notes,
    this.customCategoryName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory KeyContact.fromJson(Map<String, dynamic> json) {
    return KeyContact(
      id: json['id']?.toString() ?? '',
      category: _parseCategory(json['category'] as String?),
      name: json['name'] as String? ?? '',
      firmName: json['firm_name'] as String?,
      phone: json['phone'] as String? ?? '',
      alternatePhone: json['alternate_phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      specialization: json['specialization'] as String?,
      licenseNumber: json['license_number'] as String?,
      notes: json['notes'] as String?,
      customCategoryName: json['custom_category_name'] as String?,
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
        'firm_name': firmName,
        'phone': phone,
        'alternate_phone': alternatePhone,
        'email': email,
        'address': address,
        'specialization': specialization,
        'license_number': licenseNumber,
        'notes': notes,
        'custom_category_name': customCategoryName,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  KeyContact copyWith({
    String? id,
    ContactCategory? category,
    String? name,
    String? firmName,
    String? phone,
    String? alternatePhone,
    String? email,
    String? address,
    String? specialization,
    String? licenseNumber,
    String? notes,
    String? customCategoryName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KeyContact(
      id: id ?? this.id,
      category: category ?? this.category,
      name: name ?? this.name,
      firmName: firmName ?? this.firmName,
      phone: phone ?? this.phone,
      alternatePhone: alternatePhone ?? this.alternatePhone,
      email: email ?? this.email,
      address: address ?? this.address,
      specialization: specialization ?? this.specialization,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      notes: notes ?? this.notes,
      customCategoryName: customCategoryName ?? this.customCategoryName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get displayCategory {
    if (category == ContactCategory.custom && customCategoryName != null) {
      return customCategoryName!;
    }
    return categoryLabel(category);
  }

  static String categoryLabel(ContactCategory cat) {
    switch (cat) {
      case ContactCategory.lawyer:
        return 'Lawyer';
      case ContactCategory.auditor:
        return 'Auditor';
      case ContactCategory.propertyDocumentWriter:
        return 'Property Document Writer';
      case ContactCategory.charteredAccountant:
        return 'Chartered Accountant';
      case ContactCategory.financialAdvisor:
        return 'Financial Advisor';
      case ContactCategory.insuranceAgent:
        return 'Insurance Agent';
      case ContactCategory.taxConsultant:
        return 'Tax Consultant';
      case ContactCategory.bankManager:
        return 'Bank Manager';
      case ContactCategory.realEstateAgent:
        return 'Real Estate Agent';
      case ContactCategory.architect:
        return 'Architect';
      case ContactCategory.contractor:
        return 'Contractor';
      case ContactCategory.doctor:
        return 'Doctor';
      case ContactCategory.dentist:
        return 'Dentist';
      case ContactCategory.veterinarian:
        return 'Veterinarian';
      case ContactCategory.electrician:
        return 'Electrician';
      case ContactCategory.plumber:
        return 'Plumber';
      case ContactCategory.mechanic:
        return 'Mechanic';
      case ContactCategory.tutor:
        return 'Tutor / Teacher';
      case ContactCategory.custom:
        return 'Custom';
    }
  }

  static ContactCategory _parseCategory(String? value) {
    switch ((value ?? '').toLowerCase().replaceAll('_', '')) {
      case 'lawyer':
        return ContactCategory.lawyer;
      case 'auditor':
        return ContactCategory.auditor;
      case 'propertydocumentwriter':
        return ContactCategory.propertyDocumentWriter;
      case 'charteredaccountant':
        return ContactCategory.charteredAccountant;
      case 'financialadvisor':
        return ContactCategory.financialAdvisor;
      case 'insuranceagent':
        return ContactCategory.insuranceAgent;
      case 'taxconsultant':
        return ContactCategory.taxConsultant;
      case 'bankmanager':
        return ContactCategory.bankManager;
      case 'realestateagent':
        return ContactCategory.realEstateAgent;
      case 'architect':
        return ContactCategory.architect;
      case 'contractor':
        return ContactCategory.contractor;
      case 'doctor':
        return ContactCategory.doctor;
      case 'dentist':
        return ContactCategory.dentist;
      case 'veterinarian':
        return ContactCategory.veterinarian;
      case 'electrician':
        return ContactCategory.electrician;
      case 'plumber':
        return ContactCategory.plumber;
      case 'mechanic':
        return ContactCategory.mechanic;
      case 'tutor':
        return ContactCategory.tutor;
      default:
        return ContactCategory.custom;
    }
  }

  static String _categoryKey(ContactCategory cat) {
    switch (cat) {
      case ContactCategory.lawyer:
        return 'lawyer';
      case ContactCategory.auditor:
        return 'auditor';
      case ContactCategory.propertyDocumentWriter:
        return 'property_document_writer';
      case ContactCategory.charteredAccountant:
        return 'chartered_accountant';
      case ContactCategory.financialAdvisor:
        return 'financial_advisor';
      case ContactCategory.insuranceAgent:
        return 'insurance_agent';
      case ContactCategory.taxConsultant:
        return 'tax_consultant';
      case ContactCategory.bankManager:
        return 'bank_manager';
      case ContactCategory.realEstateAgent:
        return 'real_estate_agent';
      case ContactCategory.architect:
        return 'architect';
      case ContactCategory.contractor:
        return 'contractor';
      case ContactCategory.doctor:
        return 'doctor';
      case ContactCategory.dentist:
        return 'dentist';
      case ContactCategory.veterinarian:
        return 'veterinarian';
      case ContactCategory.electrician:
        return 'electrician';
      case ContactCategory.plumber:
        return 'plumber';
      case ContactCategory.mechanic:
        return 'mechanic';
      case ContactCategory.tutor:
        return 'tutor';
      case ContactCategory.custom:
        return 'custom';
    }
  }
}
