import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_dimensions.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_text_styles.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  
  DateTime? _dateOfBirth;
  String? _profileImageUrl;
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Load profile data after the first frame to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserProfile();
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _loadUserProfile() {
    if (!mounted) return;

    try {
      final authService = context.read<AuthService>();
      final user = authService.currentUser;

      if (user != null) {
        setState(() {
          _emailController.text = user.email;
          _phoneController.text = user.phoneNumber ?? '';
          _dateOfBirth = user.dateOfBirth;
          _profileImageUrl = user.photoUrl;

          // Use dedicated first/last name fields if available
          if (user.firstName != null && user.firstName!.isNotEmpty) {
            _firstNameController.text = user.firstName!;
            _lastNameController.text = user.lastName ?? '';
          } else if (user.displayName != null) {
            // Fallback: parse display name
            final nameParts = user.displayName!.split(' ');
            _firstNameController.text = nameParts.first;
            if (nameParts.length > 1) {
              _lastNameController.text = nameParts.sublist(1).join(' ');
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Profile load skipped due to unavailable auth context: $e');
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
      });
    }
  }

  Future<void> _uploadPhoto() async {
    // Photo upload functionality
    // In a real app, would use image_picker package or file_picker
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Photo upload coming soon!'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final authService = context.read<AuthService>();
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final displayName = '$firstName $lastName'.trim();
      final phone = _phoneController.text.trim();
      final dob = _dateOfBirth != null
          ? '${_dateOfBirth!.year.toString().padLeft(4, '0')}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}'
          : null;

      await authService.updateProfile(
        displayName: displayName,
        firstName: firstName,
        lastName: lastName,
        phone: phone.isNotEmpty ? phone : null,
        dateOfBirth: dob,
      );

      setState(() {
        _isEditing = false;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _getInitials(String fallbackEmail) {
    String initials = '';
    if (_firstNameController.text.isNotEmpty) {
      initials += _firstNameController.text[0].toUpperCase();
    }
    if (_lastNameController.text.isNotEmpty) {
      initials += _lastNameController.text[0].toUpperCase();
    }
    if (initials.isEmpty) {
      initials = fallbackEmail.substring(0, 1).toUpperCase();
    }
    return initials;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    AuthService? authService;
    try {
      authService = context.watch<AuthService>();
    } catch (e) {
      debugPrint('ProfileScreen: Provider not found: $e');
    }
    final user = authService?.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Profile'),
        titleTextStyle: const TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 18,
          fontWeight: AppTextStyles.bold,
          color: Color(0xFF0F172A),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
        actions: [
          if (user != null && !_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF475569)),
              onPressed: () => Navigator.of(context).pushNamed('/notifications'),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: FilledButton.icon(
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit Profile'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  textStyle: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: AppTextStyles.semiBold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
          if (user != null && _isEditing) ...[
            TextButton(
              onPressed: () {
                setState(() => _isEditing = false);
                _loadUserProfile();
              },
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: FilledButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ],
      ),
      body: user == null
          ? _buildNoUser(context)
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroCard(context, user),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumn = constraints.maxWidth > 580;
                            final cards = [
                              _buildPersonalInfoCard(context),
                              _buildContactInfoCard(context),
                              _buildHouseholdInfoCard(context, user, authService),
                              _buildAccountDetailsCard(context, user),
                            ];
                            if (twoColumn) {
                              return Column(
                                children: [
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(child: cards[0]),
                                        const SizedBox(width: 24),
                                        Expanded(child: cards[1]),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(child: cards[2]),
                                        const SizedBox(width: 24),
                                        Expanded(child: cards[3]),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            } else {
                              return Column(
                                children: [
                                  cards[0],
                                  const SizedBox(height: 16),
                                  cards[1],
                                  const SizedBox(height: 16),
                                  cards[2],
                                  const SizedBox(height: 16),
                                  cards[3],
                                ],
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 32),
                        Center(
                          child: TextButton.icon(
                            onPressed: authService != null
                                ? () => _handleSignOut(context, authService!)
                                : null,
                            icon: const Icon(Icons.logout_rounded, size: 20),
                            label: const Text('Sign Out'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade600,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: const TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontWeight: AppTextStyles.semiBold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ── UI Helpers ──────────────────────────────────────────────────────────────

  Widget _buildNoUser(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(AppIcons.person, size: 64, color: AppColors.primary),
          const SizedBox(height: 16),
          const Text(
            'Unable to load profile',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 16,
              fontWeight: AppTextStyles.semiBold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'User session not available',
            style: TextStyle(fontFamily: AppTextStyles.fontFamily, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, AppUser user) {
    final initials = _getInitials(user.email);
    final displayName = user.displayName ??
        '${_firstNameController.text} ${_lastNameController.text}'.trim();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 480;
          final avatarSize = wide ? 140.0 : 110.0;

          final avatarSection = Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.1),
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  image: _profileImageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(_profileImageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _profileImageUrl == null
                    ? Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: wide ? 42 : 32,
                            fontWeight: AppTextStyles.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : null,
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: GestureDetector(
                  onTap: _uploadPhoto,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          );

          final infoSection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      displayName.isEmpty ? user.email : displayName,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 22,
                        fontWeight: AppTextStyles.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'Platinum Member',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 10,
                        fontWeight: AppTextStyles.bold,
                        color: Color(0xFF2563EB),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mail_outline_rounded, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        user.email,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.phone_outlined, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          user.phoneNumber!,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFD1FAE5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF059669)),
                        SizedBox(width: 6),
                        Text(
                          'KYC Verified',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            fontWeight: AppTextStyles.semiBold,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Feature coming soon',
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.share_outlined, size: 15),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text('My QR'),
                          SizedBox(width: 4),
                          Icon(Icons.close_rounded, size: 11, color: Colors.red),
                        ],
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        disabledForegroundColor: const Color(0xFF475569),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontWeight: AppTextStyles.semiBold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatarSection,
                const SizedBox(width: 24),
                Expanded(child: infoSection),
              ],
            );
          } else {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatarSection,
                const SizedBox(height: 16),
                infoSection,
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildPersonalInfoCard(BuildContext context) {
    return _buildInfoCard(
      context,
      title: 'Personal Information',
      icon: AppIcons.person,
      children: _isEditing
          ? [
              Row(children: [
                Expanded(
                  child: _buildTextField(
                    controller: _firstNameController,
                    label: 'First Name',
                    icon: AppIcons.person,
                    enabled: true,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _lastNameController,
                    label: 'Last Name',
                    icon: AppIcons.person,
                    enabled: true,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _buildDateField(
                label: 'Date of Birth',
                icon: AppIcons.calendar,
                date: _dateOfBirth,
                enabled: true,
                onTap: _selectDate,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _phoneController,
                label: 'Phone Number',
                icon: AppIcons.phone,
                enabled: true,
                keyboardType: TextInputType.phone,
              ),
            ]
          : [
              _buildLabelValue(context, label: 'First Name', value: _firstNameController.text.isEmpty ? '—' : _firstNameController.text),
              _buildLabelValue(context, label: 'Last Name', value: _lastNameController.text.isEmpty ? '—' : _lastNameController.text),
              _buildLabelValue(context, label: 'Date of Birth', value: _dateOfBirth != null ? _formatDate(_dateOfBirth) : '—'),
              _buildLabelValue(context, label: 'Phone Number', value: _phoneController.text.isEmpty ? '—' : _phoneController.text),
            ],
    );
  }

  Widget _buildContactInfoCard(BuildContext context) {
    return _buildInfoCard(
      context,
      title: 'Contact Information',
      icon: Icons.mail_outline_rounded,
      children: _isEditing
          ? [
              _buildTextField(
                controller: _emailController,
                label: 'Email',
                icon: AppIcons.email,
                enabled: false,
              ),
            ]
          : [
              _buildLabelValue(
                context,
                label: 'Email Address',
                value: _emailController.text.isEmpty ? '—' : _emailController.text,
              ),
            ],
    );
  }

  Widget _buildHouseholdInfoCard(BuildContext context, AppUser user, AuthService? authService) {
    final householdName = authService?.currentHousehold?.name ?? 'No Household';
    final roleStr = user.role.isNotEmpty
        ? user.role[0].toUpperCase() + user.role.substring(1)
        : 'Member';
    return _buildInfoCard(
      context,
      title: 'Household Information',
      icon: Icons.groups_outlined,
      children: [
        _buildLabelValue(context, label: 'Family Group', value: householdName),
        _buildLabelValueWithBadge(context, label: 'Role', badge: roleStr),
        _buildLabelValue(context, label: 'Member Since', value: _formatJoinDate(user.createdAt)),
      ],
    );
  }

  Widget _buildAccountDetailsCard(BuildContext context, AppUser user) {
    final userId = user.id.length >= 8 ? user.id.substring(0, 8) : user.id;
    final roleStr = user.role.isNotEmpty
        ? user.role[0].toUpperCase() + user.role.substring(1)
        : 'Member';
    return _buildInfoCard(
      context,
      title: 'Account Details',
      icon: Icons.account_circle_outlined,
      children: [
        _buildLabelValue(context, label: 'User ID', value: userId, isMonospace: true),
        _buildLabelValue(context, label: 'Account Role', value: roleStr),
        _buildLabelValue(context, label: 'Account Created', value: _formatDate(user.createdAt)),
      ],
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Row(children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 16,
                  fontWeight: AppTextStyles.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ]),
          ),
          Container(height: 1, color: const Color(0xFFF1F5F9)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelValue(
    BuildContext context, {
    required String label,
    required String value,
    bool isMonospace = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11,
              fontWeight: AppTextStyles.semiBold,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: isMonospace ? 'monospace' : AppTextStyles.fontFamily,
              fontSize: 15,
              fontWeight: AppTextStyles.medium,
              color: const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelValueWithBadge(
    BuildContext context, {
    required String label,
    required String badge,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11,
              fontWeight: AppTextStyles.semiBold,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                fontWeight: AppTextStyles.bold,
                color: AppColors.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSignOut(BuildContext context, AuthService authService) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await authService.signOut();
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool enabled,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        color: onSurface,
      ),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelStyle: const TextStyle(color: AppColors.primary),
        prefixIcon: Icon(icon, size: AppDimensions.iconMedium, color: AppColors.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
          borderSide: BorderSide(color: AppColors.primary.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
          borderSide: const BorderSide(color: AppColors.primary, width: AppDimensions.borderWidthThick),
        ),
        filled: !enabled,
        fillColor: enabled ? null : AppColors.grey100,
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required IconData icon,
    required DateTime? date,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          floatingLabelStyle: const TextStyle(color: AppColors.primary),
          prefixIcon: Icon(icon, size: AppDimensions.iconMedium, color: AppColors.primary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            borderSide: BorderSide(color: AppColors.primary.withOpacity(0.3)),
          ),
          filled: !enabled,
          fillColor: enabled ? null : AppColors.grey100,
        ),
        child: Text(
          date != null ? _formatDate(date) : 'Not set',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: date != null
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatJoinDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays < 30) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 365) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else {
      return '${(difference.inDays / 365).floor()}y ago';
    }
  }
}
