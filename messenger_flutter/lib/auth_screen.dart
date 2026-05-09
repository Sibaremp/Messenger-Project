import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/sim_service.dart';
import 'services/auth_service.dart' as svc;
import 'theme.dart' show ThemeProvider, AppThemeMode;

// ─── AuthGate — точка входа в приложение ─────────────────────────────────────
//
// При запуске проверяет сохранённую сессию:
//   - есть сессия  → сразу открывает homeScreen
//   - нет сессии   → показывает AuthScreen

class AuthGate extends StatelessWidget {
  final Widget homeScreen;
  final svc.AuthService auth;

  const AuthGate({super.key, required this.homeScreen, required this.auth});

  @override
  Widget build(BuildContext context) {
    // Если сессия восстановлена в main.dart, сразу открываем чат
    if (auth.currentUser != null) return homeScreen;
    return AuthScreen(
      auth: auth,
      onLoginSuccess: () {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => homeScreen),
          (_) => false,
        );
      },
    );
  }
}

// ─── Экран авторизации ────────────────────────────────────────────────────────

class AuthScreen extends StatefulWidget {
  final svc.AuthService auth;
  final VoidCallback? onLoginSuccess;

  const AuthScreen({super.key, required this.auth, this.onLoginSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final subtleColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenW = MediaQuery.of(context).size.width;
    final isDesktop = screenW > 600;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? 440.0 : double.infinity),
            child: Column(
              children: [
                // ── Шапка ──────────────────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(24, isDesktop ? 24 : 48, 24, 0),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4765B),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.chat_bubble_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Caspian Messenger',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Войдите или создайте аккаунт',
                        style: TextStyle(fontSize: 14, color: subtleColor),
                      ),
                      const SizedBox(height: 24),
                      // ── Табы + кнопка темы ─────────────────
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: TabBar(
                                controller: _tabController,
                                indicator: BoxDecoration(
                                  color: const Color(0xFFD4765B),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                indicatorSize: TabBarIndicatorSize.tab,
                                labelColor: Colors.white,
                                unselectedLabelColor: const Color(0xFF757575),
                                labelStyle: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                dividerColor: Colors.transparent,
                                tabs: const [
                                  Tab(text: 'Вход'),
                                  Tab(text: 'Регистрация'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Переключатель темы
                          GestureDetector(
                            onTap: () {
                              final tp = ThemeProvider.of(context);
                              final next = isDark ? AppThemeMode.light : AppThemeMode.dark;
                              tp.setMode(next);
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                                color: const Color(0xFFD4765B),
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ── Форма (скроллируется) ──────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        child: _LoginForm(
                          auth: widget.auth,
                          tabController: _tabController,
                          onLoginSuccess: widget.onLoginSuccess ?? () {},
                        ),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        child: _RegisterForm(
                          auth: widget.auth,
                          tabController: _tabController,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Форма входа ──────────────────────────────────────────────────────────────

class _LoginForm extends StatefulWidget {
  final svc.AuthService auth;
  final TabController tabController;
  final VoidCallback onLoginSuccess;

  const _LoginForm({
    required this.auth,
    required this.tabController,
    required this.onLoginSuccess,
  });

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _snack(String text, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await widget.auth.login(
        name: _loginController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      widget.onLoginSuccess();
    } on svc.AuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack(e.message, color: Colors.red[700]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Ошибка подключения к серверу', color: Colors.red[700]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _AuthField(
            controller: _loginController,
            label: 'Имя пользователя',
            icon: Icons.person_outline,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
          ),
          const SizedBox(height: 16),
          _AuthField(
            controller: _passwordController,
            label: 'Пароль',
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
            suffixIcon: _VisibilityButton(
              obscure: _obscurePassword,
              onTap: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 24),
          _AuthButton(
            label: 'Войти',
            isLoading: _isLoading,
            onPressed: _submit,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => widget.tabController.animateTo(1),
            child: const Text(
              'Нет аккаунта? Зарегистрироваться',
              style: TextStyle(color: Color(0xFFD4765B)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Форма регистрации — 4-шаговый мастер ────────────────────────────────────
//
//  Шаг 0 — Выбор роли (Студент / Преподаватель)
//  Шаг 1 — Выбор учебной группы (только студенты; преподаватели пропускают)
//  Шаг 2 — Выбор себя из справочника (ФИО)
//  Шаг 3 — Придумать логин и пароль

class _RegisterForm extends StatefulWidget {
  final svc.AuthService auth;
  final TabController tabController;

  const _RegisterForm({required this.auth, required this.tabController});

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  // ── Навигация ──────────────────────────────────────────────────────────────

  int _step     = 0;  // 0=роль · 1=группа · 2=персона · 3=реквизиты
  int _prevStep = -1; // для определения направления анимации

  bool get _isForward => _step >= _prevStep;

  // ── Данные, собираемые по шагам ────────────────────────────────────────────

  String             _role           = 'student';
  String?            _selectedGroup;
  svc.PersonRecord?  _selectedPerson;

  // ── Данные шага 1 (группы) ─────────────────────────────────────────────────

  List<String> _groups       = [];
  bool         _groupsLoading = false;
  String?      _groupsError;

  // ── Данные шага 2 (персоны) ────────────────────────────────────────────────

  List<svc.PersonRecord> _people         = [];
  List<svc.PersonRecord> _filteredPeople = [];
  bool                   _peopleLoading  = false;
  String?                _peopleError;
  final _personSearchCtrl = TextEditingController();

  // ── Данные шага 3 (реквизиты) ──────────────────────────────────────────────

  final _formKey     = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _isSubmitting   = false;
  bool _simLoading     = false;

  // ── Вспомогательные геттеры ────────────────────────────────────────────────

  int get _totalSteps   => _role == 'teacher' ? 3 : 4;

  /// Номер шага для отображения (1-based, учитывает пропуск группы у преподавателя).
  int get _displayStep {
    if (_role == 'teacher') {
      if (_step == 0) return 1;
      if (_step == 2) return 2;
      return 3;
    }
    return _step + 1;
  }

  bool get _canGoNext {
    if (_step == 1) return _selectedGroup != null;
    if (_step == 2) return _selectedPerson != null;
    return true;
  }

  // ── Жизненный цикл ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _personSearchCtrl.addListener(_filterPeople);
  }

  @override
  void dispose() {
    _personSearchCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Загрузка данных ────────────────────────────────────────────────────────

  Future<void> _loadGroups() async {
    setState(() { _groupsLoading = true; _groupsError = null; });
    try {
      final g = await widget.auth.loadGroups();
      if (!mounted) return;
      setState(() {
        _groups       = g;
        _groupsLoading = false;
        if (g.isEmpty) _groupsError = 'Список групп пуст';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _groupsLoading = false;
        _groupsError   = 'Не удалось загрузить группы. Проверьте подключение.';
      });
    }
  }

  Future<void> _loadPeople() async {
    setState(() {
      _peopleLoading  = true;
      _peopleError    = null;
      _people         = [];
      _filteredPeople = [];
    });
    _personSearchCtrl.clear();
    try {
      final list = await widget.auth.loadPeople(
        role:  _role,
        group: _role == 'student' ? _selectedGroup : null,
      );
      if (!mounted) return;
      setState(() {
        _people         = list;
        _filteredPeople = list;
        _peopleLoading  = false;
        if (list.isEmpty) _peopleError = 'Список пуст';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _peopleLoading = false; _peopleError = 'Ошибка загрузки'; });
    }
  }

  void _filterPeople() {
    final q = _personSearchCtrl.text.trim().toUpperCase();
    setState(() {
      _filteredPeople = q.isEmpty
          ? _people
          : _people.where((p) => p.fullName.toUpperCase().contains(q)).toList();
    });
  }

  // ── Навигация ─────────────────────────────────────────────────────────────

  void _navigate(int newStep) =>
      setState(() { _prevStep = _step; _step = newStep; });

  void _goNext() {
    if (_step == 0) {
      if (_role == 'teacher') {
        _loadPeople();
        _navigate(2);
      } else {
        _navigate(1);
      }
    } else if (_step == 1) {
      _loadPeople();
      _navigate(2);
    } else if (_step == 2) {
      _navigate(3);
    }
  }

  void _goBack() {
    if (_step == 2 && _role == 'teacher') {
      _navigate(0);
    } else {
      _navigate(_step - 1);
    }
  }

  // ── Отправка ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.auth.register(
        personId: _selectedPerson!.id,
        name:     _nameCtrl.text.trim(),
        password: _passCtrl.text,
        phone: _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : null,
      );
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      widget.tabController.animateTo(0);
      _snack('Аккаунт создан! Теперь войдите.', color: const Color(0xFFD4765B));
    } on svc.AuthException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _snack(e.message, color: Colors.red[700]);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _snack('Ошибка подключения к серверу', color: Colors.red[700]);
    }
  }

  // ── SIM ───────────────────────────────────────────────────────────────────

  Future<void> _fillFromSim() async {
    setState(() => _simLoading = true);
    final result = await SimService.fetchSimCards();
    if (!mounted) return;
    setState(() => _simLoading = false);
    switch (result.status) {
      case SimResult.success:
        final sims = result.simCards;
        if (sims.length == 1) {
          _applySimCard(sims.first);
        } else {
          _showSimPicker(sims);
        }
      case SimResult.unsupported:
        _snack('Определение номера SIM недоступно на этой платформе');
      case SimResult.permissionDenied:
        _snack('Нет доступа к данным телефона');
      case SimResult.permissionPermanentlyDenied:
        _snack(
          'Разрешение отклонено. Откройте настройки приложения.',
          action: SnackBarAction(label: 'Настройки', onPressed: SimService.openSettings),
        );
      case SimResult.noSimFound:
        _snack('SIM-карта не обнаружена или не вставлена');
      case SimResult.error:
        _snack('Ошибка: ${result.errorMessage ?? "неизвестная"}');
    }
  }

  void _applySimCard(SimCard sim) {
    if (sim.phoneNumber?.isNotEmpty == true) {
      _phoneCtrl.text = sim.phoneNumber!;
      _snack('Номер: ${sim.phoneNumber} (${sim.displayInfo})');
    } else {
      _snack('Оператор: ${sim.displayInfo}. Введите номер вручную.');
    }
  }

  void _showSimPicker(List<SimCard> sims) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Выберите SIM-карту',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ...sims.map((sim) => ListTile(
              leading: const Icon(Icons.sim_card_outlined, color: Color(0xFFD4765B)),
              title: Text(sim.slotLabel),
              subtitle: Text(sim.displayInfo),
              trailing: sim.phoneNumber != null
                  ? Text(sim.phoneNumber!, style: const TextStyle(fontSize: 13))
                  : const Text('номер неизвестен',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () { Navigator.pop(context); _applySimCard(sim); },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _snack(String text, {SnackBarAction? action, Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      action: action,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStepIndicator(),
        const SizedBox(height: 20),
        // Анимированная смена контента при переходе между шагами
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 270),
          switchInCurve:  Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) {
            final dir = _isForward ? 0.07 : -0.07;
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(dir, 0),
                  end:   Offset.zero,
                ).animate(anim),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(_step),
            child: _buildCurrentStep(),
          ),
        ),
        const SizedBox(height: 16),
        _buildNavRow(),
      ],
    );
  }

  // ── Индикатор прогресса (пилюли) ─────────────────────────────────────────

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalSteps, (i) {
        final num       = i + 1;
        final isCurrent = num == _displayStep;
        final isDone    = num < _displayStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width:  isCurrent ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: (isCurrent || isDone)
                ? const Color(0xFFD4765B)
                : const Color(0xFFD4765B).withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── Текущий шаг ───────────────────────────────────────────────────────────

  Widget _buildCurrentStep() => switch (_step) {
    0 => _buildRoleStep(),
    1 => _buildGroupStep(),
    2 => _buildPersonStep(),
    3 => _buildCredentialsStep(),
    _ => const SizedBox.shrink(),
  };

  // ── Шаг 0: роль ───────────────────────────────────────────────────────────

  Widget _buildRoleStep() {
    final subtleColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Кто вы?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Выберите вашу роль в учебном заведении',
            style: TextStyle(fontSize: 14, color: subtleColor)),
        const SizedBox(height: 16),
        _AuthRoleSelector(
          value: _role,
          onChanged: (r) => setState(() => _role = r),
        ),
      ],
    );
  }

  // ── Шаг 1: группа ─────────────────────────────────────────────────────────

  Widget _buildGroupStep() {
    final subtleColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Учебная группа',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Выберите группу, в которой вы учитесь',
            style: TextStyle(fontSize: 14, color: subtleColor)),
        const SizedBox(height: 16),
        _GroupSelectField(
          value:      _selectedGroup,
          showError:  false,
          groups:     _groups,
          isLoading:  _groupsLoading,
          errorText:  _groupsError,
          onRetry:    _loadGroups,
          onChanged:  (g) => setState(() => _selectedGroup = g),
        ),
      ],
    );
  }

  // ── Шаг 2: персона ────────────────────────────────────────────────────────

  Widget _buildPersonStep() {
    final subtleColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final cardColor = Theme.of(context).cardColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Найдите себя',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Выберите ваше ФИО из списка',
            style: TextStyle(fontSize: 14, color: subtleColor)),
        const SizedBox(height: 12),
        // Поиск
        TextField(
          controller: _personSearchCtrl,
          decoration: InputDecoration(
            hintText:   'Поиск по ФИО...',
            prefixIcon: const Icon(Icons.search, color: Color(0xFFD4765B)),
            filled:     true,
            fillColor:  cardColor,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD4765B), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Список
        SizedBox(height: 220, child: _buildPeopleList(subtleColor)),
        // Подтверждение выбора
        if (_selectedPerson != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFD4765B).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFD4765B).withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFFD4765B), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_selectedPerson!.fullName,
                      style: const TextStyle(
                          color: Color(0xFFD4765B),
                          fontWeight: FontWeight.w600)),
                ),
                GestureDetector(
                  onTap: () => setState(() => _selectedPerson = null),
                  child: const Icon(Icons.close,
                      color: Color(0xFFD4765B), size: 18),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPeopleList(Color subtleColor) {
    if (_peopleLoading) {
      return const Center(
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: Color(0xFFD4765B)));
    }
    if (_peopleError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red[400], size: 28),
            const SizedBox(height: 6),
            Text(_peopleError!, style: TextStyle(color: Colors.red[400])),
            TextButton(
              onPressed: _loadPeople,
              child: const Text('Повторить',
                  style: TextStyle(color: Color(0xFFD4765B))),
            ),
          ],
        ),
      );
    }
    if (_filteredPeople.isEmpty) {
      return Center(
          child: Text(
        _people.isEmpty ? 'Нет данных' : 'Никого не найдено',
        style: TextStyle(color: subtleColor),
      ));
    }
    return ListView.builder(
      itemCount: _filteredPeople.length,
      itemBuilder: (_, i) {
        final p        = _filteredPeople[i];
        final selected = _selectedPerson?.id == p.id;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          dense:   true,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor:
                selected ? const Color(0xFFD4765B) : Theme.of(context).cardColor,
            child: Text(
              p.fullName.isNotEmpty ? p.fullName[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : subtleColor,
              ),
            ),
          ),
          title: Text(
            p.fullName,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color:      selected ? const Color(0xFFD4765B) : null,
            ),
          ),
          trailing: selected
              ? const Icon(Icons.check_circle_rounded,
                  color: Color(0xFFD4765B), size: 20)
              : null,
          onTap: () => setState(() => _selectedPerson = p),
        );
      },
    );
  }

  // ── Шаг 3: данные входа ────────────────────────────────────────────────────

  Widget _buildCredentialsStep() {
    final subtleColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Данные для входа',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Придумайте логин и пароль',
              style: TextStyle(fontSize: 14, color: subtleColor)),
          const SizedBox(height: 16),
          // Имя — автоматически из ФИО, не редактируется
          if (_selectedPerson != null)
            _ReadOnlyField(
              label: 'Имя',
              value: _selectedPerson!.fullName,
              icon:  Icons.badge_outlined,
            ),
          if (_selectedPerson != null) const SizedBox(height: 12),
          _AuthField(
            controller: _nameCtrl,
            label:     'Логин',
            icon:       Icons.alternate_email,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Введите логин' : null,
          ),
          const SizedBox(height: 12),
          _AuthField(
            controller:  _passCtrl,
            label:       'Пароль',
            icon:        Icons.lock_outline,
            obscureText: _obscurePass,
            suffixIcon: _VisibilityButton(
              obscure: _obscurePass,
              onTap: () => setState(() => _obscurePass = !_obscurePass),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 12),
          _AuthField(
            controller:  _confirmCtrl,
            label:       'Подтвердите пароль',
            icon:        Icons.lock_outline,
            obscureText: _obscureConfirm,
            suffixIcon: _VisibilityButton(
              obscure: _obscureConfirm,
              onTap: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            validator: (v) =>
                v != _passCtrl.text ? 'Пароли не совпадают' : null,
          ),
          if (SimService.isSupported) ...[
            const SizedBox(height: 12),
            _PhoneField(
              controller: _phoneCtrl,
              onSimTap:   _fillFromSim,
              simLoading: _simLoading,
            ),
          ],
        ],
      ),
    );
  }

  // ── Кнопки навигации ──────────────────────────────────────────────────────

  Widget _buildNavRow() {
    final isFirst = _step == 0;
    final isLast  = _step == 3;
    return Row(
      children: [
        if (!isFirst) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: _isSubmitting ? null : _goBack,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFFD4765B)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Назад',
                  style: TextStyle(
                      color: Color(0xFFD4765B),
                      fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: isFirst ? 1 : 2,
          child: isLast
              ? _AuthButton(
                  label:     'Зарегистрироваться',
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                )
              : FilledButton(
                  onPressed: (_canGoNext && !_groupsLoading)
                      ? _goNext
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD4765B),
                    disabledBackgroundColor:
                        const Color(0xFFD4765B).withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Далее',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
        ),
      ],
    );
  }
}

// ─── Валидаторы ──────────────────────────────────────────────────────────────

String? _validatePassword(String? v) {
  if (v == null || v.isEmpty) return 'Введите пароль';
  if (v.length < 6) return 'Минимум 6 символов';
  return null;
}

// ─── Поле телефона ────────────────────────────────────────────────────────────

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onSimTap;
  final bool simLoading;

  const _PhoneField({
    required this.controller,
    this.onSimTap,
    this.simLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final hint = SimService.canReadNumber
        ? 'Нажмите SIM для заполнения'
        : '+7 (999) 000-00-00';

    final base = _inputDecoration(
      'Номер телефона', Icons.phone_outlined,
      Theme.of(context).cardColor,
      hintText: hint,
    );

    final decoration = (onSimTap != null && SimService.isSupported)
        ? base.copyWith(
            suffixIcon: simLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.sim_card_outlined),
                    tooltip: SimService.canReadNumber
                        ? 'Заполнить из SIM-карты'
                        : 'Показать оператора',
                    onPressed: onSimTap,
                  ),
          )
        : base;

    final isReadOnly = SimService.canReadNumber;

    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      readOnly: isReadOnly,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
        LengthLimitingTextInputFormatter(16),
      ],
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        final digits = v.replaceAll(RegExp(r'\D'), '');
        if (digits.length < 10) return 'Некорректный номер';
        return null;
      },
      decoration: decoration,
    );
  }
}

// ─── Общие виджеты ────────────────────────────────────────────────────────────

InputDecoration _inputDecoration(
  String label,
  IconData icon,
  Color fillColor, {
  String? hintText,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    prefixIcon: Icon(icon, color: const Color(0xFFD4765B)),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: fillColor,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD4765B), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
    ),
  );
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _AuthField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: _inputDecoration(
        label, icon, Theme.of(context).cardColor,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class _VisibilityButton extends StatelessWidget {
  final bool obscure;
  final VoidCallback onTap;

  const _VisibilityButton({required this.obscure, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscure ? Icons.visibility_off : Icons.visibility,
        color: const Color(0xFF757575),
      ),
      onPressed: onTap,
    );
  }
}

class _AuthButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  const _AuthButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFD4765B),
          disabledBackgroundColor:
              const Color(0xFFD4765B).withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

// ─── Поле выбора группы ───────────────────────────────────────────────────────

class _GroupSelectField extends StatelessWidget {
  final String? value;
  final bool showError;
  final List<String> groups;
  final bool isLoading;
  final String? errorText;
  final VoidCallback? onRetry;
  final ValueChanged<String?> onChanged;

  const _GroupSelectField({
    required this.value,
    required this.showError,
    required this.groups,
    required this.isLoading,
    required this.onChanged,
    this.errorText,
    this.onRetry,
  });

  Future<void> _openPicker(BuildContext context) async {
    if (isLoading) return;
    if (groups.isEmpty) {
      // Группы не загружены — пытаемся перезагрузить
      onRetry?.call();
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GroupPickerSheet(current: value, groups: groups),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final cardColor   = Theme.of(context).cardColor;
    final subtleColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final hasLoadError = !isLoading && groups.isEmpty && errorText != null;
    return GestureDetector(
      onTap: () => _openPicker(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: (showError || hasLoadError)
                  ? Border.all(color: const Color(0xFFE53935), width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                const Icon(Icons.school_outlined, color: Color(0xFFD4765B), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: isLoading
                      ? const Text('Загрузка групп...',
                          style: TextStyle(fontSize: 16, color: Color(0xFF757575)))
                      : Text(
                          hasValue ? value! : 'Учебная группа',
                          style: TextStyle(
                            fontSize: 16,
                            color: hasValue ? null : subtleColor,
                          ),
                        ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (hasLoadError)
                  const Icon(Icons.refresh, color: Color(0xFFE53935))
                else
                  Icon(Icons.expand_more, color: subtleColor),
              ],
            ),
          ),
          if (hasLoadError)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 6),
              child: Text(
                '${errorText!} Нажмите, чтобы повторить.',
                style: const TextStyle(fontSize: 12, color: Color(0xFFE53935)),
              ),
            )
          else if (showError)
            const Padding(
              padding: EdgeInsets.only(left: 12, top: 6),
              child: Text(
                'Выберите учебную группу',
                style: TextStyle(fontSize: 12, color: Color(0xFFE53935)),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Нижний лист выбора группы ────────────────────────────────────────────────

class _GroupPickerSheet extends StatefulWidget {
  final String? current;
  final List<String> groups;
  const _GroupPickerSheet({this.current, required this.groups});

  @override
  State<_GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends State<_GroupPickerSheet> {
  final _searchController = TextEditingController();
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.groups;
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchController.text.trim().toUpperCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.groups
          : widget.groups.where((g) => g.toUpperCase().contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return SizedBox(
      height: screenH * 0.7,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Учебная группа',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Поиск...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('Группа не найдена',
                        style: TextStyle(color: Color(0xFF757575))),
                  )
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final group = _filtered[i];
                      final isSelected = group == widget.current;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? const Color(0xFFD4765B)
                              : Theme.of(context).scaffoldBackgroundColor,
                          child: Text(
                            group.split('-').first,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF757575),
                            ),
                          ),
                        ),
                        title: Text(
                          group,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                                color: Color(0xFFD4765B))
                            : null,
                        onTap: () => Navigator.pop(context, group),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Нередактируемое поле (читаемое значение) ─────────────────────────────────

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final subtleColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFD4765B), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 11, color: subtleColor)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Icon(Icons.lock_outline, color: subtleColor, size: 16),
        ],
      ),
    );
  }
}

// ─── Выбор роли при регистрации ────────────────────────────────────────────────

class _AuthRoleSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _AuthRoleSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AuthRoleChip(
          label: 'Студент',
          icon: Icons.person_outline,
          selected: value == 'student',
          onTap: () => onChanged('student'),
        ),
        const SizedBox(width: 8),
        _AuthRoleChip(
          label: 'Преподаватель',
          icon: Icons.school,
          selected: value == 'teacher',
          onTap: () => onChanged('teacher'),
        ),
      ],
    );
  }
}

class _AuthRoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AuthRoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,

        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFD4765B)
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFFD4765B)
                  : Theme.of(context).dividerColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18,
                  color: selected ? Colors.white : const Color(0xFF757575)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF757575),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

