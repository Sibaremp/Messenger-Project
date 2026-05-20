import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppLocalizations — ручная реализация без кодогенерации.
//
// Использование в виджетах:
//   final l = context.l10n;
//   Text(l.send)
// ─────────────────────────────────────────────────────────────────────────────

class AppLocalizations {
  final String languageCode;
  const AppLocalizations(this.languageCode);

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations('ru');

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  // ── Выбор строки по языку ──────────────────────────────────────────────────
  String _t(String ru, String en, String kk) {
    switch (languageCode) {
      case 'en': return en;
      case 'kk': return kk;
      default:   return ru;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ОБЩИЕ
  // ══════════════════════════════════════════════════════════════════════════

  String get ok          => _t('OK',        'OK',       'ОК');
  String get cancel      => _t('Отмена',    'Cancel',   'Болдырмау');
  String get save        => _t('Сохранить', 'Save',     'Сақтау');
  String get delete      => _t('Удалить',   'Delete',   'Жою');
  String get edit        => _t('Редактировать', 'Edit', 'Өңдеу');
  String get close       => _t('Закрыть',   'Close',    'Жабу');
  String get open        => _t('Открыть',   'Open',     'Ашу');
  String get search      => _t('Поиск',     'Search',   'Іздеу');
  String get back        => _t('Назад',     'Back',     'Артқа');
  String get next        => _t('Далее',     'Next',     'Алға');
  String get create      => _t('Создать',   'Create',   'Жасау');
  String get add         => _t('Добавить',  'Add',      'Қосу');
  String get yes         => _t('Да',        'Yes',      'Иә');
  String get no          => _t('Нет',       'No',       'Жоқ');
  String get send        => _t('Отправить', 'Send',     'Жіберу');
  String get copy        => _t('Копировать','Copy',     'Көшіру');
  String get share       => _t('Поделиться','Share',    'Бөлісу');
  String get reply       => _t('Ответить',  'Reply',    'Жауап беру');
  String get forward     => _t('Переслать', 'Forward',  'Қайта жіберу');
  String get pin         => _t('Закрепить', 'Pin',      'Бекіту');
  String get unpin       => _t('Открепить', 'Unpin',    'Бекітуді алу');
  String get select      => _t('Выделить',  'Select',   'Белгілеу');
  String get retry       => _t('Повторить', 'Retry',    'Қайталау');
  String get loading     => _t('Загрузка…', 'Loading…', 'Жүктелуде…');
  String get error       => _t('Ошибка',    'Error',    'Қате');
  String get settings    => _t('Настройки', 'Settings', 'Параметрлер');
  String get profile     => _t('Профиль',   'Profile',  'Профиль');
  String get logout      => _t('Выйти из аккаунта', 'Log out', 'Шығу');
  String get online      => _t('в сети',    'online',   'желіде');
  String get you         => _t('Вы',        'You',      'Сіз');
  String get empty       => _t('Пусто',     'Empty',    'Бос');
  String get confirm     => _t('Подтвердить','Confirm', 'Растау');
  String get apply       => _t('Применить', 'Apply',    'Қолдану');
  String get saveAs      => _t('Сохранить как…', 'Save as…', 'Басқаша сақтау…');
  String get saveToCaspian => _t('Сохранить', 'Save',   'Сақтау');
  String get saveToCaspianSub => _t('В папку CaspianMessenger', 'To CaspianMessenger folder', 'CaspianMessenger қалтасына');
  String get saveAsManual => _t('Сохранить как…', 'Save as…', 'Басқаша сақтау…');
  String get saveAsManualSub => _t('Выбрать папку вручную', 'Choose folder manually', 'Қалтаны қолмен таңдау');
  String get savedToCaspian  => _t('Сохранено в папку CaspianMessenger', 'Saved to CaspianMessenger folder', 'CaspianMessenger қалтасына сақталды');
  String saveError(String e) => _t('Ошибка сохранения: $e', 'Save error: $e', 'Сақтау қатесі: $e');
  String get openInApp   => _t('Открыть в программе…', 'Open with…', 'Бағдарламада ашу…');
  String get removeFromDevice => _t('Удалить с устройства', 'Remove from device', 'Құрылғыдан жою');
  String get attachment  => _t('Вложение', 'Attachment', 'Тіркеме');
  String get photo       => _t('Фото',    'Photo',    'Фото');
  String get video       => _t('Видео',   'Video',    'Бейне');
  String get document    => _t('Документ','Document', 'Құжат');
  String get audio       => _t('Аудио',   'Audio',    'Аудио');
  String get voiceMsg    => _t('Голосовое сообщение', 'Voice message', 'Дауыстық хабар');
  String get file        => _t('Файл',    'File',     'Файл');
  String get poll        => _t('Опрос',   'Poll',     'Сауалнама');
  String get gif         => _t('GIF',     'GIF',      'GIF');
  String get camera      => _t('Камера',  'Camera',   'Камера');

  // ══════════════════════════════════════════════════════════════════════════
  // АВТОРИЗАЦИЯ
  // ══════════════════════════════════════════════════════════════════════════

  String get signIn          => _t('Войти',              'Sign in',       'Кіру');
  String get register        => _t('Зарегистрироваться', 'Register',      'Тіркелу');
  String get loginTitle      => _t('Вход',               'Sign in',       'Кіру');
  String get registerTitle   => _t('Регистрация',        'Registration',  'Тіркелу');
  String get loginSubtitle   => _t('Войдите или создайте аккаунт', 'Sign in or create an account', 'Кіріңіз немесе аккаунт жасаңыз');
  String get username        => _t('Имя пользователя',  'Username',      'Пайдаланушы аты');
  String get enterUsername   => _t('Введите имя',        'Enter username','Аты енгізіңіз');
  String get password        => _t('Пароль',             'Password',      'Құпиясөз');
  String get confirmPassword => _t('Подтвердите пароль', 'Confirm password', 'Құпиясөзді растаңыз');
  String get passwordsMismatch => _t('Пароли не совпадают', 'Passwords do not match', 'Құпиясөздер сәйкес келмейді');
  String get minPassword     => _t('Минимум 6 символов', 'Minimum 6 characters', 'Кемінде 6 таңба');
  String get phone           => _t('Номер телефона',     'Phone number',  'Телефон нөмірі');
  String get phoneHint       => _t('+7 (999) 000-00-00', '+7 (999) 000-00-00', '+7 (999) 000-00-00');
  String get fillFromSim     => _t('Нажмите SIM для заполнения', 'Tap SIM to fill', 'Толтыру үшін SIM басыңыз');
  String get selectSim       => _t('Выберите SIM-карту', 'Select SIM card', 'SIM-картаны таңдаңыз');
  String get unknownNumber   => _t('номер неизвестен',   'unknown number', 'нөмір белгісіз');
  String get whoAreYou       => _t('Кто вы?',            'Who are you?',  'Сіз кімсіз?');
  String get selectRole      => _t('Выберите вашу роль в учебном заведении', 'Select your role at the institution', 'Оқу орнындағы рөліңізді таңдаңыз');
  String get student         => _t('Студент',            'Student',       'Студент');
  String get teacher         => _t('Преподаватель',      'Teacher',       'Оқытушы');
  String get academicGroup   => _t('Учебная группа',     'Study group',   'Оқу тобы');
  String get selectGroup     => _t('Выберите группу, в которой вы учитесь', 'Select your study group', 'Оқу тобыңызды таңдаңыз');
  String get findYourself    => _t('Найдите себя',       'Find yourself', 'Өзіңізді табыңыз');
  String get selectFullName  => _t('Выберите ваше ФИО из списка', 'Select your full name from the list', 'Тізімнен аты-жөніңізді таңдаңыз');
  String get searchByName    => _t('Поиск по ФИО…',     'Search by name…','Аты-жөн бойынша іздеу…');
  String get loginCredentials => _t('Данные для входа', 'Login credentials', 'Кіру деректері');
  String get createLoginPwd  => _t('Придумайте логин и пароль', 'Create login and password', 'Логин мен құпиясөз ойлап табыңыз');
  String get name            => _t('Имя',                'Name',          'Аты');
  String get loginField      => _t('Логин',              'Login',         'Логин');
  String get noData          => _t('Нет данных',         'No data',       'Деректер жоқ');
  String get noneFound       => _t('Никого не найдено',  'Nobody found',  'Ешкім табылмады');
  String get noTeachers      => _t('Нет преподавателей', 'No teachers',   'Оқытушылар жоқ');
  String get noStudents      => _t('Нет студентов',      'No students',   'Студенттер жоқ');
  String get accountCreated  => _t('Аккаунт создан! Теперь войдите.', 'Account created! Now sign in.', 'Аккаунт жасалды! Енді кіріңіз.');
  String get connectionError => _t('Ошибка подключения к серверу', 'Server connection error', 'Серверге қосылу қатесі');
  String get loadingGroups   => _t('Загрузка групп…',   'Loading groups…','Топтар жүктелуде…');
  String get selectEduGroup  => _t('Выберите учебную группу', 'Select study group', 'Оқу тобын таңдаңыз');
  String get groupNotFound   => _t('Группа не найдена', 'Group not found', 'Топ табылмады');
  String get searchGroups    => _t('Поиск…',            'Search…',        'Іздеу…');
  String get groupsLoadError => _t('Не удалось загрузить группы. Проверьте подключение.', 'Failed to load groups. Check connection.', 'Топтарды жүктеу мүмкін болмады. Байланысты тексеріңіз.');
  String get peopleLoadError => _t('Ошибка загрузки',  'Load error',     'Жүктеу қатесі');
  String get termsCheckbox   => _t('Пользовательское соглашение', 'Terms of service', 'Пайдаланушы келісімі');
  String get privacyCheckbox => _t('Политику конфиденциальности', 'Privacy policy', 'Құпиялылық саясаты');
  String get acceptTerms     => _t('Необходимо принять пользовательское соглашение и политику конфиденциальности', 'Please accept the terms of service and privacy policy', 'Пайдаланушы келісімі мен құпиялылық саясатын қабылдаңыз');
  String get enterLogin      => _t('Введите логин',        'Enter login',        'Логинді енгізіңіз');
  String get enterPassword   => _t('Введите пароль',       'Enter password',     'Құпиясөзді енгізіңіз');
  String get fillFromSimBtn  => _t('Заполнить из SIM-карты', 'Fill from SIM card', 'SIM-картадан толтыру');
  String get showCarrier     => _t('Показать оператора',   'Show carrier',       'Операторды көрсету');
  String get invalidPhone    => _t('Некорректный номер',   'Invalid number',     'Қате нөмір');
  String get iAccept         => _t('Принимаю ',            'I accept ',          'Қабылдаймын ');
  String tapToRetry(String e) => _t('$e Нажмите, чтобы повторить.', '$e Tap to retry.', '$e Қайталау үшін басыңыз.');
  String get privacyTitle    => _t('Политика конфиденциальности', 'Privacy policy', 'Құпиялылық саясаты');

  // ══════════════════════════════════════════════════════════════════════════
  // НАВИГАЦИЯ / РАЗДЕЛЫ
  // ══════════════════════════════════════════════════════════════════════════

  String get chatSection        => _t('Общение',       'Chats',       'Байланыс');
  String get academicSection    => _t('Академический', 'Academic',    'Академиялық');
  String get notificationsTab   => _t('Уведомления',   'Notifications','Хабарландырулар');
  String get settingsTab        => _t('Настройки',     'Settings',    'Параметрлер');
  String get personalTab        => _t('Личные',        'Personal',    'Жеке');
  String get groupsTab          => _t('Группы',        'Groups',      'Топтар');
  String get newChat            => _t('Новый чат',     'New chat',    'Жаңа чат');
  String get createGroup        => _t('Создать группу','Create group','Топ жасау');
  String get createCommunity    => _t('Создать сообщество','Create community','Қоғамдастық жасау');
  String get createAcademicGroup    => _t('Создать академическую группу',   'Create academic group',     'Академиялық топ жасау');
  String get createAcademicCommunity=> _t('Создать академическое сообщество','Create academic community','Академиялық қоғамдастық жасау');
  String get noChats            => _t('Нет чатов',     'No chats',    'Чаттар жоқ');
  String get selectChat         => _t('Выберите чат',  'Select a chat','Чат таңдаңыз');
  String get searchPlaceholder  => _t('Поиск',         'Search',      'Іздеу');

  // ══════════════════════════════════════════════════════════════════════════
  // СПИСОК ЧАТОВ
  // ══════════════════════════════════════════════════════════════════════════

  String get pressEditToStart   => _t('Нажмите ✎ чтобы начать диалог', 'Tap ✎ to start a conversation', 'Сөйлесу үшін ✎ басыңыз');
  String get searchByNameOrNumber => _t('Поиск по имени или номеру…',  'Search by name or number…',    'Аты немесе нөмір бойынша іздеу…');
  String get noContactsFound    => _t('Контакты не найдены',            'No contacts found',             'Контактілер табылмады');
  String get loadingContacts    => _t('Загружаем контакты…',            'Loading contacts…',             'Контактілер жүктелуде…');
  String get noContactAccess    => _t('Нет доступа к контактам',        'No access to contacts',         'Контактілерге рұқсат жоқ');
  String get allowAccessDesc    => _t('Разрешите доступ в настройках, чтобы найти друзей по телефонной книге', 'Allow access in settings to find friends from your phonebook', 'Телефон кітабынан достарды табу үшін параметрлерде рұқсат беріңіз');
  String get deviceContacts     => _t('Контакты',          'Contacts',       'Контактілер');
  String get inAppContacts      => _t('В приложении',      'In app',         'Қолданбада');
  String get allContacts        => _t('КОНТАКТЫ',          'CONTACTS',       'КОНТАКТІЛЕР');
  String get appContactsLabel   => _t('В ПРИЛОЖЕНИИ',      'IN APP',         'ҚОЛДАНБАДА');
  String get openBtn            => _t('Открыть',           'Open',           'Ашу');
  String get markAllRead        => _t('Все прочитаны',     'All read',       'Барлығы оқылды');
  String get allNotif           => _t('Все',               'All',            'Барлығы');
  String get lastDay            => _t('За сутки',          'Last 24h',       'Соңғы 24 сағат');
  String get noNotifications    => _t('Нет уведомлений',   'No notifications','Хабарландырулар жоқ');
  String get mentionLabel       => _t('Упоминание',        'Mention',        'Атап өту');
  String get replyNotif         => _t('Ответ на сообщение','Reply',          'Хабарға жауап');
  String get readBtn            => _t('Прочитать',         'Read',           'Оқу');
  String get newGroup           => _t('Новая группа',      'New group',      'Жаңа топ');
  String get newCommunityTitle  => _t('Новое сообщество',  'New community',  'Жаңа қоғамдастық');
  String get chatNameLabel      => _t('Название',          'Name',           'Атауы');
  String get descriptionOpt     => _t('Описание (необязательно)', 'Description (optional)', 'Сипаттама (міндетті емес)');
  String get enterNameError     => _t('Введите название',  'Enter a name',   'Атауын енгізіңіз');
  String get participantLabel   => _t('Участник',          'Participant',    'Қатысушы');
  String get allCanWrite        => _t('Все участники могут писать',   'All members can write',   'Барлық мүшелер жаза алады');
  String get onlyAdminWrites    => _t('Только администратор пишет', 'Only admin can write',    'Тек әкімші жаза алады');
  String get onlyTeacherCanCreate => _t('Только преподаватель может создавать академические группы', 'Only a teacher can create academic groups', 'Академиялық топтарды тек оқытушы жасай алады');

  // ══════════════════════════════════════════════════════════════════════════
  // ЧАТ (сообщения, панель ввода, контекстное меню)
  // ══════════════════════════════════════════════════════════════════════════

  String get typeMessage        => _t('Написать сообщение…',  'Type a message…',  'Хабар жазу…');
  String get addCaption         => _t('Добавьте подпись…',    'Add a caption…',   'Қол қою қосыңыз…');
  String get captionHint        => _t('Подпись',              'Caption',          'Қол қою');
  String get editMessage        => _t('Редактировать',        'Edit',             'Өңдеу');
  String get deleteMessage      => _t('Удалить',              'Delete',           'Жою');
  String get replyMessage       => _t('Ответить',             'Reply',            'Жауап беру');
  String get forwardMessage     => _t('Переслать',            'Forward',          'Қайта жіберу');
  String get forwardTo          => _t('Переслать в…',         'Forward to…',      'Қайта жіберу…');
  String get copyMessage        => _t('Копировать',           'Copy',             'Көшіру');
  String get pinMessage         => _t('Закрепить',            'Pin',              'Бекіту');
  String get unpinMessage       => _t('Открепить',            'Unpin',            'Бекітуді алу');
  String get selectMessage      => _t('Выделить',             'Select',           'Белгілеу');
  String get saveToFolder       => _t('Сохранить',            'Save',             'Сақтау');
  String get saveToFolderSub    => _t('В папку CaspianMessenger','To CaspianMessenger','CaspianMessenger-ке');
  String get saveAsFolder       => _t('Сохранить как…',       'Save as…',         'Басқаша сақтау…');
  String get saveAsFolderSub    => _t('Выбрать папку вручную','Choose folder',    'Қалтаны таңдау');
  String get noChatsForForward  => _t('Нет других чатов для пересылки', 'No other chats to forward to', 'Қайта жіберуге басқа чаттар жоқ');
  String get alreadyMember      => _t('Вы уже участник этой группы', 'You are already a member', 'Сіз бұл топтың мүшесісіз');
  String get allAlreadyInGroup  => _t('Все контакты уже в этой группе', 'All contacts are already in this group', 'Барлық контактілер топта');
  String get inviteToGroup      => _t('Пригласить в группу', 'Invite to group',  'Топқа шақыру');
  String get postAsCommunity    => _t('От имени', 'As channel',                  'Арна атынан');
  String get postAsSelf         => _t('От своего имени', 'As myself',            'Өз атымдан');
  String get switchRole         => _t('Сменить',  'Switch',                      'Ауыстыру');
  String get mentionAll         => _t('Упомянуть всех', 'Mention everyone',       'Барлығын атап өту');
  String get msgCensored        => _t('Сообщение содержало недопустимые слова и было автоматически отредактировано.', 'Message contained prohibited words and was automatically edited.', 'Хабарда тыйым салынған сөздер болды және автоматты түрде өңделді.');
  String get audioCallTooltip   => _t('Аудио звонок',  'Audio call',  'Аудио қоңырау');
  String get videoCallTooltip   => _t('Видео звонок',  'Video call',  'Бейне қоңырау');
  String get forwardTooltip     => _t('Переслать',      'Forward',     'Қайта жіберу');
  String get deleteTooltip      => _t('Удалить',        'Delete',      'Жою');
  String get sendPhotoTitle     => _t('Отправить фото', 'Send photo',  'Фото жіберу');
  String get sendVideoTitle     => _t('Отправить видео','Send video',  'Бейне жіберу');
  String get sendAsFiles        => _t('Отправить как файлы', 'Send as files', 'Файлдар ретінде жіберу');
  String get addMore            => _t('Добавить',       'Add',         'Қосу');
  String get photoOrVideo       => _t('Фото или видео', 'Photo or video','Фото немесе бейне');
  String get createPoll         => _t('Создать опрос',  'Create poll', 'Сауалнама жасау');
  String get pollQuestion       => _t('Введите вопрос…','Enter question…','Сұрақ енгізіңіз…');
  String get pollOptions        => _t('Варианты ответа','Answer options','Жауап нұсқалары');
  String get pollSettings       => _t('Настройки',      'Settings',    'Параметрлер');
  String get pollMultiple       => _t('Множественный выбор','Multiple choice','Бірнеше таңдау');
  String get pollAnonymous      => _t('Анонимный опрос','Anonymous poll','Анонимді сауалнама');
  String get pollChangeVote     => _t('Разрешить изменить голос','Allow vote change','Дауысты өзгертуге рұқсат беру');
  String get pollNoLimit        => _t('Без ограничения по времени','No time limit','Уақыт шектеусіз');
  String get pollEnterQuestion  => _t('Введите вопрос', 'Enter question','Сұрақ енгізіңіз');
  String get addAnswerOption    => _t('Добавить вариант','Add option',  'Нұсқа қосу');

  // ══════════════════════════════════════════════════════════════════════════
  // ВЛОЖЕНИЯ (документы, медиа)
  // ══════════════════════════════════════════════════════════════════════════

  String get openInProgram      => _t('Открыть в программе…','Open with…','Бағдарламада ашу…');
  String get removeLocal        => _t('Удалить с устройства','Remove from device','Құрылғыдан жою');
  String savedFile(String n) => _t('Сохранено: $n',    'Saved: $n',   'Сақталды: $n');
  String saveFileError(String e) => _t('Ошибка сохранения: $e','Save error: $e','Сақтау қатесі: $e');

  // ══════════════════════════════════════════════════════════════════════════
  // ПОИСК
  // ══════════════════════════════════════════════════════════════════════════

  String get searchChatsMessagesFiles => _t('Поиск чатов, сообщений, файлов…','Search chats, messages, files…','Чаттар, хабарлар, файлдар…');
  String get searchChatsTab     => _t('Чаты',      'Chats',    'Чаттар');
  String get searchMessagesTab  => _t('Сообщения', 'Messages', 'Хабарлар');
  String get searchFilesTab     => _t('Файлы',     'Files',    'Файлдар');
  String get enterQuery         => _t('Введите запрос для поиска',    'Enter a search query',    'Іздеу сұрауын енгізіңіз');
  String get searchHint         => _t('Ищите чаты, сообщения или файлы','Search chats, messages or files','Чаттар, хабарлар немесе файлдарды іздеңіз');
  String get chatsNotFound      => _t('Чаты не найдены',    'No chats found',    'Чаттар табылмады');
  String get messagesNotFound   => _t('Сообщения не найдены','No messages found','Хабарлар табылмады');
  String get filesNotFound      => _t('Файлы не найдены',   'No files found',    'Файлдар табылмады');
  String get directChat         => _t('Личный чат',         'Direct message',    'Жеке чат');
  String get allFiles           => _t('Все',    'All',     'Барлығы');
  String get imageFiles         => _t('Фото',   'Photos',  'Фото');
  String get videoFiles         => _t('Видео',  'Videos',  'Бейне');
  String get documentFiles      => _t('Документы','Documents','Құжаттар');

  // Вкладки с числом результатов
  String searchTabChats(int n)     => _t('Чаты ($n)',      'Chats ($n)',    'Чаттар ($n)');
  String searchTabMessages(int n)  => _t('Сообщения ($n)', 'Messages ($n)', 'Хабарлар ($n)');
  String searchTabFiles(int n)     => _t('Файлы ($n)',     'Files ($n)',    'Файлдар ($n)');

  // Тип чата (с числом участников)
  String chatTypeGroup(int n)      => _t('Группа • $n участников',     'Group • $n members',     'Топ • $n мүше');
  String chatTypeCommunity(int n)  => _t('Сообщество • $n подписчиков','Community • $n members',  'Қоғамдастық • $n мүше');

  // Академический значок
  String get academicShort         => _t('Акад.',  'Acad.',  'Акад.');

  // ══════════════════════════════════════════════════════════════════════════
  // ЗВОНКИ
  // ══════════════════════════════════════════════════════════════════════════

  String get outgoing           => _t('Исходящий…',    'Calling…',      'Шығыс…');
  String get connecting         => _t('Подключение…',  'Connecting…',   'Қосылуда…');
  String get callEnded          => _t('Звонок завершён','Call ended',    'Қоңырау аяқталды');
  String get noConnection       => _t('Нет соединения', 'No connection', 'Байланыс жоқ');
  String get groupCall          => _t('Групповой звонок','Group call',   'Топтық қоңырау');
  String get adminOnlySpeak     => _t('В сообществе говорить могут только администраторы','Only admins can speak in communities','Қоғамдастықта тек әкімшілер сөйлей алады');
  String get listenOnly         => _t('Только прослушивание','Listen only', 'Тек тыңдау');
  String get muteMic            => _t('Выкл. мик.',    'Mute',          'Микрофонды өшіру');
  String get unmuteMic          => _t('Вкл. мик.',     'Unmute',        'Микрофонды қосу');
  String get cameraOff          => _t('Выкл. камеру',  'Camera off',    'Камераны өшіру');
  String get cameraOn           => _t('Вкл. камеру',   'Camera on',     'Камераны қосу');
  String get flipCamera         => _t('Перевернуть',   'Flip',          'Айналдыру');
  String get endCall            => _t('Завершить',      'End',           'Аяқтау');
  String get speakerOn          => _t('Динамик вкл.',  'Speaker on',    'Динамик қосулы');
  String get speakerOff         => _t('Динамик выкл.', 'Speaker off',   'Динамик өшірулі');
  String get selectAudioOutput  => _t('Аудиовыход',    'Audio output',  'Дыбыс шығысы');
  String get endCallToExit      => _t('Нажмите «Завершить» для выхода из звонка',
                                      'Press "End" to leave the call',
                                      'Қоңыраудан шығу үшін «Аяқтау» басыңыз');
  String get ongoingGroupCall   => _t('Идёт групповой звонок', 'Ongoing group call', 'Топтық қоңырау жүріп жатыр');
  String get joinCall           => _t('Присоединиться', 'Join', 'Қосылу');
  String get incomingAudioCall  => _t('Входящий аудиозвонок','Incoming audio call','Кіріс аудио қоңырау');
  String get incomingVideoCall  => _t('Входящий видеозвонок','Incoming video call','Кіріс бейне қоңырау');
  String get groupVideoCall     => _t('Групповой видеозвонок','Group video call','Топтық бейне қоңырау');
  String get groupAudioCall     => _t('Групповой аудиозвонок','Group audio call','Топтық аудио қоңырау');
  String get accept             => _t('Принять',  'Accept',  'Қабылдау');
  String get declineCall        => _t('Отклонить','Decline', 'Бас тарту');
  String get cantCallNoChat     => _t('Откройте личный чат для звонка','Open a direct chat to call','Қоңырау шалу үшін жеке чат ашыңыз');

  // ══════════════════════════════════════════════════════════════════════════
  // ПРОФИЛЬ / РЕДАКТИРОВАНИЕ
  // ══════════════════════════════════════════════════════════════════════════

  String get editProfile        => _t('Редактировать профиль','Edit profile','Профильді өңдеу');
  String get personalData       => _t('Личные данные',   'Personal data', 'Жеке деректер');
  String get nameLabel          => _t('Имя',             'Name',          'Аты');
  String get loginLabel         => _t('Логин',           'Login',         'Логин');
  String get roleLabel          => _t('Роль',            'Role',          'Рөл');
  String get phoneLabel         => _t('Телефон',         'Phone',         'Телефон');
  String get aboutLabel         => _t('О себе',          'About',         'Өзім туралы');
  String get aboutHint          => _t('Расскажите немного о себе…','Tell a bit about yourself…','Өзіңіз туралы аздап айтып беріңіз…');
  String get searchGroupHint    => _t('Поиск группы…',  'Search group…', 'Топ іздеу…');
  String get notSelected        => _t('Не выбрана',     'Not selected',  'Таңдалмаған');
  String get takePhoto          => _t('Сделать фото',   'Take photo',    'Фото түсіру');
  String get chooseGallery      => _t('Выбрать из галереи','Choose from gallery','Галереядан таңдау');
  String get chooseGif          => _t('Выбрать GIF',    'Choose GIF',    'GIF таңдау');
  String get deletePhoto        => _t('Удалить фото',   'Delete photo',  'Фотоны жою');
  String get nameEmpty          => _t('Имя не может быть пустым','Name cannot be empty','Аты бос болмауы керек');
  String avatarUploadError(String e) => _t('Не удалось загрузить аватар: $e','Failed to upload avatar: $e','Аватарды жүктеу мүмкін болмады: $e');
  String get savedMsg           => _t('Сохранено',      'Saved',         'Сақталды');
  String get changeLogin        => _t('Сменить логин',  'Change login',  'Логинді өзгерту');
  String get newLoginLabel      => _t('Новый логин',    'New login',     'Жаңа логин');
  String get currentPassword    => _t('Текущий пароль', 'Current password','Ағымдағы құпиясөз');
  String get loginChanged       => _t('Логин изменён',  'Login changed', 'Логин өзгертілді');
  String get inSelfProfile      => _t('в сети',         'online',        'желіде');

  // ══════════════════════════════════════════════════════════════════════════
  // ГРУППА / СООБЩЕСТВО (профиль)
  // ══════════════════════════════════════════════════════════════════════════

  String get groupType          => _t('Группа',             'Group',       'Топ');
  String get communityType      => _t('Сообщество',         'Community',   'Қоғамдастық');
  String get subscribersLabel   => _t('Подписчики',         'Subscribers', 'Жазылушылар');
  String get membersLabel       => _t('Участники',          'Members',     'Мүшелер');
  String get descriptionLabel   => _t('Описание',           'Description', 'Сипаттама');
  String get typeLabel          => _t('Тип',                'Type',        'Түрі');
  String get createdLabel       => _t('Создан',             'Created',     'Жасалған');
  String get deleteGroup        => _t('Удалить группу',     'Delete group','Топты жою');
  String get deleteCommunity    => _t('Удалить сообщество', 'Delete community','Қоғамдастықты жою');
  String get removeMemberTitle  => _t('Удалить участника?', 'Remove member?','Мүшені шығару?');
  String removeMemberDesc(String n) => _t('«$n» будет исключён из чата.','«$n» will be removed from the chat.','«$n» чаттан шығарылады.');
  String get makeAdmin          => _t('Назначить администратором','Make admin','Әкімші ету');
  String get removeAdmin        => _t('Снять роль администратора','Remove admin','Әкімші рөлін алу');
  String get changePhoto        => _t('Изменить фото',      'Change photo','Фотоны өзгерту');
  String get creatorRole        => _t('Создатель',          'Creator',     'Жасаушы');
  String get adminRole          => _t('Админ',              'Admin',       'Әкімші');
  String blockUserTitle(String n) => _t('Заблокировать $n?','Block $n?','$n блоктау?');
  String get blockUserDesc      => _t('Пользователь не сможет отправлять вам сообщения.','The user will not be able to send you messages.','Пайдаланушы сізге хабар жібере алмайды.');
  String get blockBtn           => _t('Заблокировать','Block','Блоктау');
  String get callBtn            => _t('Звонок', 'Call',  'Қоңырау');
  String get chatBtn            => _t('Чат',    'Chat',  'Чат');
  String get notifLabel         => _t('Уведомления',     'Notifications','Хабарландырулар');
  String get soundOn            => _t('Звук',            'Sound on',     'Дыбыс қосулы');
  String get soundOff           => _t('Включить',        'Enable',       'Қосу');
  String get offlineStatus      => _t('последний раз недавно','last seen recently','жақында онлайн болды');

  // ══════════════════════════════════════════════════════════════════════════
  // НАСТРОЙКИ
  // ══════════════════════════════════════════════════════════════════════════

  String get settingsTitle         => _t('Настройки',               'Settings',             'Параметрлер');
  String get notifAndSounds        => _t('Уведомления и звуки',     'Notifications & sounds','Хабарландырулар мен дыбыстар');
  String get activeSessions        => _t('Активные сеансы',         'Active sessions',      'Белсенді сеанстар');
  String get activeSessionsSub     => _t('Устройства с активной сессией','Devices with active sessions','Белсенді сессиясы бар құрылғылар');
  String get appearance            => _t('Оформление',              'Appearance',           'Безендіру');
  String get appearanceSub         => _t('Тема, цвета, шрифт',      'Theme, colors, font',  'Тема, түстер, қаріп');
  String get dataAndStorage        => _t('Данные и хранилище',      'Data & storage',       'Деректер мен жад');
  String get dataAndStorageSub     => _t('Кэш, медиафайлы',         'Cache, media',         'Кэш, медиафайлдар');
  String get soundAndCamera        => _t('Звук и камера',           'Sound & camera',       'Дыбыс және камера');
  String get soundAndCameraSub     => _t('Микрофон, динамик, камера','Mic, speaker, camera', 'Микрофон, динамик, камера');
  String get languageTitle         => _t('Язык',                    'Language',             'Тіл');
  String get languageSub           => _t('Русский',                 'English',              'Қазақша');
  String get logoutTitle           => _t('Выйти из аккаунта',       'Log out',              'Шығу');
  String get logoutConfirm         => _t('Выход',                   'Log out',              'Шығу');
  String get logoutQuestion        => _t('Вы уверены, что хотите выйти из аккаунта?','Are you sure you want to log out?','Аккаунтан шығуды қалайсыз ба?');
  String get logoutBtn             => _t('Выйти',                   'Log out',              'Шығу');
  String get textScaleLabel        => _t('Масштаб',                 'Scale',                'Масштаб');
  String get textSizeLabel         => _t('Размер текста',           'Text size',            'Мәтін өлшемі');

  // Уведомления
  String get notifSoundLabel       => _t('Звук уведомлений',       'Notification sound',    'Хабарландыру дыбысы');
  String get vibrationLabel        => _t('Вибрация',               'Vibration',             'Дірілдету');
  String get previewLabel          => _t('Предпросмотр сообщений', 'Message preview',       'Хабарды алдын ала қарау');
  String get previewSub            => _t('Показывать текст в уведомлении','Show text in notification','Хабарландырудағы мәтінді көрсету');
  String get categoriesLabel       => _t('Категории',              'Categories',            'Санаттар');
  String get directChatsLabel      => _t('Личные чаты',            'Direct chats',          'Жеке чаттар');
  String get groupsLabel           => _t('Группы',                 'Groups',                'Топтар');
  String get communitiesLabel      => _t('Сообщества',             'Communities',           'Қоғамдастықтар');
  String get newsLabel             => _t('Новости (от администратора)','News (from admin)', 'Жаңалықтар (әкімшіден)');
  String get callsLabel            => _t('Звонки',                 'Calls',                 'Қоңыраулар');
  String get acceptCallsLabel      => _t('Принимать звонки',       'Accept calls',          'Қоңырауларды қабылдау');
  String get acceptCallsSub        => _t('Показывать входящие звонки на устройстве','Show incoming calls on device','Құрылғыда кіріс қоңырауларды көрсету');

  // Оформление (тема)
  String get themeLabel            => _t('Тема',            'Theme',          'Тема');
  String get lightTheme            => _t('Светлая',         'Light',          'Ашық');
  String get darkTheme             => _t('Тёмная',          'Dark',           'Күңгірт');
  String get autoTheme             => _t('Авто',            'Auto',           'Авто');
  String get autoDayNight          => _t('Авто день/ночь',  'Auto day/night', 'Авто күн/түн');
  String get lightFrom             => _t('Светлая с',       'Light from',     'Ашық бастап');
  String get darkFrom              => _t('Тёмная с',        'Dark from',      'Күңгірт бастап');
  String get primaryColorLabel     => _t('Основной цвет',   'Primary color',  'Негізгі түс');
  String get chatColorsLabel       => _t('Цвета чата',      'Chat colors',    'Чат түстері');
  String get chatBg                => _t('Фон чата',        'Chat background','Чат фоны');
  String get myMessages            => _t('Мои сообщения',   'My messages',    'Менің хабарларым');
  String get theirMessages         => _t('Сообщения собеседника','Their messages','Серіктестің хабарлары');
  String get sendButton            => _t('Кнопка отправки / записи','Send/record button','Жіберу/жазу түймесі');
  String get chatWallpaper         => _t('Обои чата',       'Chat wallpaper', 'Чат тұсқағазы');
  String get fontLabel             => _t('Шрифт',           'Font',           'Қаріп');
  String get saveTheme             => _t('Сохранить тему',  'Save theme',     'Тақырыпты сақтау');
  String get themeNameHint         => _t('Название темы',   'Theme name',     'Тақырып атауы');
  String get colorPickerTitle      => _t('Выбор цвета',     'Color picker',   'Түс таңдау');
  String get permissionBlocked     => _t('Разрешение заблокировано','Permission blocked','Рұқсат бұғатталды');
  String get openAppSettings       => _t('Откройте настройки приложения, чтобы включить его.','Open app settings to enable it.','Қосу үшін қолданба параметрлерін ашыңыз.');
  String get openSettingsBtn       => _t('Настройки',       'Settings',       'Параметрлер');
  String get generalSection        => _t('Общие',           'General',        'Жалпы');

  // Данные и хранилище
  String get usageSection          => _t('Использование',   'Usage',          'Пайдалану');
  String get tempCache             => _t('Временный кэш',   'Temporary cache','Уақытша кэш');
  String get savedFiles            => _t('Сохранённые файлы','Saved files',   'Сақталған файлдар');
  String savedFilesSub(String s) => _t('$s • папка CaspianMessenger','$s • CaspianMessenger folder','$s • CaspianMessenger қалтасы');
  String get clearBtn              => _t('Очистить',        'Clear',          'Тазалау');
  String get cacheCleared          => _t('Временный кэш очищен','Cache cleared','Уақытша кэш тазаланды');
  String get deleteSavedTitle      => _t('Удалить сохранённые файлы?','Delete saved files?','Сақталған файлдарды жою?');
  String get deleteSavedDesc       => _t('Все файлы из папки CaspianMessenger будут удалены. Отменить это действие невозможно.','All files in CaspianMessenger folder will be deleted. This cannot be undone.','CaspianMessenger қалтасындағы барлық файлдар жойылады. Бұл әрекетті болдырмау мүмкін емес.');
  String get savedFilesCleared     => _t('Сохранённые файлы удалены','Saved files deleted','Сақталған файлдар жойылды');
  String get dataLimitSection      => _t('Лимит данных',    'Data limit',     'Деректер лимиті');
  String dataLimitMax(int mb)  => _t('Максимум: $mb МБ','Maximum: $mb MB','Максимум: $mb МБ');

  // Звук и камера
  String get microphoneLabel       => _t('Микрофон',          'Microphone',  'Микрофон');
  String get speakerLabel          => _t('Динамик / наушники','Speaker / headphones','Динамик / құлаққап');
  String get cameraLabel           => _t('Камера',            'Camera',      'Камера');
  String get micCamPermission      => _t('Разрешите доступ к микрофону и камере в системных настройках','Allow microphone and camera access in system settings','Жүйе параметрлерінде микрофон мен камераға рұқсат беріңіз');

  // Активные сеансы
  String get serviceUnavailable    => _t('Сервис недоступен', 'Service unavailable','Қызмет қолжетімді емес');

  // SIM-карта
  String get simCardNotFound       => _t('SIM-карта не найдена',                'SIM card not found',                   'SIM-карта табылмады');
  String get simPermissionDenied   => _t('Нет разрешения на чтение SIM-карты',  'No SIM read permission',               'SIM-картаны оқуға рұқсат жоқ');
  String get simUnsupported        => _t('Устройство не поддерживает чтение SIM','Device does not support SIM reading',  'Құрылғы SIM оқуды қолдамайды');
  String get simReadError          => _t('Ошибка чтения SIM',                   'SIM read error',                       'SIM оқу қатесі');
  String simNumberUnavailable(String info) => _t('Номер недоступен ($info). На iOS Apple скрывает номер.', 'Number unavailable ($info). iOS hides the number.', 'Нөмір қолжетімді емес ($info). iOS нөмірді жасырады.');
  String get simPermissionBlockedDesc => _t('Разрешение на чтение SIM-карты было отклонено. Откройте настройки приложения, чтобы включить его.', 'SIM read permission was denied. Open app settings to enable it.', 'SIM оқу рұқсаты қабылданбады. Қосу үшін қолданба параметрлерін ашыңыз.');
  String get insertFromSim         => _t('Вставить номер из SIM-карты',          'Fill from SIM card',                   'SIM-картадан нөмір алу');

  // Тема / обои
  String get wallpaperPick         => _t('Выбрать изображение / GIF', 'Choose image / GIF', 'Сурет / GIF таңдау');
  String profileSaveError(String e) => _t('Ошибка: $e', 'Error: $e', 'Қате: $e');

  // Язык
  String get languageRu            => _t('Русский',   'Russian',  'Орысша');
  String get languageEn            => _t('English',   'English',  'Ағылшынша');
  String get languageKk            => _t('Қазақша',   'Kazakh',   'Қазақша');

  // ══════════════════════════════════════════════════════════════════════════
  // КОНТАКТЫ / DESKTOP
  // ══════════════════════════════════════════════════════════════════════════

  String get teachersTitle      => _t('Преподаватели', 'Teachers',       'Оқытушылар');
  String get teachersSearch     => _t('Поиск преподавателей…','Search teachers…','Оқытушы іздеу…');
  String get studentsSearch     => _t('Поиск контактов…',    'Search contacts…', 'Контакт іздеу…');
  String get nothingFound       => _t('Ничего не найдено',   'Nothing found',    'Ештеңе табылмады');
  String get openContact        => _t('Открыть',             'Open',             'Ашу');
  String get newChatDesktop     => _t('Новый чат',           'New chat',         'Жаңа чат');
  String get newGroupDesktop    => _t('Создать группу',      'Create group',     'Топ жасау');
  String get newAcademicGroup   => _t('Создать академическую группу',    'Create academic group',     'Академиялық топ жасау');
  String get newAcademicComm    => _t('Создать академическое сообщество','Create academic community', 'Академиялық қоғамдастық жасау');

  // ── ЧАТЫ — ошибки и динамические сообщения ────────────────────────────────
  String sendError(String e)         => _t('Ошибка отправки: $e',             'Send error: $e',                'Жіберу қатесі: $e');
  String saveChangesError(String e)  => _t('Не удалось сохранить изменения: $e','Could not save changes: $e',  'Өзгерістерді сақтау мүмкін болмады: $e');
  String deleteError(String e)       => _t('Ошибка удаления: $e',             'Delete error: $e',              'Жою қатесі: $e');
  String gifSendError(String e)      => _t('Ошибка отправки GIF: $e',         'GIF send error: $e',            'GIF жіберу қатесі: $e');
  String openChatError(String e)     => _t('Не удалось открыть чат: $e',      'Could not open chat: $e',       'Чатты ашу мүмкін болмады: $e');
  String joinError(String e)         => _t('Не удалось вступить: $e',         'Could not join: $e',            'Қосылу мүмкін болмады: $e');
  String forwardedTo(String name)    => _t('Переслано в «$name»',             'Forwarded to "$name"',          '«$name» топқа қайта жіберілді');
  String joinedGroup(String name)    => _t('Вы вступили в «$name»',          'You joined "$name"',            '«$name» топқа қосылдыңыз');
  String inviteSent(int n)           => _t('Приглашение отправлено $n получателям','Invitation sent to $n recipients','$n адамға шақыру жіберілді');
  String inviteSentReport(int sent, int failed) => _t('Отправлено: $sent, ошибок: $failed','Sent: $sent, errors: $failed','Жіберілді: $sent, қате: $failed');
  String maxPinnedMsg(int n)         => _t('Можно закрепить не более $n сообщений','You can pin at most $n messages','Ең көбі $n хабар бекітуге болады');
  String memberCount(int n)          => _t('$n участников',                   '$n members',                    '$n мүше');
  String communitySubscribers(int n) => _t('Сообщество · $n подписчиков',    'Community · $n subscribers',    'Қоғамдастық · $n жазылушы');
  String selectedCount(int n)        => _t('Выбрано $n изображений',          '$n images selected',            '$n сурет таңдалды');
  String sendCount(int n)            => _t('Отправить ($n)',                  'Send ($n)',                     'Жіберу ($n)');
  String pollDeadlineUntil(String dt) => _t('До $dt',                         'Until $dt',                     '$dt дейін');
  String pollOptionLabel(int i)       => _t('Вариант $i',                     'Option $i',                     '$i нұсқасы');
  String get pollQuestionLabel       => _t('Вопрос *',                        'Question *',                    'Сұрақ *');
  String get addTwoOptions           => _t('Добавьте хотя бы 2 варианта',     'Add at least 2 options',        'Кемінде 2 нұсқа қосыңыз');
  String get mentionVisualOnly       => _t('Упоминание только визуальное (сервер не выдал ID)','Mention is visual only (server did not provide ID)','Атап өту тек визуалды (сервер ID бермеді)');
  String get pollVoteError           => _t('Ошибка голосования',              'Poll vote error',               'Дауыс беру қатесі');

  // ── Selection mode / AppBar ───────────────────────────────────────────────
  String selectedItems(int n)        => _t('$n выбрано',               '$n selected',               '$n таңдалды');
  // audioCallTooltip, videoCallTooltip defined earlier — reuse those

  // ── Channel input header ──────────────────────────────────────────────────
  String get postAsPrefix            => _t('От имени  ',               'As ',                       'Атынан  ');
  String get postAsMyself            => _t('От своего имени',          'As myself',                 'Өз атымнан');
  String get switchSender            => _t('Сменить',                  'Switch',                    'Ауыстыру');

  // ── Attach popup ──────────────────────────────────────────────────────────
  // camera, document, poll, photoOrVideo, inviteToGroup, mentionAll all defined earlier — reuse those

  // ── Poll dialog ───────────────────────────────────────────────────────────
  // createPoll, pollSettings, pollAnonymous defined earlier — reuse those
  String get createPollBtn           => _t('Создать',                  'Create',                    'Жасау');
  String get pollQuestionHint        => _t('Введите вопрос…',          'Enter question…',           'Сұрақты енгізіңіз…');
  String get pollAnswerOptions       => _t('Варианты ответа',          'Answer options',            'Жауап нұсқалары');
  String get pollAddOption           => _t('Добавить вариант',         'Add option',                'Нұсқа қосу');
  String get pollMultipleChoice      => _t('Множественный выбор',      'Multiple choice',           'Бірнеше таңдау');
  String get pollCanChangeVote       => _t('Разрешить изменить голос', 'Allow changing vote',       'Дауысты өзгертуге рұқсат беру');
  String get pollNoDeadline          => _t('Без ограничения по времени','No time limit',            'Уақыт шектеусіз');

  // ── Media preview ─────────────────────────────────────────────────────────
  // addCaption, captionHint, sendAsFiles, addMore defined earlier — reuse those
  String get sendPhoto               => _t('Отправить фото',           'Send photo',                'Фото жіберу');
  String get sendVideo               => _t('Отправить видео',          'Send video',                'Бейне жіберу');

  // ── Sidebar ───────────────────────────────────────────────────────────────
  String get sidebarExpand           => _t('Развернуть',               'Expand',                    'Жаю');
  String get sidebarCollapse         => _t('Свернуть',                 'Collapse',                  'Жинау');
  String get sidebarLogout           => _t('Выйти',                    'Log out',                   'Шығу');

  // ── Member picker ─────────────────────────────────────────────────────────
  String get addMembers              => _t('Добавить участников',      'Add members',               'Қатысушыларды қосу');
  String get searchByNameGroup       => _t('Поиск по ФИО или группе…', 'Search by name or group…',  'Аты немесе топ бойынша іздеу…');

  // ── Notifications panel ───────────────────────────────────────────────────
  String get notificationCenter      => _t('Центр уведомлений',        'Notification center',       'Хабарландыру орталығы');
  String get adminNotifSubtitle      => _t('Системные уведомления от администратора', 'System notifications from administrator', 'Администратордың жүйелік хабарламалары');
  String get failedToLoadNotif       => _t('Не удалось загрузить уведомления', 'Could not load notifications', 'Хабарландыруларды жүктеу мүмкін болмады');
  String get refresh                 => _t('Обновить',                 'Refresh',                   'Жаңарту');
  String get studentsLabel           => _t('Студенты',                 'Students',                  'Студенттер');
  String get teachersLabel           => _t('Преподаватели',            'Teachers',                  'Оқытушылар');
  String get playbackError           => _t('Ошибка воспроизведения',   'Playback error',             'Ойнату қатесі');
  String get emojiTab                => _t('Эмодзи',                   'Emoji',                      'Эмодзи');
  String get searchGif               => _t('Поиск GIF…',               'Search GIF…',                'GIF іздеу…');
  String get gifSearchHint           => _t('Введите запрос для поиска GIF', 'Enter a query to search for GIFs', 'GIF іздеу үшін сұраныс енгізіңіз');

  // ── Profile panel ─────────────────────────────────────────────────────────
  String get profileSaved            => _t('Профиль сохранён',          'Profile saved',             'Профиль сақталды');
  String get loginChangeError        => _t('Ошибка смены логина',        'Login change error',        'Логинді өзгерту қатесі');
  String get usernameLabel           => _t('Имя пользователя',          'Username',                  'Пайдаланушы аты');
  String get personalDataHeader      => _t('ЛИЧНЫЕ ДАННЫЕ',             'PERSONAL DATA',             'ЖЕКЕ ДЕРЕКТЕР');
  String get interfaceSettings       => _t('НАСТРОЙКА ИНТЕРФЕЙСА',      'INTERFACE SETTINGS',        'ИНТЕРФЕЙС БАПТАУЛАРЫ');
  String get bio                     => _t('О себе',                    'About me',                  'Өзім туралы');
  String get bioHint                 => _t('Расскажите немного о себе...','Tell a bit about yourself...','Өзіңіз туралы аздап айтыңыз...');
  String get saveChangesBtn          => _t('Сохранить изменения',       'Save changes',              'Өзгерістерді сақтау');
  String get manageDevices           => _t('Управление устройствами',   'Manage devices',            'Құрылғыларды басқару');
  // avatarUploadError is defined in the ПРОФИЛЬ section above — reuse that

  // ── Settings overlay ──────────────────────────────────────────────────────
  String get systemFont              => _t('Системный',                 'System',                    'Жүйелік');
  String get bubblePreviewOther      => _t('Привет! 👋',               'Hello! 👋',                 'Сәлем! 👋');
  String get bubblePreviewMe         => _t('Привет! 😊',               'Hello! 😊',                 'Сәлем! 😊');
  String get appVersion              => _t('Версия 1.0.0',             'Version 1.0.0',             'Нұсқа 1.0.0');

  // ── Devices screen ────────────────────────────────────────────────────────
  // retry defined earlier — reuse that
  String get devicesTitle            => _t('Устройства',               'Devices',                   'Құрылғылар');
  String get failedToLoadDevices     => _t('Не удалось загрузить устройства','Could not load devices','Құрылғыларды жүктеу мүмкін болмады');
  String get noActiveDevices         => _t('Нет активных устройств',   'No active devices',         'Белсенді құрылғылар жоқ');
  String activeSessionsCount(int n)  => _t('АКТИВНЫЕ СЕАНСЫ ($n)',     'ACTIVE SESSIONS ($n)',      'БЕЛСЕНДІ СЕАНСТАР ($n)');
  String get terminateSession        => _t('Завершить сеанс',          'End session',               'Сеансты аяқтау');
  String terminateSessionMsg(String name) => _t('Завершить сеанс на $name?', 'End session on $name?', '$name құрылғысындағы сеансты аяқтайсыз ба?');
  String get terminate               => _t('Завершить',                'End',                       'Аяқтау');
  String get logoutThisDevice        => _t('Выйти с этого устройства', 'Log out from this device',  'Осы құрылғыдан шығу');
  String get logoutThisDeviceMsg     => _t('Вы выйдете из аккаунта на текущем устройстве.','You will be logged out on this device.','Ағымдағы құрылғыдан аккаунттан шығасыз.');
  String get logoutAllDevices        => _t('Выйти со всех устройств',  'Log out from all devices',  'Барлық құрылғылардан шығу');
  String get logoutAllDevicesMsg     => _t('Все активные сеансы будут завершены, включая текущий.\nВы будете перенаправлены на экран входа.','All active sessions will be ended, including this one.\nYou will be redirected to the login screen.','Ағымдағыны қоса барлық белсенді сеанстар аяқталады.\nКіру экранына бағытталасыз.');
  String get logoutAllBtn            => _t('Выйти со всех',            'Log out from all',          'Барлығынан шығу');
  String get logoutAllHint           => _t('Выйдет со всех сеансов, включая текущий.','Logs out from all sessions, including current.','Ағымдағыны қоса барлық сеанстардан шығады.');
  String get thisDevice              => _t('Это\nустройство',          'This\ndevice',               'Осы\nқұрылғы');
  String get browserPlatform        => _t('Браузер',                   'Browser',                   'Браузер');
  String deleteChatForever(String name) => _t('«$name» будет удалено навсегда.', '«$name» will be deleted forever.', '«$name» мәңгілікке жойылады.');
  String fullDate(int day, int month, int year) => _t(
    '$day ${["января","февраля","марта","апреля","мая","июня","июля","августа","сентября","октября","ноября","декабря"][month-1]} $year',
    '${["January","February","March","April","May","June","July","August","September","October","November","December"][month-1]} $day, $year',
    '$day ${["қаңтар","ақпан","наурыз","сәуір","мамыр","маусым","шілде","тамыз","қыркүйек","қазан","қараша","желтоқсан"][month-1]} $year',
  );
  String get justNow                 => _t('Только что',               'Just now',                  'Жаңа ғана');
  String minutesAgo(int n)           => _t('$n мин. назад',            '$n min. ago',               '$n мин. бұрын');
  String hoursAgo(int n)             => _t('$n ч. назад',              '$n hr. ago',                '$n сағ. бұрын');
  String get yesterday               => _t('Вчера',                    'Yesterday',                 'Кеше');
  String daysAgo(int n)              => _t('$n дн. назад',             '$n days ago',               '$n күн бұрын');
  String errorText(String e)         => _t('Ошибка: $e',               'Error: $e',                 'Қате: $e');

  // ── Comments screen ───────────────────────────────────────────────────────
  String get censoredComment         => _t(
    'Комментарий содержал недопустимые слова и был автоматически отредактирован.',
    'The comment contained inappropriate words and was automatically edited.',
    'Пікір тиісті сөздерді қамтыды және автоматты түрде өңделді.',
  );
  String get discussion              => _t('Обсуждение',               'Discussion',                'Талқылау');
  String get noComments              => _t('Нет комментариев',          'No comments',               'Пікірлер жоқ');
  String commentCount(int n)         {
    final en = '$n comment${n == 1 ? '' : 's'}';
    final kk = '$n пікір';
    final mod10 = n % 10, mod100 = n % 100;
    String ru;
    if (mod100 >= 11 && mod100 <= 19) ru = '$n комментариев';
    else if (mod10 == 1)              ru = '$n комментарий';
    else if (mod10 >= 2 && mod10 <= 4) ru = '$n комментария';
    else                              ru = '$n комментариев';
    return _t(ru, en, kk);
  }
  String get beFirstToComment        => _t('Будьте первым, кто прокомментирует', 'Be the first to comment', 'Бірінші пікір қалдырыңыз');
  String get discussionStart         => _t('Начало обсуждения',         'Start of discussion',       'Талқылаудың басы');
  String get editing                 => _t('Редактирование',            'Editing',                   'Өңдеу');
  String get today                   => _t('Сегодня',                   'Today',                     'Бүгін');
  String get selectAction            => _t('Выделить',                  'Select',                    'Таңдау');
  String shortMonthDate(int day, int month) {
    final ruM = ['янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек'];
    final enM = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final kkM = ['қаң','ақп','нау','сәу','мам','мау','шіл','там','қыр','қаз','қар','жел'];
    return _t('$day ${ruM[month-1]}', '${enM[month-1]} $day', '$day ${kkM[month-1]}');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Delegate
// ─────────────────────────────────────────────────────────────────────────────

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['ru', 'en', 'kk'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Удобное расширение
// ─────────────────────────────────────────────────────────────────────────────

extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
