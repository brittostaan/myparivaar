import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/key_contact.dart';
import '../theme/app_colors.dart';

class KeyContactsScreen extends StatefulWidget {
  const KeyContactsScreen({super.key});

  @override
  State<KeyContactsScreen> createState() => _KeyContactsScreenState();
}

class _KeyContactsScreenState extends State<KeyContactsScreen> {
  final List<KeyContact> _contacts = [];
  String? _selectedCategoryFilter;

  static const List<_ContactCategoryInfo> _categoryInfoList = [
    _ContactCategoryInfo(
      category: ContactCategory.lawyer,
      icon: Icons.gavel,
      color: Color(0xFF37474F),
      bgColor: Color(0xFFCFD8DC),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.auditor,
      icon: Icons.fact_check_outlined,
      color: Color(0xFF4527A0),
      bgColor: Color(0xFFD1C4E9),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.propertyDocumentWriter,
      icon: Icons.description_outlined,
      color: Color(0xFF5D4037),
      bgColor: Color(0xFFBCAAA4),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.charteredAccountant,
      icon: Icons.calculate_outlined,
      color: Color(0xFF1565C0),
      bgColor: Color(0xFFBBDEFB),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.financialAdvisor,
      icon: Icons.account_balance_outlined,
      color: Color(0xFF2E7D32),
      bgColor: Color(0xFFC8E6C9),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.insuranceAgent,
      icon: Icons.health_and_safety_outlined,
      color: Color(0xFF00695C),
      bgColor: Color(0xFFB2DFDB),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.taxConsultant,
      icon: Icons.receipt_long_outlined,
      color: Color(0xFFAD1457),
      bgColor: Color(0xFFF8BBD0),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.bankManager,
      icon: Icons.account_balance,
      color: Color(0xFF0277BD),
      bgColor: Color(0xFFB3E5FC),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.realEstateAgent,
      icon: Icons.location_city_outlined,
      color: Color(0xFFE65100),
      bgColor: Color(0xFFFFE0B2),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.architect,
      icon: Icons.architecture,
      color: Color(0xFF6A1B9A),
      bgColor: Color(0xFFE1BEE7),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.contractor,
      icon: Icons.construction_outlined,
      color: Color(0xFF795548),
      bgColor: Color(0xFFD7CCC8),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.doctor,
      icon: Icons.medical_services_outlined,
      color: Color(0xFFC62828),
      bgColor: Color(0xFFFFCDD2),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.dentist,
      icon: Icons.mood_outlined,
      color: Color(0xFF00838F),
      bgColor: Color(0xFFB2EBF2),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.veterinarian,
      icon: Icons.pets_outlined,
      color: Color(0xFF8D6E63),
      bgColor: Color(0xFFEFEBE9),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.electrician,
      icon: Icons.electrical_services_outlined,
      color: Color(0xFFF9A825),
      bgColor: Color(0xFFFFF9C4),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.plumber,
      icon: Icons.plumbing_outlined,
      color: Color(0xFF0277BD),
      bgColor: Color(0xFFE1F5FE),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.mechanic,
      icon: Icons.build_outlined,
      color: Color(0xFF455A64),
      bgColor: Color(0xFFECEFF1),
    ),
    _ContactCategoryInfo(
      category: ContactCategory.tutor,
      icon: Icons.school_outlined,
      color: Color(0xFF1565C0),
      bgColor: Color(0xFFE3F2FD),
    ),
  ];

  List<KeyContact> get _filteredContacts {
    if (_selectedCategoryFilter == null) return _contacts;
    return _contacts
        .where((c) => c.displayCategory == _selectedCategoryFilter)
        .toList();
  }

  Map<String, int> get _categoryCounts {
    final counts = <String, int>{};
    for (final contact in _contacts) {
      final label = contact.displayCategory;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return counts;
  }

  // ── Add / Edit Dialog ─────────────────────────────────────────────────────

  Future<void> _showAddContactDialog({KeyContact? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final firmCtrl = TextEditingController(text: existing?.firmName ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final altPhoneCtrl =
        TextEditingController(text: existing?.alternatePhone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final specCtrl =
        TextEditingController(text: existing?.specialization ?? '');
    final licenseCtrl =
        TextEditingController(text: existing?.licenseNumber ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final customCatCtrl =
        TextEditingController(text: existing?.customCategoryName ?? '');

    ContactCategory selectedCategory =
        existing?.category ?? ContactCategory.lawyer;
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<KeyContact?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title:
                Text(existing != null ? 'Edit Contact' : 'Add Key Contact'),
            content: SizedBox(
              width: 520,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<ContactCategory>(
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'Contact Type',
                          border: OutlineInputBorder(),
                        ),
                        items: ContactCategory.values.map((cat) {
                          return DropdownMenuItem(
                            value: cat,
                            child: Text(KeyContact.categoryLabel(cat)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedCategory = val);
                          }
                        },
                      ),
                      if (selectedCategory == ContactCategory.custom) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: customCatCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Custom Contact Type',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (selectedCategory == ContactCategory.custom &&
                                (v == null || v.trim().isEmpty)) {
                              return 'Enter the contact type name';
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          hintText: _nameHint(selectedCategory),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: firmCtrl,
                        decoration: InputDecoration(
                          labelText: _firmLabel(selectedCategory),
                          hintText: _firmHint(selectedCategory),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '+91 98765 43210',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+\- ]')),
                        ],
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Phone number is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: altPhoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Alternate Phone (optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+\- ]')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Email (optional)',
                          hintText: 'name@example.com',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressCtrl,
                        decoration: InputDecoration(
                          labelText: _addressLabel(selectedCategory),
                          hintText: _addressHint(selectedCategory),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.location_on_outlined),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: specCtrl,
                        decoration: InputDecoration(
                          labelText: _specLabel(selectedCategory),
                          hintText: _specHint(selectedCategory),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (_showsLicense(selectedCategory)) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: licenseCtrl,
                          decoration: InputDecoration(
                            labelText: _licenseLabel(selectedCategory),
                            hintText: _licenseHint(selectedCategory),
                            border: const OutlineInputBorder(),
                            prefixIcon:
                                const Icon(Icons.badge_outlined),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText:
                              'Any additional info, reference, or relationship',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final now = DateTime.now();
                  final contact = KeyContact(
                    id: existing?.id ??
                        now.millisecondsSinceEpoch.toString(),
                    category: selectedCategory,
                    name: nameCtrl.text.trim(),
                    firmName: firmCtrl.text.trim().isNotEmpty
                        ? firmCtrl.text.trim()
                        : null,
                    phone: phoneCtrl.text.trim(),
                    alternatePhone: altPhoneCtrl.text.trim().isNotEmpty
                        ? altPhoneCtrl.text.trim()
                        : null,
                    email: emailCtrl.text.trim().isNotEmpty
                        ? emailCtrl.text.trim()
                        : null,
                    address: addressCtrl.text.trim().isNotEmpty
                        ? addressCtrl.text.trim()
                        : null,
                    specialization: specCtrl.text.trim().isNotEmpty
                        ? specCtrl.text.trim()
                        : null,
                    licenseNumber: licenseCtrl.text.trim().isNotEmpty
                        ? licenseCtrl.text.trim()
                        : null,
                    notes: notesCtrl.text.trim().isNotEmpty
                        ? notesCtrl.text.trim()
                        : null,
                    customCategoryName:
                        selectedCategory == ContactCategory.custom
                            ? customCatCtrl.text.trim()
                            : null,
                    createdAt: existing?.createdAt ?? now,
                    updatedAt: now,
                  );
                  Navigator.pop(ctx, contact);
                },
                child: Text(existing != null ? 'Save' : 'Add'),
              ),
            ],
          );
        });
      },
    );

    if (result != null) {
      setState(() {
        if (existing != null) {
          final idx = _contacts.indexWhere((c) => c.id == existing.id);
          if (idx >= 0) _contacts[idx] = result;
        } else {
          _contacts.add(result);
        }
      });
    }
  }

  void _deleteContact(KeyContact contact) {
    setState(() {
      _contacts.removeWhere((c) => c.id == contact.id);
    });
  }

  // ── Context-aware labels ──────────────────────────────────────────────────

  String _nameHint(ContactCategory cat) {
    switch (cat) {
      case ContactCategory.lawyer:
        return 'e.g. Adv. Ramesh Kumar';
      case ContactCategory.auditor:
        return 'e.g. CA Suresh Menon';
      case ContactCategory.propertyDocumentWriter:
        return 'e.g. N. Krishnamurthy';
      case ContactCategory.doctor:
        return 'e.g. Dr. Priya Sharma';
      default:
        return 'e.g. Full Name';
    }
  }

  String _firmLabel(ContactCategory cat) {
    switch (cat) {
      case ContactCategory.lawyer:
        return 'Law Firm / Chamber (optional)';
      case ContactCategory.auditor:
      case ContactCategory.charteredAccountant:
        return 'Firm Name (optional)';
      case ContactCategory.doctor:
      case ContactCategory.dentist:
        return 'Hospital / Clinic (optional)';
      case ContactCategory.bankManager:
        return 'Bank & Branch (optional)';
      case ContactCategory.insuranceAgent:
        return 'Insurance Company (optional)';
      case ContactCategory.realEstateAgent:
        return 'Agency Name (optional)';
      case ContactCategory.tutor:
        return 'Institute / School (optional)';
      default:
        return 'Firm / Organization (optional)';
    }
  }

  String _firmHint(ContactCategory cat) {
    switch (cat) {
      case ContactCategory.lawyer:
        return 'e.g. Kumar & Associates';
      case ContactCategory.auditor:
      case ContactCategory.charteredAccountant:
        return 'e.g. Menon Audit Partners';
      case ContactCategory.doctor:
        return 'e.g. Apollo Hospital, Chennai';
      case ContactCategory.bankManager:
        return 'e.g. SBI, Anna Nagar Branch';
      case ContactCategory.insuranceAgent:
        return 'e.g. LIC of India';
      default:
        return '';
    }
  }

  String _addressLabel(ContactCategory cat) {
    switch (cat) {
      case ContactCategory.lawyer:
        return 'Chamber / Office Address (optional)';
      case ContactCategory.doctor:
      case ContactCategory.dentist:
        return 'Clinic Address (optional)';
      default:
        return 'Office Address (optional)';
    }
  }

  String _addressHint(ContactCategory cat) {
    switch (cat) {
      case ContactCategory.lawyer:
        return 'e.g. High Court Campus, Chennai';
      case ContactCategory.doctor:
        return 'e.g. 42, Greams Road, Chennai';
      default:
        return 'Full address';
    }
  }

  String _specLabel(ContactCategory cat) {
    switch (cat) {
      case ContactCategory.lawyer:
        return 'Specialization (optional)';
      case ContactCategory.doctor:
        return 'Specialty (optional)';
      case ContactCategory.charteredAccountant:
      case ContactCategory.auditor:
        return 'Area of Practice (optional)';
      case ContactCategory.tutor:
        return 'Subject (optional)';
      case ContactCategory.contractor:
        return 'Type of Work (optional)';
      default:
        return 'Specialization (optional)';
    }
  }

  String _specHint(ContactCategory cat) {
    switch (cat) {
      case ContactCategory.lawyer:
        return 'e.g. Property Law, Family Law, Criminal';
      case ContactCategory.doctor:
        return 'e.g. Cardiologist, General Physician';
      case ContactCategory.charteredAccountant:
        return 'e.g. Tax Filing, GST, Audit';
      case ContactCategory.tutor:
        return 'e.g. Mathematics, Piano, Swimming';
      case ContactCategory.contractor:
        return 'e.g. Civil, Interiors, Plumbing';
      default:
        return '';
    }
  }

  bool _showsLicense(ContactCategory cat) {
    return cat == ContactCategory.lawyer ||
        cat == ContactCategory.doctor ||
        cat == ContactCategory.dentist ||
        cat == ContactCategory.charteredAccountant ||
        cat == ContactCategory.auditor ||
        cat == ContactCategory.architect ||
        cat == ContactCategory.veterinarian;
  }

  String _licenseLabel(ContactCategory cat) {
    switch (cat) {
      case ContactCategory.lawyer:
        return 'Bar Council Number (optional)';
      case ContactCategory.doctor:
      case ContactCategory.dentist:
        return 'Registration Number (optional)';
      case ContactCategory.charteredAccountant:
      case ContactCategory.auditor:
        return 'Membership Number (optional)';
      case ContactCategory.architect:
        return 'COA Registration (optional)';
      default:
        return 'License / Registration (optional)';
    }
  }

  String _licenseHint(ContactCategory cat) {
    switch (cat) {
      case ContactCategory.lawyer:
        return 'e.g. TN/1234/2020';
      case ContactCategory.doctor:
        return 'e.g. MCI-12345';
      case ContactCategory.charteredAccountant:
        return 'e.g. ICAI 012345';
      default:
        return '';
    }
  }

  _ContactCategoryInfo? _getCategoryInfo(ContactCategory cat) {
    for (final info in _categoryInfoList) {
      if (info.category == cat) return info;
    }
    return null;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceHoverLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Action Pane ────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Key Contacts',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                      const Spacer(),
                      if (_contacts.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_contacts.length} contact${_contacts.length == 1 ? '' : 's'} · ${_categoryCounts.length} categor${_categoryCounts.length == 1 ? 'y' : 'ies'}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () => _showAddContactDialog(),
                        icon: const Icon(Icons.person_add_outlined, size: 18),
                        label: const Text('Add Contact'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Row 2: Category tabs
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _ActionPaneTab(
                          label: 'All Contacts',
                          icon: Icons.people_outline,
                          selected: _selectedCategoryFilter == null,
                          onTap: () => setState(() => _selectedCategoryFilter = null),
                        ),
                        const SizedBox(width: 6),
                        ..._categoryInfoList.map((info) {
                          final label = KeyContact.categoryLabel(info.category);
                          final count = _contacts.where((c) => c.category == info.category).length;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _ActionPaneTab(
                              label: count > 0 ? '$label ($count)' : label,
                              icon: info.icon,
                              selected: _selectedCategoryFilter == label,
                              onTap: () => setState(() => _selectedCategoryFilter = label),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLight),

            // ── Content ────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: _contacts.isEmpty
                    ? _buildEmptyState()
                    : _buildContactList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contacts_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No key contacts yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your lawyer, auditor, doctor, and other\nimportant contacts for quick access.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddContactDialog(),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Add Your First Contact'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactList() {
    final filtered = _filteredContacts;
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No contacts in this category',
          style: TextStyle(color: Colors.grey[400]),
        ),
      );
    }
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final contact = filtered[index];
        final info = _getCategoryInfo(contact.category);
        return _ContactCard(
          contact: contact,
          categoryInfo: info,
          onEdit: () => _showAddContactDialog(existing: contact),
          onDelete: () => _deleteContact(contact),
        );
      },
    );
  }
}

// ── Supporting Widgets ────────────────────────────────────────────────────────

class _ContactCategoryInfo {
  final ContactCategory category;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _ContactCategoryInfo({
    required this.category,
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}

class _ActionPaneTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ActionPaneTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withAlpha(15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selected
              ? Border(bottom: BorderSide(color: AppColors.primary, width: 2))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? AppColors.primary : Colors.grey[500]),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.icon,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16,
                  color: selected ? Colors.white : (color ?? Colors.grey[600])),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final KeyContact contact;
  final _ContactCategoryInfo? categoryInfo;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContactCard({
    required this.contact,
    required this.categoryInfo,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = categoryInfo?.color ?? AppColors.primary;
    final bgColor =
        categoryInfo?.bgColor ?? AppColors.primaryLight.withAlpha(40);
    final icon = categoryInfo?.icon ?? Icons.person;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contact.displayCategory,
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_vert,
                    size: 20, color: Colors.grey[400]),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Info rows
          _infoRow(Icons.phone_outlined, contact.phone, color),
          if (contact.alternatePhone != null)
            _infoRow(Icons.phone_outlined, contact.alternatePhone!, color),
          if (contact.email != null)
            _infoRow(Icons.email_outlined, contact.email!, color),
          if (contact.firmName != null)
            _infoRow(Icons.business_outlined, contact.firmName!, color),
          if (contact.address != null)
            _infoRow(
                Icons.location_on_outlined, contact.address!, color),
          if (contact.specialization != null)
            _infoRow(Icons.star_outline, contact.specialization!, color),
          if (contact.licenseNumber != null)
            _infoRow(Icons.badge_outlined, contact.licenseNumber!, color),
          if (contact.notes != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes_outlined, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    contact.notes!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color.withAlpha(150)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }
}
