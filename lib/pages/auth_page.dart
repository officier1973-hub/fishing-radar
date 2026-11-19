import 'package:flutter/material.dart';
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

  bool _isRegisterMode = false;
  bool _isBusy = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
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

    return Scaffold(
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
            const Text(
              'Вы можете редактировать и удалять свои точки, публиковать фото '
              'уловов и скрывать точные координаты в «Круге доверия».',
            ),
            const SizedBox(height: 20),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _isRegisterMode
                                  ? 'Создать аккаунт'
                                  : 'Войти',
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
    );
  }
}
