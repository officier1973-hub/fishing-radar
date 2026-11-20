import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  static const _regions = [
    'Волга / Самара',
    'Кама',
    'Дон',
    'Москва / Ока',
    'Обь / Сибирь',
    'Общий чат',
  ];

  String _selectedRegion = _regions.first;
  final List<ChatMessage> _messages = [];
  RealtimeChannel? _channel;
  bool _isLoading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectRegion(_selectedRegion);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_apiService.unsubscribeChannel(_channel));
    _msgController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // После выключения/включения экрана сбрасываем зависшую отправку и переподключаем чат
      if (_sending) {
        setState(() => _sending = false);
      }
      _inputFocusNode.unfocus();
      _connectRegion(_selectedRegion, keepExisting: true);
    }
  }

  Future<void> _connectRegion(
    String region, {
    bool keepExisting = false,
  }) async {
    final oldChannel = _channel;
    _channel = null;
    unawaited(_apiService.unsubscribeChannel(oldChannel));

    setState(() {
      if (!keepExisting) {
        _messages.clear();
        _isLoading = true;
      }
    });

    final loaded = await _apiService.fetchRegionMessages(region);
    if (!mounted || region != _selectedRegion) return;

    setState(() {
      _messages.clear();
      for (final m in loaded) {
        _upsertMessage(m);
      }
      _isLoading = false;
    });
    _scrollToBottom();

    _channel = _apiService.subscribeToRegionChat(region, (incoming) {
      if (!mounted || region != _selectedRegion) return;
      setState(() {
        _upsertMessage(incoming);
      });
      _scrollToBottom();
    });
  }

  void _upsertMessage(ChatMessage msg) {
    final idx = _messages.indexWhere((m) => m.id == msg.id);
    if (idx != -1) {
      _messages[idx] = msg;
    } else {
      _messages.add(msg);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _sending) return;

    final region = _selectedRegion;
    setState(() => _sending = true);

    try {
      final (sentMsg, err) = await _apiService.sendRegionMessage(region, text);
      if (!mounted) return;

      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
        return;
      }

      _msgController.clear();
      if (sentMsg != null && region == _selectedRegion) {
        setState(() => _upsertMessage(sentMsg));
        _scrollToBottom();
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _apiService.currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Чат водоёмов'),
        actions: [
          IconButton(
            tooltip: 'Обновить чат',
            icon: const Icon(Icons.refresh),
            onPressed: () => _connectRegion(_selectedRegion, keepExisting: true),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SizedBox(
            height: 46,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _regions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final region = _regions[index];
                return ChoiceChip(
                  label: Text(region),
                  selected: _selectedRegion == region,
                  onSelected: (_) {
                    if (_selectedRegion == region) return;
                    setState(() => _selectedRegion = region);
                    _connectRegion(region);
                  },
                );
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (!_apiService.isBackendConfigured)
            Container(
              width: double.infinity,
              color: Colors.orange.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: const Text(
                'Локальный режим: сообщения видны только на этом устройстве.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'В комнате «$_selectedRegion» пока пусто.\n'
                            'Напишите, как обстановка на воде: уровень, прозрачность, клёв.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (_, index) {
                          final m = _messages[index];
                          final isMine = myId != null && m.userId == myId;
                          final timeStr =
                              DateFormat('dd.MM HH:mm').format(m.createdAt);
                          return Align(
                            key: ValueKey(m.id),
                            alignment: isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.78,
                              ),
                              decoration: BoxDecoration(
                                color: isMine
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${m.authorName} • $timeStr',
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(m.text),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: _inputFocusNode,
                      controller: _msgController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Обстановка на воде...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
