import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _friendCodeController = TextEditingController();

  bool _isRegisterMode = false;
  bool _isBusy = false;
  String? _errorText;

  bool _loadingCircle = false;
  String? _myTrustCode;
  List<TrustedPeer> _trustPeers = [];
  String? _circleError;
  bool _circleChanged = false;

  @override
  void initState() {
    super.initState();
    if (_apiService.isBackendConfigured && _apiService.currentUser != null) {
      _loadTrustCircle();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _friendCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadTrustCircle() async {
    if (!_apiService.isBackendConfigured || _apiService.currentUser == null) {
      return;
    }
    setState(() {
      _loadingCircle = true;
      _circleError = null;
    });

    final codeFuture = _apiService.getOrCreateMyTrustCode();
    final peersFuture = _apiService.fetchMyTrustCircle();
    final code = await codeFuture;
    final peers = await peersFuture;

    if (!mounted) return;
    setState(() {
      _myTrustCode = code;
      _trustPeers = peers;
      _loadingCircle = false;
    });
  }

  Future<void> _copyMyCode() async {
    final code = _myTrustCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Код $code скопирован')),
    );
  }

  Future<void> _addFriend() async {
    final raw = _friendCodeController.text.trim();
    if (raw.isEmpty) {
      setState(() => _circleError = 'Введите код друга');
      return;
    }

    setState(() {
      _isBusy = true;
      _circleError = null;
    });

    final err = await _apiService.addTrustedFriendByCode(raw);
    if (!mounted) return;

    if (err != null) {
      setState(() {
        _isBusy = false;
        _circleError = err;
      });
      return;
    }

    _friendCodeController.clear();
    _circleChanged = true;
    setState(() => _isBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Друг добавлен в ваш Круг доверия')),
    );
    await _loadTrustCircle();
  }

  Future<void> _removeFriend(TrustedPeer peer) async {
    setState(() {
      _isBusy = true;
      _circleError = null;
    });

    final err = await _apiService.removeTrustedFriend(peer.peerUserId);
    if (!mounted) return;

    if (err != null) {
      setState(() {
        _isBusy = false;
        _circleError = err;
      });
      return;
    }

    _circleChanged = true;
    setState(() => _isBusy = false);
    await _loadTrustCircle();
  }

  Future<void> _submitEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isBusy = true;
      _errorText = null;
    });

    final String? err;
    if (_isRegisterMode) {
      err = await _apiService.signUpWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
        displayName: _nameController.text.trim().isEmpty
            ? 'Рыбак'
            : _nameController.text.trim(),
      );
    } else {
      err = await _apiService.signInWithEmail(
        _emailController.text,
        _passwordController.text,
      );
    }

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _errorText = err;
    });

    if (err == null) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _signInGuest() async {
    setState(() {
      _isBusy = true;
      _errorText = null;
    });
    final err = await _apiService.signInAsGuest();
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _errorText = err;
    });
    if (err == null) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _signOut() async {
    setState(() => _isBusy = true);
    await _apiService.signOut();
    if (!mounted) return;
    setState(() => _isBusy = false);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final user = _apiService.currentUser;
    final outgoingPeers = _trustPeers.where((p) => p.isOutgoing).toList();
    final incomingPeers = _trustPeers.where((p) => !p.isOutgoing).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_circleChanged);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Профиль рыбака')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (!_apiService.isBackendConfigured)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Облако сейчас не подключено (нет ключей сервера). '
                    'Вы можете отмечать точки и треки в локальном режиме.',
                  ),
                ),
              )
            else if (user != null) ...[
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(_apiService.currentAuthorName),
                  subtitle: Text(
                    user.isAnonymous
                        ? 'Гостевой профиль (точки привязаны к этому устройству)'
                        : (user.email ?? 'Авторизован'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Круг доверия',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Отправьте свой код напарнику, чтобы он открыл вам свои секретные точки, '
                'или введите код напарника — тогда он увидит точные координаты ваших точек.',
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Мой код для друзей',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      if (_loadingCircle && _myTrustCode == null)
                        const LinearProgressIndicator()
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: SelectableText(
                                    _myTrustCode ?? 'Не удалось получить',
                                    maxLines: 1,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          letterSpacing: 1.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Обновить код',
                                onPressed:
                                    _loadingCircle ? null : _loadTrustCircle,
                                icon: const Icon(Icons.refresh),
                              ),
                              IconButton.filledTonal(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Копировать код',
                                onPressed:
                                    _myTrustCode == null ? null : _copyMyCode,
                                icon: const Icon(Icons.copy, size: 18),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _friendCodeController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Код напарника (напр. FR1A2B3C)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _isBusy ? null : _addFriend,
                            child: const Text('Добавить'),
                          ),
                        ],
                      ),
                      if (_circleError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _circleError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (outgoingPeers.isNotEmpty) ...[
                Text(
                  'Кому я доверяю свои точки (${outgoingPeers.length})',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                ...outgoingPeers.map(
                  (peer) => Card(
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text(peer.peerName),
                      subtitle: const Text('Видит точные координаты'),
                      trailing: IconButton(
                        tooltip: 'Удалить из круга',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _isBusy ? null : () => _removeFriend(peer),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (incomingPeers.isNotEmpty) ...[
                Text(
                  'Кто доверяет мне (${incomingPeers.length})',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                ...incomingPeers.map(
                  (peer) => Card(
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.visibility_outlined),
                      title: Text(peer.peerName),
                      subtitle:
                          const Text('Вы видите точные точки этого рыбака'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isBusy ? null : _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Выйти из профиля'),
              ),
            ] else ...[
              Text(
                _isRegisterMode ? 'Регистрация' : 'Вход в аккаунт',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                'Аккаунт нужен, чтобы редактировать свои точки, скрывать точные '
                'координаты от других в «Круге доверия» и общаться в чате.',
              ),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    if (_isRegisterMode) ...[
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Имя / позывной на воде',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Введите корректный email'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Пароль (от 6 символов)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Минимум 6 символов'
                          : null,
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isBusy ? null : _submitEmail,
                        child: _isBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                _isRegisterMode ? 'Создать аккаунт' : 'Войти',
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isBusy
                          ? null
                          : () => setState(() {
                                _isRegisterMode = !_isRegisterMode;
                                _errorText = null;
                              }),
                      child: Text(
                        _isRegisterMode
                            ? 'Уже есть аккаунт? Войти'
                            : 'Нет аккаунта? Зарегистрироваться',
                      ),
                    ),
                    const Divider(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _signInGuest,
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Быстрый гостевой вход'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
