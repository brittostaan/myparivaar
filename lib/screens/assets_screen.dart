import 'package:flutter/material.dart';
import '../models/asset.dart';
import '../theme/app_colors.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  final List<Asset> _assets = [];
  String? _selectedCategoryFilter;

  /// Default asset categories with icons & colors for the grid.
  static final List<_AssetCategoryInfo> _categoryInfoList = [
    _AssetCategoryInfo(
      category: AssetCategory.property,
      icon: Icons.location_city_outlined,
      color: const Color(0xFF1565C0),
      bgColor: const Color(0xFFBBDEFB),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.bankLocker,
      icon: Icons.lock_outlined,
      color: const Color(0xFF4E342E),
      bgColor: const Color(0xFFD7CCC8),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.bitcoin,
      icon: Icons.currency_bitcoin,
      color: const Color(0xFFE65100),
      bgColor: const Color(0xFFFFE0B2),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.jewellery,
      icon: Icons.diamond_outlined,
      color: const Color(0xFF6A1B9A),
      bgColor: const Color(0xFFE1BEE7),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.art,
      icon: Icons.palette_outlined,
      color: const Color(0xFFC62828),
      bgColor: const Color(0xFFFFCDD2),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.antique,
      icon: Icons.museum_outlined,
      color: const Color(0xFF5D4037),
      bgColor: const Color(0xFFBCAAA4),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.vehicle,
      icon: Icons.directions_car_outlined,
      color: const Color(0xFF00695C),
      bgColor: const Color(0xFFB2DFDB),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.gold,
      icon: Icons.stars_outlined,
      color: const Color(0xFFF9A825),
      bgColor: const Color(0xFFFFF9C4),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.stocks,
      icon: Icons.show_chart,
      color: const Color(0xFF0277BD),
      bgColor: const Color(0xFFB3E5FC),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.mutualFunds,
      icon: Icons.pie_chart_outline,
      color: const Color(0xFF2E7D32),
      bgColor: const Color(0xFFC8E6C9),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.fixedDeposit,
      icon: Icons.account_balance_outlined,
      color: const Color(0xFF37474F),
      bgColor: const Color(0xFFCFD8DC),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.insurancePolicy,
      icon: Icons.health_and_safety_outlined,
      color: const Color(0xFF1B5E20),
      bgColor: const Color(0xFFA5D6A7),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.intellectualProperty,
      icon: Icons.lightbulb_outline,
      color: const Color(0xFF4527A0),
      bgColor: const Color(0xFFD1C4E9),
    ),
    _AssetCategoryInfo(
      category: AssetCategory.collectible,
      icon: Icons.collections_outlined,
      color: const Color(0xFFAD1457),
      bgColor: const Color(0xFFF8BBD0),
    ),
  ];

  List<Asset> get _filteredAssets {
    if (_selectedCategoryFilter == null) return _assets;
    return _assets
        .where(
          (a) => Asset.categoryLabel(a.category) == _selectedCategoryFilter,
        )
        .toList();
  }

  double get _totalEstimatedValue =>
      _assets.fold<double>(0, (sum, a) => sum + a.estimatedValue);

  Map<String, double> get _categoryTotals {
    final totals = <String, double>{};
    for (final asset in _assets) {
      final label = asset.displayCategory;
      totals[label] = (totals[label] ?? 0) + asset.estimatedValue;
    }
    return totals;
  }

  String _fmtCurrency(double amount) {
    final abs = amount.abs();
    final formatted = abs.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '\u20B9$formatted';
  }

  // ── Add / Edit Dialog ─────────────────────────────────────────────────────

  Future<void> _showAddAssetDialog({Asset? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final valueCtrl = TextEditingController(
      text: existing != null ? existing.estimatedValue.toStringAsFixed(0) : '',
    );
    final locationCtrl =
        TextEditingController(text: existing?.location ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final customCatCtrl =
        TextEditingController(text: existing?.customCategoryName ?? '');

    AssetCategory selectedCategory = existing?.category ?? AssetCategory.property;
    PropertyType? selectedPropType = existing?.propertyType;
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Asset?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(existing != null ? 'Edit Asset' : 'Add New Asset'),
            content: SizedBox(
              width: 500,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Category dropdown
                      DropdownButtonFormField<AssetCategory>(
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: AssetCategory.values.map((cat) {
                          return DropdownMenuItem(
                            value: cat,
                            child: Text(Asset.categoryLabel(cat)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedCategory = val;
                              if (val != AssetCategory.property) {
                                selectedPropType = null;
                              }
                            });
                          }
                        },
                      ),

                      // Custom category name
                      if (selectedCategory == AssetCategory.custom) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: customCatCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Custom Category Name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (selectedCategory == AssetCategory.custom &&
                                (v == null || v.trim().isEmpty)) {
                              return 'Enter a name for the custom category';
                            }
                            return null;
                          },
                        ),
                      ],

                      // Property type
                      if (selectedCategory == AssetCategory.property) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<PropertyType>(
                          value: selectedPropType,
                          decoration: const InputDecoration(
                            labelText: 'Property Type',
                            border: OutlineInputBorder(),
                          ),
                          items: PropertyType.values.map((pt) {
                            return DropdownMenuItem(
                              value: pt,
                              child: Text(Asset.propertyTypeLabel(pt)),
                            );
                          }).toList(),
                          validator: (v) {
                            if (selectedCategory == AssetCategory.property &&
                                v == null) {
                              return 'Select a property type';
                            }
                            return null;
                          },
                          onChanged: (val) {
                            setDialogState(() => selectedPropType = val);
                          },
                        ),
                      ],

                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Asset Name',
                          hintText: 'e.g. Beach Villa, Gold Necklace, BTC Wallet',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: valueCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Estimated Value (\u20B9)',
                          border: OutlineInputBorder(),
                          prefixText: '\u20B9 ',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Enter estimated value';
                          }
                          if (double.tryParse(v.trim()) == null) {
                            return 'Enter a valid number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: locationCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Location (optional)',
                          hintText: 'e.g. SBI Main Branch, Chennai',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
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
                  final asset = Asset(
                    id: existing?.id ??
                        DateTime.now().millisecondsSinceEpoch.toString(),
                    category: selectedCategory,
                    name: nameCtrl.text.trim(),
                    description: descCtrl.text.trim().isNotEmpty
                        ? descCtrl.text.trim()
                        : null,
                    estimatedValue:
                        double.parse(valueCtrl.text.trim()),
                    location: locationCtrl.text.trim().isNotEmpty
                        ? locationCtrl.text.trim()
                        : null,
                    notes: notesCtrl.text.trim().isNotEmpty
                        ? notesCtrl.text.trim()
                        : null,
                    propertyType: selectedPropType,
                    customCategoryName: selectedCategory == AssetCategory.custom
                        ? customCatCtrl.text.trim()
                        : null,
                    createdAt: existing?.createdAt ?? now,
                    updatedAt: now,
                  );
                  Navigator.pop(ctx, asset);
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
          final idx = _assets.indexWhere((a) => a.id == existing.id);
          if (idx >= 0) _assets[idx] = result;
        } else {
          _assets.add(result);
        }
      });
    }
  }

  void _deleteAsset(Asset asset) {
    setState(() {
      _assets.removeWhere((a) => a.id == asset.id);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Assets',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Track and manage all your family assets in one place.',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _showAddAssetDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Asset'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Total Value Card ─────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Estimated Value',
                      style: TextStyle(
                        color: Colors.white.withAlpha(200),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _fmtCurrency(_totalEstimatedValue),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_assets.length} asset${_assets.length == 1 ? '' : 's'} across ${_categoryTotals.length} categor${_categoryTotals.length == 1 ? 'y' : 'ies'}',
                      style: TextStyle(
                        color: Colors.white.withAlpha(180),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Category Filter Chips ────────────────────────────────
              if (_assets.isNotEmpty) ...[
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: _selectedCategoryFilter == null,
                        onTap: () =>
                            setState(() => _selectedCategoryFilter = null),
                      ),
                      const SizedBox(width: 8),
                      ..._categoryTotals.keys.map((cat) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _FilterChip(
                            label: cat,
                            selected: _selectedCategoryFilter == cat,
                            onTap: () => setState(
                                () => _selectedCategoryFilter = cat),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Content ──────────────────────────────────────────────
              Expanded(
                child: _assets.isEmpty
                    ? _buildEmptyState()
                    : _buildAssetContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Category grid for quick-add
          _buildCategoryGrid(),
          const SizedBox(height: 32),
          Icon(Icons.account_balance_wallet_outlined,
              size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No assets added yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap a category above or use the Add Asset button\nto start tracking your assets.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetContent() {
    final filtered = _filteredAssets;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category grid (collapsed when assets exist)
          _buildCategoryGrid(),
          const SizedBox(height: 20),

          // Category breakdown cards
          if (_selectedCategoryFilter == null && _categoryTotals.length > 1) ...[
            const Text(
              'Breakdown by Category',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _categoryTotals.entries.map((entry) {
                final info = _getCategoryInfo(entry.key);
                final pct = _totalEstimatedValue > 0
                    ? (entry.value / _totalEstimatedValue * 100)
                    : 0.0;
                return _CategoryBreakdownCard(
                  label: entry.key,
                  value: _fmtCurrency(entry.value),
                  percentage: pct,
                  color: info?.color ?? AppColors.primary,
                  bgColor: info?.bgColor ?? AppColors.primaryLight.withAlpha(40),
                  icon: info?.icon ?? Icons.category,
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Asset list
          Text(
            _selectedCategoryFilter != null
                ? '$_selectedCategoryFilter (${filtered.length})'
                : 'All Assets (${filtered.length})',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...filtered.map((asset) => _AssetListTile(
                asset: asset,
                fmtCurrency: _fmtCurrency,
                categoryInfo: _getCategoryInfoByCategory(asset.category),
                onEdit: () => _showAddAssetDialog(existing: asset),
                onDelete: () => _deleteAsset(asset),
              )),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: _categoryInfoList.length + 1, // +1 for custom
      itemBuilder: (context, index) {
        if (index == _categoryInfoList.length) {
          // Add Custom tile
          return _CategoryTile(
            icon: Icons.add_circle_outline,
            label: 'Custom',
            color: AppColors.primary,
            bgColor: AppColors.primaryLight.withAlpha(40),
            onTap: () {
              _showAddAssetDialog();
            },
          );
        }
        final info = _categoryInfoList[index];
        final count =
            _assets.where((a) => a.category == info.category).length;
        return _CategoryTile(
          icon: info.icon,
          label: Asset.categoryLabel(info.category),
          color: info.color,
          bgColor: info.bgColor,
          badge: count > 0 ? count : null,
          onTap: () {
            // Pre-select this category in the add dialog
            _showAddAssetDialogWithCategory(info.category);
          },
        );
      },
    );
  }

  Future<void> _showAddAssetDialogWithCategory(AssetCategory category) async {
    // Show assets of this category if any exist, otherwise open add dialog
    final existing = _assets.where((a) => a.category == category).toList();
    if (existing.isNotEmpty) {
      setState(() {
        _selectedCategoryFilter = Asset.categoryLabel(category);
      });
    } else {
      final nameCtrl = TextEditingController();
      final descCtrl = TextEditingController();
      final valueCtrl = TextEditingController();
      final locationCtrl = TextEditingController();
      final notesCtrl = TextEditingController();

      PropertyType? selectedPropType;
      final formKey = GlobalKey<FormState>();

      final result = await showDialog<Asset?>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('Add ${Asset.categoryLabel(category)}'),
              content: SizedBox(
                width: 500,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (category == AssetCategory.property) ...[
                          DropdownButtonFormField<PropertyType>(
                            value: selectedPropType,
                            decoration: const InputDecoration(
                              labelText: 'Property Type',
                              border: OutlineInputBorder(),
                            ),
                            items: PropertyType.values.map((pt) {
                              return DropdownMenuItem(
                                value: pt,
                                child: Text(Asset.propertyTypeLabel(pt)),
                              );
                            }).toList(),
                            validator: (v) => v == null
                                ? 'Select a property type'
                                : null,
                            onChanged: (val) {
                              setDialogState(() => selectedPropType = val);
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: nameCtrl,
                          decoration: InputDecoration(
                            labelText: '${Asset.categoryLabel(category)} Name',
                            hintText: _hintForCategory(category),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Name is required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Description (optional)',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: valueCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Estimated Value (\u20B9)',
                            border: OutlineInputBorder(),
                            prefixText: '\u20B9 ',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter estimated value';
                            }
                            if (double.tryParse(v.trim()) == null) {
                              return 'Enter a valid number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: locationCtrl,
                          decoration: InputDecoration(
                            labelText: _locationLabelForCategory(category),
                            hintText: _locationHintForCategory(category),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Notes (optional)',
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
                    final asset = Asset(
                      id: now.millisecondsSinceEpoch.toString(),
                      category: category,
                      name: nameCtrl.text.trim(),
                      description: descCtrl.text.trim().isNotEmpty
                          ? descCtrl.text.trim()
                          : null,
                      estimatedValue: double.parse(valueCtrl.text.trim()),
                      location: locationCtrl.text.trim().isNotEmpty
                          ? locationCtrl.text.trim()
                          : null,
                      notes: notesCtrl.text.trim().isNotEmpty
                          ? notesCtrl.text.trim()
                          : null,
                      propertyType: selectedPropType,
                      createdAt: now,
                      updatedAt: now,
                    );
                    Navigator.pop(ctx, asset);
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          });
        },
      );

      if (result != null) {
        setState(() => _assets.add(result));
      }
    }
  }

  String _hintForCategory(AssetCategory cat) {
    switch (cat) {
      case AssetCategory.property:
        return 'e.g. Beach Plot in ECR';
      case AssetCategory.bankLocker:
        return 'e.g. SBI Main Branch Locker #42';
      case AssetCategory.bitcoin:
        return 'e.g. BTC Cold Wallet';
      case AssetCategory.jewellery:
        return 'e.g. Gold Necklace Set';
      case AssetCategory.art:
        return 'e.g. M.F. Husain Painting';
      case AssetCategory.antique:
        return 'e.g. Tanjore Bronze Lamp';
      case AssetCategory.vehicle:
        return 'e.g. Honda City 2024';
      case AssetCategory.gold:
        return 'e.g. 24K Gold Bars (100g)';
      case AssetCategory.stocks:
        return 'e.g. Reliance Industries 500 shares';
      case AssetCategory.mutualFunds:
        return 'e.g. SBI Blue Chip Fund';
      case AssetCategory.fixedDeposit:
        return 'e.g. HDFC 5-year FD';
      case AssetCategory.insurancePolicy:
        return 'e.g. LIC Jeevan Anand';
      case AssetCategory.intellectualProperty:
        return 'e.g. Mobile App Patent';
      case AssetCategory.collectible:
        return 'e.g. Vintage Stamp Collection';
      case AssetCategory.custom:
        return 'e.g. Rare Wine Collection';
    }
  }

  String _locationLabelForCategory(AssetCategory cat) {
    switch (cat) {
      case AssetCategory.bankLocker:
        return 'Bank & Branch';
      case AssetCategory.property:
        return 'Location / Address';
      case AssetCategory.bitcoin:
        return 'Wallet / Exchange';
      case AssetCategory.stocks:
      case AssetCategory.mutualFunds:
        return 'Broker / Platform';
      case AssetCategory.fixedDeposit:
        return 'Bank';
      case AssetCategory.insurancePolicy:
        return 'Provider';
      default:
        return 'Location (optional)';
    }
  }

  String _locationHintForCategory(AssetCategory cat) {
    switch (cat) {
      case AssetCategory.bankLocker:
        return 'e.g. SBI T. Nagar Branch';
      case AssetCategory.property:
        return 'e.g. 45, Anna Nagar, Chennai';
      case AssetCategory.bitcoin:
        return 'e.g. Ledger Nano X / WazirX';
      case AssetCategory.stocks:
      case AssetCategory.mutualFunds:
        return 'e.g. Zerodha / Groww';
      case AssetCategory.fixedDeposit:
        return 'e.g. ICICI Bank';
      case AssetCategory.insurancePolicy:
        return 'e.g. LIC / HDFC Life';
      default:
        return 'Where is this stored?';
    }
  }

  _AssetCategoryInfo? _getCategoryInfo(String label) {
    for (final info in _categoryInfoList) {
      if (Asset.categoryLabel(info.category) == label) return info;
    }
    return null;
  }

  _AssetCategoryInfo? _getCategoryInfoByCategory(AssetCategory cat) {
    for (final info in _categoryInfoList) {
      if (info.category == cat) return info;
    }
    return null;
  }
}

// ── Supporting Widgets ────────────────────────────────────────────────────────

class _AssetCategoryInfo {
  final AssetCategory category;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _AssetCategoryInfo({
    required this.category,
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}

class _CategoryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final int? badge;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 28, color: color),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }
}

class _CategoryBreakdownCard extends StatelessWidget {
  final String label;
  final String value;
  final double percentage;
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _CategoryBreakdownCard({
    required this.label,
    required this.value,
    required this.percentage,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${percentage.toStringAsFixed(1)}% of total',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetListTile extends StatelessWidget {
  final Asset asset;
  final String Function(double) fmtCurrency;
  final _AssetCategoryInfo? categoryInfo;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AssetListTile({
    required this.asset,
    required this.fmtCurrency,
    required this.categoryInfo,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = categoryInfo?.color ?? AppColors.primary;
    final bgColor = categoryInfo?.bgColor ??
        AppColors.primaryLight.withAlpha(40);
    final icon = categoryInfo?.icon ?? Icons.category;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
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
                  asset.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _buildSubtitle(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmtCurrency(asset.estimatedValue),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              if (asset.location != null)
                Text(
                  asset.location!,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[400]),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buildSubtitle() {
    final parts = <String>[asset.displayCategory];
    if (asset.category == AssetCategory.property && asset.propertyType != null) {
      parts.add(Asset.propertyTypeLabel(asset.propertyType!));
    }
    if (asset.description != null) parts.add(asset.description!);
    return parts.join(' \u00B7 ');
  }
}
