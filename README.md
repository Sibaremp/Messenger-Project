# Caspian Messenger

Корпоративный мессенджер для учебных заведений с поддержкой чатов, голосовых и видеозвонков, файлообмена и ролевого доступа. Состоит из трёх независимых компонентов: серверной части, мобильного/десктопного клиента и веб-панели администратора.

---

## Структура репозитория

```
Messenger-Project/
├── CaspianMessenger.Server/      # Backend (ASP.NET Core 10)
├── messenger_flutter/            # Клиент (Flutter)
└── admin_panel_messenger/        # Панель администратора (Flutter Web)
```

---

## Стек технологий

| Компонент | Технологии |
|---|---|
| **Backend** | .NET 10, ASP.NET Core, Entity Framework Core, PostgreSQL, SignalR, WebRTC, FCM |
| **Клиент** | Flutter (Android, iOS, Windows, macOS, Linux, Web) |
| **Админ-панель** | Flutter Web, Riverpod, go_router, Dio |

---

## Возможности

### Сообщения
- Личные чаты (1-на-1) и групповые чаты
- Каналы/предметы (публикует только администратор, участники комментируют)
- Редактирование, удаление, пересылка и закрепление сообщений
- Голосовые сообщения (запись и воспроизведение)
- Ответы на сообщения с упоминаниями
- Опросы с несколькими вариантами ответа
- Сквозное шифрование (X25519 ECDH + AES-256-GCM)
- Фильтрация нецензурной лексики

### Звонки
- Аудио- и видеозвонки (1-на-1 и групповые)
- WebRTC peer-to-peer с STUN/ICE серверами
- Push-уведомления о входящих звонках (FCM, работает в фоне)
- Управление камерой, микрофоном и динамиком во время звонка

### Файлы
- Изображения, видео, документы (до 50 МБ)
- Автоматические превью видео (FFmpeg)
- Определение длительности видео

### Уведомления
- Firebase Cloud Messaging (FCM)
- Локальные уведомления на десктопе
- Массовая рассылка администратором (всем / студентам / преподавателям / группе)

### Администрирование
- Управление пользователями, группами и предметами
- База участников с импортом из Excel/CSV/JSON
- Назначение преподавателей на группы и предметы
- Дашборд с метриками (активные пользователи, рост, статистика уведомлений)
- Удалённое завершение сессий

---

## Аутентификация и роли

- JWT Bearer токены (срок настраивается, по умолчанию 30 дней)
- Роли: `student`, `teacher`, `admin`
- Смена пароля инвалидирует все активные сессии
- Управление устройствами (FCM-токены)

---

## База данных

PostgreSQL. Основные таблицы:

`Users` · `People` · `Admins` · `Chats` · `ChatMembers` · `Messages` · `Comments` · `Attachments` · `Sessions` · `UserDevices` · `Subjects` · `TeacherSubjectGroups` · `Notifications` · `Polls` · `PollOptions` · `PollVotes` · `Calls` · `CallParticipants`

Миграции применяются автоматически при запуске сервера.

---

## Быстрый старт

### Требования

- .NET 10 SDK
- PostgreSQL 15+
- Flutter 3.x SDK
- FFmpeg (для видео)
- Firebase проект (FCM)

### 1. Backend

```bash
cd CaspianMessenger.Server
```

Заполните `appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database=caspian_messenger;Username=postgres;Password=yourpassword"
  },
  "Jwt": {
    "Key": "your-secret-key-min-32-chars",
    "Issuer": "CaspianMessenger",
    "Audience": "CaspianMessengerUsers",
    "ExpiryDays": 30
  },
  "Firebase": {
    "CredentialsPath": "firebase-adminsdk.json"
  },
  "FileStorage": {
    "BasePath": "wwwroot/uploads"
  },
  "FFmpeg": {
    "FfmpegPath": "/usr/bin/ffmpeg",
    "FfprobePath": "/usr/bin/ffprobe"
  }
}
```

```bash
dotnet run
```

API доступно по адресу `https://localhost:5001`. Swagger UI: `https://localhost:5001/swagger`.

### 2. Flutter-клиент

```bash
cd messenger_flutter
flutter pub get
```

Укажите адрес сервера в конфигурации приложения, затем:

```bash
# Android / iOS
flutter run

# Desktop
flutter run -d windows   # или macos / linux

# Web
flutter run -d chrome
```

### 3. Панель администратора

```bash
cd admin_panel_messenger
flutter pub get
flutter run -d chrome
```

### Docker (опционально)

```bash
cd CaspianMessenger.Server
docker build -t caspian-messenger-server .
docker run -p 5001:5001 --env-file .env caspian-messenger-server
```

---

## Архитектура backend

```
Controllers   →   Services   →   Models / DTOs
                     ↓
              SignalR Hubs (ChatHub, CallsHub)
                     ↓
              PostgreSQL (EF Core)
```

- **Layered**: Controllers → Services → Models
- **Real-time**: SignalR WebSocket для чатов и звонков
- **Batched DB writes**: один `SaveChanges` на запрос
- **Scoped DbContext, Singleton Services** для `FcmService` и `ProfanityFilter`

---

## Документация компонентов

- [Backend README](CaspianMessenger.Server/README.md) — API endpoints, конфигурация, деплой
- [Flutter README](messenger_flutter/README.md) — архитектура клиента, зависимости, сборка
- [Admin Panel README](admin_panel_messenger/README.md) — функции панели, структура, настройка
