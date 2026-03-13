import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_user.dart';
import '../models/member.dart';
import '../services/family_service.dart';
import '../widgets/app_header.dart';
import '../theme/app_icons.dart';

const _kMaxHouseholdSize = 8;

/// Displays and manages household members.
///
/// Admin capabilities: invite by phone, remove members.
/// Member view:        read-only member list.
///
/// Required:
///   [familyService]  — injected service for all API calls
///   [currentUser]    — logged-in user (determines admin vs member view)
///   [householdName]  — displayed in the AppBar subtitle
class FamilyManagementScreen extends StatefulWidget {
  const FamilyManagementScreen({
    super.key,
    required this.familyService,
    required this.currentUser,
    required this.householdName,
  });

  final FamilyService familyService;
  final AppUser       currentUser;
  final String        householdName;

  @override
  State<FamilyManagementScreen> createState() => _FamilyManagementScreenState();
}

class _FamilyManagementScreenState extends State<FamilyManagementScreen> {
  List<Member> _members       = [];
  bool         _isLoading     = true;
  String?      _errorMessage;
  String?      _removingId;   // userId currently being removed (shows inline spinner)

  bool get _isAdmin    => widget.currentUser.isAdmin;
  bool get _isFull     => _members.length >= _kMaxHouseholdSize;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  // ── Data ──────────────────────────────────────────────────────────────────
  Future<void> _loadMembers() async {
    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });
    try {
      final members = await widget.familyService.fetchMembers();
      if (mounted) setState(() => _members = members);
    } on FamilyException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to load members. Pull down to retry.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Invite flow ───────────────────────────────────────────────────────────
  Future<void> _openInviteSheet() async {
    final result = await showModalBottomSheet<InviteResult>(
      context:       context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InviteSheet(familyService: widget.familyService),
    );

    if (result == null || !mounted) return;

    // Show invite code immediately after sheet closes
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InviteCodeDialog(result: result),
    );
  }

  // ── Remove flow ───────────────────────────────────────────────────────────
  Future<void> _confirmRemove(Member member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          'Remove ${member.displayLabel} from ${widget.householdName}?\n\n'
          'Their data will be retained but they will lose access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _removingId = member.id);
    try {
      await widget.familyService.removeMember(member.id);
      if (mounted) {
        setState(() => _members.removeWhere((m) => m.id == member.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.displayLabel} has been removed.')),
        );
      }
    } on FamilyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:         Text(e.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Family',
              subtitle: widget.householdName,
              avatarIcon: AppIcons.groupOutlined,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadMembers,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isAdmin && !_isLoading && _errorMessage == null
          ? _InviteFab(isFull: _isFull, onPressed: _openInviteSheet)
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _ErrorState(
        message:  _errorMessage!,
        onRetry:  _loadMembers,
      );
    }

    if (_members.isEmpty) {
      return const _EmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadMembers,
      child: CustomScrollView(
        slivers: [
          // Capacity header
          SliverToBoxAdapter(
            child: _CapacityHeader(
              count:   _members.length,
              max:     _kMaxHouseholdSize,
              isAdmin: _isAdmin,
              isFull:  _isFull,
            ),
          ),

          // Member list
          SliverList.builder(
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final member = _members[index];
              final isCurrentUser = member.id == widget.currentUser.id;
              final isRemoving    = _removingId == member.id;

              return _MemberTile(
                member:         member,
                isCurrentUser:  isCurrentUser,
                isAdmin:        _isAdmin,
                isRemoving:     isRemoving,
                onRemove:       // Admins can remove any non-admin, non-self member
                    _isAdmin && !isCurrentUser && !member.isAdmin
                        ? () => _confirmRemove(member)
                        : null,
              );
            },
          ),

          // Bottom padding for FAB
          const SliverToBoxAdapter(child: SizedBox(height: 88)),
        ],
      ),
    );
  }
}

// ── Member tile ───────────────────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isCurrentUser,
    required this.isAdmin,
    required this.isRemoving,
    this.onRemove,
  });

  final Member     member;
  final bool       isCurrentUser;
  final bool       isAdmin;
  final bool       isRemoving;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _Avatar(member: member),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.displayLabel,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 6),
            _Badge(label: 'You', color: cs.primaryContainer, textColor: cs.onPrimaryContainer),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (member.displayName != null)
            Text(member.phone, style: TextStyle(fontSize: 12, color: cs.outline)),
          const SizedBox(height: 2),
          _Badge(
            label:     member.isAdmin ? 'Admin' : 'Member',
            color:     member.isAdmin ? cs.secondaryContainer : cs.surfaceContainerHighest,
            textColor: member.isAdmin ? cs.onSecondaryContainer : cs.onSurfaceVariant,
          ),
        ],
      ),
      trailing: isRemoving
          ? SizedBox(
              width:  20,
              height: 20,
              child:  CircularProgressIndicator(strokeWidth: 2, color: cs.error),
            )
          : onRemove != null
              ? IconButton(
                  icon:    Icon(AppIcons.personRemove, color: cs.error),
                  tooltip: 'Remove member',
                  onPressed: onRemove,
                )
              : null,
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.member});
  final Member member;

  String get _initials {
    final label = member.displayName?.trim() ?? member.phone;
    if (label.isEmpty) return '?';
    // For phones like +919876543210, use last 2 digits
    if (label.startsWith('+') || RegExp(r'^\d').hasMatch(label)) {
      return label.substring(label.length >= 2 ? label.length - 2 : 0);
    }
    final words = label.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length >= 2) return '${words[0][0]}${words[1][0]}'.toUpperCase();
    return label[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: member.isAdmin ? cs.primaryContainer : cs.secondaryContainer,
      child: Text(
        _initials,
        style: TextStyle(
          fontSize:   13,
          fontWeight: FontWeight.w600,
          color:      member.isAdmin ? cs.onPrimaryContainer : cs.onSecondaryContainer,
        ),
      ),
    );
  }
}

// ── Badge ─────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, required this.textColor});
  final String label;
  final Color  color;
  final Color  textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color:        color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: textColor),
      ),
    );
  }
}

// ── Capacity header ───────────────────────────────────────────────────────────

class _CapacityHeader extends StatelessWidget {
  const _CapacityHeader({
    required this.count,
    required this.max,
    required this.isAdmin,
    required this.isFull,
  });

  final int  count;
  final int  max;
  final bool isAdmin;
  final bool isFull;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            'Members',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        isFull ? cs.errorContainer : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count / $max',
              style: TextStyle(
                fontSize:   12,
                fontWeight: FontWeight.w600,
                color:      isFull ? cs.onErrorContainer : cs.onSurfaceVariant,
              ),
            ),
          ),
          if (isFull && isAdmin) ...[
            const SizedBox(width: 8),
            Text(
              'Full',
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ],
        ],
      ),
    );
  }
}

// ── FAB ───────────────────────────────────────────────────────────────────────

class _InviteFab extends StatelessWidget {
  const _InviteFab({required this.isFull, required this.onPressed});
  final bool         isFull;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed:   isFull ? null : onPressed,
      icon:        const Icon(AppIcons.personAdd),
      label:       const Text('Invite'),
      tooltip:     isFull ? 'Household is full' : 'Invite a member',
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String       message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.wifiOff, size: 48, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon:  const Icon(AppIcons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.groupOutlined, size: 56, color: cs.outline),
          const SizedBox(height: 16),
          Text('No members yet', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ── Invite bottom sheet ────────────────────────────────────────────────────────

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.familyService});
  final FamilyService familyService;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _formKey   = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  bool    _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error   = null;
    });

    try {
      final result = await widget.familyService.inviteMember(_phoneCtrl.text.trim());
      if (mounted) Navigator.of(context).pop(result);
    } on FamilyException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final viewInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color:        cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + viewInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width:  40,
                height: 4,
                decoration: BoxDecoration(
                  color:        cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text('Invite a member', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Enter their phone number. You\'ll get a code to share with them.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // Phone field
            TextFormField(
              controller:  _phoneCtrl,
              autofocus:   true,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText:  'Phone number',
                hintText:   '+919876543210',
                prefixIcon: Icon(AppIcons.phone),
                border:     OutlineInputBorder(),
              ),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Phone number is required.';
                if (v.length < 6) return 'Enter a valid phone number.';
                return null;
              },
            ),

            // Error message
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color:        cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              ),
            ],

            const SizedBox(height: 20),

            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _loading
                  ? const SizedBox(
                      width:  20,
                      height: 20,
                      child:  CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Generate invite code'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Invite code dialog ────────────────────────────────────────────────────────

class _InviteCodeDialog extends StatefulWidget {
  const _InviteCodeDialog({required this.result});
  final InviteResult result;

  @override
  State<_InviteCodeDialog> createState() => _InviteCodeDialogState();
}

class _InviteCodeDialogState extends State<_InviteCodeDialog> {
  bool _copied = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.result.inviteCode));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  String _formatExpiry(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.inDays > 0)   return 'Expires in ${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    if (diff.inHours > 0)  return 'Expires in ${diff.inHours} hour${diff.inHours == 1 ? '' : 's'}';
    return 'Expires soon';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Invite code ready'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Share this code with ${widget.result.phoneNumber}.\n'
            'They\'ll enter it in the app to join.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Code display
          GestureDetector(
            onTap: _copyCode,
            child: Container(
              width:   double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color:        cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    widget.result.inviteCode,
                    style: TextStyle(
                      fontSize:    32,
                      fontWeight:  FontWeight.w700,
                      letterSpacing: 6,
                      fontFamily:  'monospace',
                      color:       cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatExpiry(widget.result.expiresAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Copy button
          OutlinedButton.icon(
            onPressed: _copyCode,
            icon:  Icon(_copied ? AppIcons.check : AppIcons.copy, size: 18),
            label: Text(_copied ? 'Copied!' : 'Copy code'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
