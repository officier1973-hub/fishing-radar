import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _msgController = TextEditingController();

  static const _regions = [
    'Волга / Самара',
    'Кама',
    'Дон',
    'Москва / Ока',
    'Обь / Сибирь',
    'Общий чат',
  ];

  String _selectedRegion = _regions.first;
  bool _sending = false;

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final err = await _apiService.sendRegionMessage(_selectedRegion, text);
    if (!mounted) return;
    setState(() => _sending = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    _msgController.clear();
    if (!_apiService.isBackendConfigured) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _apiService.currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Чат водоёмов'),
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
                  onSelected: (_) => setState(() => _selectedRegion = region),
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
            child: StreamBuilder<List<ChatMessage>>(
              key: ValueKey(_selectedRegion),
              stream: _apiService.watchRegionMessages(_selectedRegion),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'В комнате «$_selectedRegion» пока пусто.\n'
                        'Напишите, как обстановка на воде: уровень, прозрачность, клёв.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (_, index) {
                    final m = messages[index];
                    final isMine = myId != null && m.userId == myId;
                    final timeStr = DateFormat('dd.MM HH:mm').format(m.createdAt);
                    return Align(
                      alignment:
                          isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78,
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Theme.of(context).colorScheme.primaryContainer
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
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            const SizedBox(height: 3),
                            Text(m.text),
                          ],
                        ),
                      ),
                    );
                  },
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
                    icon: const Icon(Icons.send),
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
