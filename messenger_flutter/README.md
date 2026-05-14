# Caspian Messenger

Корпоративный мессенджер для студентов и преподавателей колледжа на Flutter.  
Адаптивный интерфейс: мобильные устройства, десктоп и браузер.

---

## Возможности

### Чаты
- **Личные сообщения** — переписка один на один
- **Группы** — чаты, в которых могут писать все участники
- **Сообщества** — каналы с правом записи только у администратора, комментарии к постам
- **Разделы**: «Общение» (студенты) и «Академический» (преподаватели)
- Ответ на сообщение (swipe-to-reply с анимацией и вибрацией)
- Пересылка, редактирование и удаление сообщений
- Режим выделения нескольких сообщений
- Вложения: фото, видео, документы
- **Голосовые сообщения** — запись и воспроизведение прямо в чате
- Полноэкранный просмотр медиа с видеоплеером
- **@упоминания** участников с подсветкой и уведомлениями
- **GIF и стикеры** через Tenor (поиск и вставка)
- **Опросы** — создание, голосование, завершение

### Звонки (WebRTC)
- **Аудио и видео звонки** — один на один и групповые
- Входящий вызов с уведомлением (FCM push) — работает в фоне и при закрытом приложении
- Переключение камера / микрофон / динамик прямо во время звонка
- Поддержка нескольких участников (mesh P2P)
- Fallback: если камера недоступна — автоматически переходит на аудио

### Комментарии (сообщества)
- Полная функциональность: ответ, редактирование, удаление, пересылка
- Вложения в комментариях
- Режим выделения комментариев

### Безопасность
- **Сквозное шифрование сообщений** — X25519 ECDH + AES-256-GCM + HKDF
- JWT-аутентификация с управлением сессиями
- Возможность завершить любую сессию удалённо

### Статус сообщений

| Иконка | Статус |
|--------|--------|
| ⏱ | Отправляется |
| ✓ | Отправлено |
| ✓✓ | Доставлено |
| ✓✓ (голубые) | Прочитано |
| ✗ | Ошибка |

### Уведомления
- **Push-уведомления** (Firebase Cloud Messaging) — работают в фоне на Android / iOS
- Локальные уведомления на десктопе (Windows / macOS / Linux)
- Вкладка уведомлений хранит упоминания (`@ник`, `@all`) и ответы
- Счётчик непрочитанных на иконке вкладки

### Аватары и профили
- 8 контрастных hash-based цветов для имён отправителей
- Группы и сообщества: **инициалы из названия** (как в Telegram)
- Автоматический fallback на инициалы при ошибке загрузки фото
- Учебная группа студента отображается перед именем в групповых чатах

### Контакты и поиск
- Автоматическая загрузка телефонной книги устройства (Android / iOS)
- Маркировка контактов, зарегистрированных в приложении
- Поиск чатов, сообщений, файлов

### Профиль пользователя
- Аватарка (камера или галерея)
- Имя, логин, «О себе», учебная группа
- Автозаполнение номера с SIM-карты (Android)
- Переключатель светлой / тёмной / системной темы

### Управление сессиями
- Список активных сессий с платформой и временем последней активности
- Текущая сессия помечается «Это устройство»
- Завершение конкретной сессии или всех сразу

### Адаптивный интерфейс
- **Мобильные устройства** — полноэкранная навигация с BottomNavigationBar
- **Десктоп** (ширина ≥ 800 px) — трёхпанельная раскладка со сворачиваемым сайдбаром
- **Браузер (Web)** — полноценная работа, включая звонки и SignalR

---

## Архитектура

```
lib/
├── main.dart                       # Точка входа
├── models.dart                     # Модели данных с JSON-сериализацией
├── app_constants.dart              # Цвета, размеры, форматирование
├── theme.dart                      # Темы оформления, ThemeProvider
├── auth_screen.dart                # Экраны входа и регистрации
├── profile_screen.dart             # Профиль пользователя
├── responsive_shell.dart           # Адаптивная оболочка (mobile / desktop / web)
│
├── services/
│   ├── api_config.dart             # URL сервера, авто-выбор хоста
│   ├── auth_service.dart           # JWT, secure storage, управление сессиями
│   ├── chat_service.dart           # Абстракция ChatService + LocalChatService
│   ├── api_chat_service.dart       # REST + SignalR реализация ChatService
│   ├── signaling_service.dart      # SignalR-хаб звонков (WebRTC сигнализация)
│   ├── call_service.dart           # WebRTC: PeerConnection, треки, ICE
│   ├── call_state.dart             # DTO для событий звонков
│   ├── encryption_service.dart     # X25519 + AES-256-GCM шифрование
│   ├── notification_service.dart   # FCM + локальные уведомления
│   ├── notification_parser.dart    # Разбор payload уведомлений
│   ├── notification_router.dart    # Навигация по тапу на уведомление
│   ├── notification_settings.dart  # Настройки уведомлений
│   ├── audio_service.dart          # Запись голосовых сообщений
│   ├── audio_player_service.dart   # Воспроизведение аудио
│   ├── file_download_service.dart  # Скачивание и кэширование файлов
│   ├── local_cache_service.dart    # Кэш сообщений / чатов
│   ├── tenor_service.dart          # Поиск GIF через Tenor API
│   ├── volume_service.dart         # Управление громкостью
│   └── sim_service.dart            # Чтение SIM-карты (Android / iOS)
│
├── widgets/
│   ├── sidebar.dart                # Сворачиваемый сайдбар (десктоп)
│   ├── chat_widgets.dart           # MessageBubble, PollCard, ChatAvatar, …
│   ├── audio_message_bubble.dart   # Пузырь голосового сообщения
│   ├── emoji_gif_panel.dart        # Панель эмодзи и GIF
│   ├── member_picker.dart          # Выбор участников группы
│   ├── notifications_panel.dart    # Панель уведомлений
│   ├── profile_panel.dart          # Десктопная панель профиля
│   └── settings_overlay.dart       # Оверлей настроек
│
└── screens/
    ├── call_screen.dart            # Экран звонка (WebRTC, видео/аудио)
    ├── chat_list_screen.dart       # Список чатов + уведомления + контакты
    ├── chat_screen.dart            # Экран переписки
    ├── chat_settings_screen.dart   # Настройки чата / группы
    ├── comments_screen.dart        # Комментарии к постам сообществ
    ├── contact_profile_screen.dart # Профиль собеседника
    ├── devices_screen.dart         # Активные сессии
    ├── group_profile_screen.dart   # Профиль группы / сообщества
    └── search_screen.dart          # Поиск
```

### Слой сервисов

`ChatService` — абстрактный интерфейс с потоком событий `Stream<ChatEvent>`.

| Реализация | Описание |
|---|---|
| `LocalChatService` | Данные в памяти (разработка без сервера) |
| `ApiChatService` | REST API + SignalR (продакшн) |

---

## Требования

| | Минимум |
|---|---|
| Flutter | 3.x |
| Dart | 3.x |
| Android | API 23 (Android 6.0) |
| iOS | 12.0 |
| Web | Chrome / Firefox / Safari (WebRTC) |
| Windows / macOS / Linux | Поддерживается |

---

## Зависимости

| Пакет | Назначение |
|---|---|
| `flutter_secure_storage` | Безопасное хранение JWT и сессии |
| `signalr_netcore` | SignalR real-time соединение |
| `flutter_webrtc` | WebRTC видео/аудио звонки |
| `firebase_messaging` | FCM push-уведомления (Android / iOS) |
| `flutter_local_notifications` | Уведомления на десктопе |
| `record` | Запись голосовых сообщений |
| `just_audio` + `just_audio_media_kit` | Воспроизведение аудио |
| `media_kit` / `media_kit_video` | Видеоплеер (десктоп / web) |
| `video_player` | Видеоплеер (mobile) |
| `image_picker` | Выбор фото / видео |
| `file_picker` | Выбор документов |
| `flutter_contacts` | Телефонная книга |
| `permission_handler` | Запрос разрешений |
| `cached_network_image` | Кэширование изображений |
| `emoji_picker_flutter` | Эмодзи-клавиатура |
| `cryptography` | X25519 + AES-256-GCM шифрование |
| `window_manager` | Управление окном (десктоп) |
| `http` | REST API запросы |
| `shared_preferences` | Хранение настроек |
| `open_filex` | Открытие скачанных файлов |
| `share_plus` | Поделиться файлом / сообщением |

---

## Запуск

```bash
flutter pub get
flutter run
```

### Android — разрешения
Прописаны в `AndroidManifest.xml`:
- `INTERNET` — сетевые запросы
- `READ_CONTACTS` — телефонная книга
- `READ_PHONE_STATE` / `READ_PHONE_NUMBERS` — данные SIM-карты
- `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` — медиа (Android 13+)
- `CAMERA` / `RECORD_AUDIO` — звонки и голосовые сообщения

---

## Подключение к серверу

### Локальная разработка

В `lib/services/api_config.dart` адрес выбирается автоматически:
- **Android-эмулятор** → `10.0.2.2:5216`
- **Браузер / iOS-симулятор / Десктоп** → `localhost:5216`

Для реального устройства укажи IP сервера в `main.dart`:
```dart
ApiConfig.overrideHost = '192.168.1.100';
```

### Продакшн

После деплоя сервера укажи домен:
```dart
ApiConfig.overrideHost = 'your-domain.com';
// Не забудь переключить на HTTPS в api_config.dart: http:// → https://
```

---

## Сервер

Серверная часть — **ASP.NET Core (.NET 10)** + **PostgreSQL 17**.  
Репозиторий: `CaspianMessenger.Server`

### Быстрый старт (Docker)

```bash
cd CaspianMessenger.Server

# Скопировать и заполнить секреты
cp .env.example .env

# Поднять всё одной командой (БД + миграции + сервер)
docker compose up --build
```

Сервер будет доступен на `http://localhost:5216`, Swagger на `/swagger`.

### Деплой на VPS

```bash
# На сервере (Ubuntu 24.04)
curl -fsSL https://get.docker.com | sh
git clone <repo> && cd CaspianMessenger.Server
cp .env.example .env && nano .env      # вписать пароли

chmod +x deploy.sh && ./deploy.sh       # поднимает nginx + app + db
```

После деплоя настроить HTTPS через Let's Encrypt (инструкция в `deploy.sh`).

### Стек сервера

| Компонент | Технология |
|---|---|
| API | ASP.NET Core 10, REST + SignalR |
| БД | PostgreSQL 17, Entity Framework Core |
| Аутентификация | JWT Bearer |
| Push-уведомления | Firebase Admin SDK (FCM) |
| Видео-превью | FFmpeg |
| Контейнеризация | Docker + docker compose |
| Reverse proxy | nginx (продакшн) |
