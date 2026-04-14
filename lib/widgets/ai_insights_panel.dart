import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

/// A quick-start prompt card configuration for the AI Insights panel.
class AIQuickPrompt {
  final IconData icon;
  final String label;
  final Color color;
  final String prompt;

  const AIQuickPrompt({
    required this.icon,
    required this.label,
    required this.color,
    required this.prompt,
  });
}

/// Default quick prompts shown when no custom prompts are provided.
const List<AIQuickPrompt> defaultQuickPrompts = [
  AIQuickPrompt(
    icon: Icons.history_rounded,
    label: 'Historical Performance',
    color: Color(0xFF7C4DFF),
    prompt:
        'Show me my historical budget performance over the last 6 months. How many months did I stay within budget? What are the trends?',
  ),
  AIQuickPrompt(
    icon: Icons.insights_rounded,
    label: 'Budget Analytics',
    color: Color(0xFF00ACC1),
    prompt:
        'Analyze my budget categories. Which categories am I overspending on? What is my average monthly spend and which category is most volatile?',
  ),
];

/// Reusable AI Insights panel with budget analysis and AI chat.
///
/// Can be used as a side panel or embedded widget in any screen.
/// Supports custom quick-start prompts per screen context.
class AIInsightsPanel extends StatefulWidget {
  final VoidCallback onClose;
  final String analysisLabel;
  final List<AIQuickPrompt>? quickPrompts;

  const AIInsightsPanel({
    super.key,
    required this.onClose,
    this.analysisLabel = 'Budget Analysis',
    this.quickPrompts,
  });

  @override
  State<AIInsightsPanel> createState() => _AIInsightsPanelState();
}

class _AIInsightsPanelState extends State<AIInsightsPanel> {
  bool _loading = false;
  String? _analysis;
  String? _error;

  final _chatController = TextEditingController();
  final List<_ChatMessage> _chatMessages = [];
  bool _chatLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchAnalysis();
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _fetchAnalysis() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().getBudgetAnalysis(
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) {
        setState(() {
          _analysis = result['analysis'] as String?;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _sendChat() async {
    final msg = _chatController.text.trim();
    if (msg.isEmpty) return;
    _chatController.clear();
    setState(() {
      _chatMessages.add(_ChatMessage(text: msg, isUser: true));
      _chatLoading = true;
    });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final result = await AIService().sendChatMessage(
        message: msg,
        supabaseUrl: auth.supabaseUrl,
        idToken: await auth.getIdToken(),
      );
      if (mounted) {
        setState(() {
          _chatMessages.add(_ChatMessage(
            text: result['response'] as String? ?? 'No response',
            isUser: false,
          ));
          _chatLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages.add(_ChatMessage(text: 'Error: $e', isUser: false));
          _chatLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompts = widget.quickPrompts ?? defaultQuickPrompts;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 20, color: Color(0xFF9C27B0)),
              const SizedBox(width: 8),
              const Text('AI Insights',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: _loading ? null : _fetchAnalysis,
                icon: const Icon(Icons.refresh, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Refresh analysis',
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Analysis section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [Colors.purple.shade50, Colors.blue.shade50]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics_outlined,
                        size: 16, color: Colors.purple[600]),
                    const SizedBox(width: 6),
                    Text(widget.analysisLabel,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.purple[700])),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  )
                else if (_error != null)
                  Text(_error!,
                      style: TextStyle(fontSize: 12, color: Colors.red[600]))
                else if (_analysis != null)
                  Text(_analysis!,
                      style: const TextStyle(fontSize: 12, height: 1.5))
                else
                  Text('Tap refresh to generate AI analysis',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Chat section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 16, color: Colors.purple[400]),
                    const SizedBox(width: 6),
                    Text('Ask AI',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.purple[600])),
                  ],
                ),
                const SizedBox(height: 8),

                // Chat messages
                if (_chatMessages.isNotEmpty) ...[
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _chatMessages.length,
                        itemBuilder: (ctx, i) {
                          final msg = _chatMessages[i];
                          return Align(
                            alignment: msg.isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: msg.isUser
                                    ? Colors.purple[100]
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: msg.isUser
                                    ? null
                                    : Border.all(color: Colors.grey[200]!),
                              ),
                              child: Text(msg.text,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (_chatLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Text('Thinking...',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ] else
                  const Spacer(),

                // Chat input
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        decoration: InputDecoration(
                          hintText: 'Ask about your finances...',
                          hintStyle:
                              TextStyle(fontSize: 13, color: Colors.grey[400]),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                        onSubmitted: (_) => _sendChat(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _chatLoading ? null : _sendChat,
                      icon:
                          Icon(Icons.send_rounded, color: Colors.purple[600]),
                      tooltip: 'Send',
                    ),
                  ],
                ),
                if (prompts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (int i = 0; i < prompts.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _quickPromptCard(
                            icon: prompts[i].icon,
                            label: prompts[i].label,
                            color: prompts[i].color,
                            prompt: prompts[i].prompt,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickPromptCard({
    required IconData icon,
    required String label,
    required Color color,
    required String prompt,
  }) {
    return Material(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          _chatController.text = prompt;
          _sendChat();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  const _ChatMessage({required this.text, required this.isUser});
}
