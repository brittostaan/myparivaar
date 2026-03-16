import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_dimensions.dart';
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

  @override
  Widget build(BuildContext context) {
    AuthService? authService;
    try {
      authService = context.watch<AuthService>();
    } catch (e) {
      debugPrint('ProfileScreen: Provider not found: $e');
    }
    final user = authService?.currentUser;
    debugPrint('ProfileScreen build: user=${user?.email}, authService=${authService != null}');

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(AppIcons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('My Profile'),
        titleTextStyle: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 18,
          fontWeight: AppTextStyles.bold,
          color: colorScheme.onSurface,
        ),
        actions: [
          if (user != null && !_isEditing)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
              icon: const Icon(AppIcons.edit, size: AppDimensions.iconSmall),
              label: const Text('Edit'),
            ),
          if (user != null && _isEditing) ...[
            TextButton(
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _loadUserProfile();
                });
              },
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppDimensions.spacingSmall),
            FilledButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: _isSaving
                  ? const SizedBox(
                      width: AppDimensions.iconXs,
                      height: AppDimensions.iconXs,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(width: AppDimensions.spacingMedium),
          ],
        ],
      ),
      body: user == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(AppIcons.person, size: AppDimensions.iconXxl, color: AppColors.primary),
                  const SizedBox(height: AppDimensions.spacingMedium),
                  Text(
                    'Unable to load profile',
                    style: AppTextStyles.cardTitle(colorScheme.onSurface),
                  ),
                  const SizedBox(height: AppDimensions.spacingSmall),
                  Text(
                    'User session not available',
                    style: AppTextStyles.hint(colorScheme.onSurface),
                  ),
                  const SizedBox(height: AppDimensions.spacingLarge),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: AppDimensions.paddingAllLarge,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Profile Photo Section
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withOpacity(0.1),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.3),
                                width: 3,
                              ),
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
                                      _getInitials(user.email),
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 42,
                                        fontWeight: AppTextStyles.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          if (_isEditing)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colorScheme.surface,
                                    width: 3,
                                  ),
                                ),
                                child: IconButton(
                                  icon: const Icon(AppIcons.camera, color: Colors.white, size: AppDimensions.iconSmall),
                                  onPressed: _uploadPhoto,
                                  tooltip: 'Upload Photo',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingXl),
                    // Personal Information Section
                    _buildSectionCard(
                      context,
                      title: 'Personal Information',
                      icon: AppIcons.person,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _firstNameController,
                                label: 'First Name',
                                icon: AppIcons.person,
                                enabled: _isEditing,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'First name is required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: AppDimensions.spacingMedium),
                            Expanded(
                              child: _buildTextField(
                                controller: _lastNameController,
                                label: 'Last Name',
                                icon: AppIcons.person,
                                enabled: _isEditing,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Last name is required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppDimensions.spacingMedium),
                        _buildDateField(
                          label: 'Date of Birth',
                          icon: AppIcons.calendar,
                          date: _dateOfBirth,
                          enabled: _isEditing,
                          onTap: _isEditing ? _selectDate : null,
                        ),
                        const SizedBox(height: AppDimensions.spacingMedium),
                        _buildTextField(
                          controller: _phoneController,
                          label: 'Phone Number',
                          icon: AppIcons.phone,
                          enabled: _isEditing,
                          keyboardType: TextInputType.phone,
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              if (value.length < 10) {
                                return 'Enter a valid phone number';
                              }
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spacingMedium),

                    // Contact Information Section
                    _buildSectionCard(
                      context,
                      title: 'Contact Information',
                      icon: AppIcons.email,
                      children: [
                        _buildTextField(
                          controller: _emailController,
                          label: 'Email',
                          icon: AppIcons.email,
                          enabled: false,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Email is required';
                            }
                            if (!value.contains('@')) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spacingMedium),

                    // Household Information Section
                    _buildSectionCard(
                      context,
                      title: 'Household Information',
                      icon: AppIcons.home,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: AppDimensions.avatarMedium,
                            height: AppDimensions.avatarMedium,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
                            ),
                            child: const Icon(
                              AppIcons.home,
                              size: AppDimensions.iconMedium,
                              color: AppColors.primary,
                            ),
                          ),
                          title: Text(
                            authService?.currentHousehold?.name ?? 'No Household',
                            style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurface),
                          ),
                          subtitle: Text(
                            user.isAdmin ? 'Admin' : 'Member',
                            style: AppTextStyles.hint(colorScheme.onSurface),
                          ),
                          trailing: IconButton(
                            icon: const Icon(AppIcons.arrowForward, size: AppDimensions.iconSmall, color: AppColors.primary),
                            onPressed: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).pushNamed('/family');
                            },
                          ),
                        ),
                        if (authService?.currentHousehold != null) ...[
                          const Divider(height: AppDimensions.spacingLarge),
                          _buildInfoChip(
                            context,
                            icon: AppIcons.calendar,
                            label: 'Member Since',
                            value: _formatJoinDate(user.createdAt),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spacingMedium),

                    // Account Information Section
                    _buildSectionCard(
                      context,
                      title: 'Account Information',
                      icon: AppIcons.info,
                      children: [
                        _buildInfoRow(
                          context,
                          label: 'User ID',
                          value: user.id.substring(0, 8),
                          icon: AppIcons.info,
                        ),
                        const Divider(height: AppDimensions.spacingLarge),
                        _buildInfoRow(
                          context,
                          label: 'Role',
                          value: user.role,
                          icon: AppIcons.adminPanel,
                        ),
                        const Divider(height: AppDimensions.spacingLarge),
                        _buildInfoRow(
                          context,
                          label: 'Member Since',
                          value: _formatDate(user.createdAt),
                          icon: AppIcons.calendar,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: AppDimensions.cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        side: const BorderSide(color: AppColors.grey200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: AppDimensions.paddingAllSmall,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
                  ),
                  child: Icon(
                    icon,
                    size: AppDimensions.iconSmall,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: AppTextStyles.cardTitle(colorScheme.onSurface),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingLarge),
            ...children,
          ],
        ),
      ),
    );
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

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          icon,
          size: AppDimensions.iconSmall,
          color: AppColors.primary,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.hint(colorScheme.onSurface),
            ),
            const SizedBox(height: AppDimensions.spacingXs),
            Text(
              value,
              style: AppTextStyles.cardSubtitle(colorScheme.onSurface).copyWith(
                fontWeight: AppTextStyles.semiBold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: AppDimensions.iconSmall,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppDimensions.spacingSmall),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.hint(colorScheme.onSurface),
                ),
                Text(
                  value,
                  style: AppTextStyles.cardSubtitle(colorScheme.onSurface).copyWith(
                    fontWeight: AppTextStyles.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
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
