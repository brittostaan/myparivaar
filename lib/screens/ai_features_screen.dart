import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/ai_service.dart';
import '../widgets/app_header.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

class AIFeaturesScreen extends StatefulWidget {
  const AIFeaturesScreen({super.key});

  @override
  State<AIFeaturesScreen> createState() => _AIFeaturesScreenState();
}

class _AIFeaturesScreenState extends State<AIFeaturesScreen> {
  final AIService _aiService = AIService();
  
  String? _weeklySummary;
  bool _loadingSummary = false;
  String? _summaryError;
  
  final TextEditingController _chatController = TextEditingController();
  final List<ChatMessage> _chatMessages = [];
  bool _sendingMessage = false;
  
  // Usage tracking
  int _chatQueriesUsed = 0;
  int _chatQueriesLimit = 5;

  @override
  void initState() {
    super.initState();
    _loadWeeklySummary();
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _loadWeeklySummary() async {
    setState(() {
      _loadingSummary = true;
      _summaryError = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final summary = await _aiService.getWeeklySummary(
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (mounted) {
        setState(() {
          _weeklySummary = summary['summary'];
          _loadingSummary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _summaryError = e.toString();
          _loadingSummary = false;
        });
      }
    }
  }

  Future<void> _sendChatMessage() async {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;

    // Add user message to chat
    setState(() {
      _chatMessages.add(ChatMessage(
        text: message,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _sendingMessage = true;
    });

    _chatController.clear();

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final response = await _aiService.sendChatMessage(
        message: message,
        supabaseUrl: authService.supabaseUrl,
        idToken: await authService.getIdToken(),
      );

      if (mounted) {
        setState(() {
          _chatMessages.add(ChatMessage(
            text: response['response'],
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _chatQueriesUsed = response['queries_used'];
          _chatQueriesLimit = response['monthly_limit'];
          _sendingMessage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages.add(ChatMessage(
            text: 'Sorry, I encountered an error: $e',
            isUser: false,
            timestamp: DateTime.now(),
            isError: true,
          ));
          _sendingMessage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const AppHeader(
                title: 'AI Insights',
                avatarIcon: AppIcons.smartToy,
              ),
              // Quick-access AI tools
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildAIToolCard(
                        icon: Icons.warning_amber_rounded,
                        label: 'Anomaly Detection',
                        color: Colors.orange,
                        onTap: () => Navigator.pushNamed(context, '/anomaly-detection'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildAIToolCard(
                        icon: Icons.trending_up,
                        label: 'Financial Simulator',
                        color: Colors.teal,
                        onTap: () => Navigator.pushNamed(context, '/financial-simulator'),
                      ),
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(icon: Icon(AppIcons.summarize), text: 'Weekly Summary'),
                  Tab(icon: Icon(AppIcons.chat), text: 'AI Chat'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildWeeklySummaryTab(),
                    _buildChatTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAIToolCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color.withOpacity(0.9),
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: color.withOpacity(0.5), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklySummaryTab() {
    return RefreshIndicator(
      onRefresh: _loadWeeklySummary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(AppIcons.insights, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'This Week\'s Insights',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_loadingSummary)
                      const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Analyzing your spending patterns...'),
                          ],
                        ),
                      )
                    else if (_summaryError != null)
                      Column(
                        children: [
                          const Icon(AppIcons.error, size: 48, color: AppColors.warning),
                          const SizedBox(height: 16),
                          Text(
                            'Unable to generate weekly summary',
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _summaryError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.grey600),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadWeeklySummary,
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    else if (_weeklySummary != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _weeklySummary!,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Generated: ${DateTime.now().toString().substring(0, 16)}',
                            style: const TextStyle(
                              color: AppColors.grey600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      )
                    else
                      const Column(
                        children: [
                          Icon(AppIcons.timeline, size: 48, color: AppColors.grey600),
                          SizedBox(height: 16),
                          Text(
                            'No summary available',
                            style: TextStyle(fontSize: 16),
                          ),
                          Text('Track some expenses to get AI insights!'),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About AI Insights',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Weekly summaries are generated once per week\n'
                      '• AI analyzes your spending patterns and budget performance\n'
                      '• Insights are personalized to your family\'s data\n'
                      '• AI does not provide financial advice or recommendations',
                      style: TextStyle(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        // Usage indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12.0),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            'Questions used: $_chatQueriesUsed / $_chatQueriesLimit this month',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
        
        // Chat messages
        Expanded(
          child: _chatMessages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(AppIcons.chat, size: 64, color: AppColors.grey400),
                      const SizedBox(height: 16),
                      Text(
                        'Ask me about your finances',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Try asking:\n• "How much did I spend this month?"\n• "What\'s my top spending category?"\n• "How are my budgets doing?"',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: _chatMessages.length,
                  itemBuilder: (context, index) {
                    final message = _chatMessages[index];
                    return _buildChatMessage(message);
                  },
                ),
        ),
        
        // Loading indicator
        if (_sendingMessage)
          Container(
            padding: const EdgeInsets.all(8.0),
            child: const Row(
              children: [
                SizedBox(width: 16),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('AI is thinking...'),
              ],
            ),
          ),
        
        // Input field
        Container(
          padding: const EdgeInsets.all(8.0),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.grey300),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: const InputDecoration(
                    hintText: 'Ask about your spending...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _chatQueriesUsed < _chatQueriesLimit ? _sendChatMessage() : null,
                  enabled: !_sendingMessage && _chatQueriesUsed < _chatQueriesLimit,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: (!_sendingMessage && _chatQueriesUsed < _chatQueriesLimit) 
                    ? _sendChatMessage 
                    : null,
                icon: const Icon(AppIcons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatMessage(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: message.isUser 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: message.isError 
                  ? AppColors.errorLight
                  : Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: Icon(
                message.isError ? AppIcons.error : AppIcons.smartToy,
                size: 16,
                color: message.isError 
                    ? AppColors.errorDark
                    : Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: message.isUser 
                    ? Theme.of(context).primaryColor
                    : message.isError 
                        ? AppColors.errorLight
                        : AppColors.grey100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      color: message.isUser 
                          ? Colors.white
                          : message.isError 
                              ? AppColors.errorDark
                              : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 10,
                      color: message.isUser 
                          ? Colors.white70
                          : AppColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          if (message.isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: Icon(
                AppIcons.person,
                size: 16,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  });
}