# CaspianMessenger — Server

ASP.NET Core 10 backend для мессенджера учебного заведения. REST API + SignalR + WebRTC-сигнализация + FCM push.

---

## Содержание

- [Стек](#стек)
- [Требования](#требования)
- [Быстрый старт](#быстрый-старт)
- [Конфигурация](#конфигурация)
- [База данных](#база-данных)
- [Аутентификация](#аутентификация)
- [API — Пользователи](#api--пользователи)
- [API — Чаты и сообщения](#api--чаты-и-сообщения)
- [API — Звонки](#api--звонки)
- [API — Файлы](#api--файлы)
- [API — Уведомления (FCM)](#api--уведомления-fcm)
- [API — Опросы](#api--опросы)
- [API — Поиск](#api--поиск)
- [API — Админ-панель](#api--админ-панель)
- [SignalR](#signalr)
- [Фильтр мата](#фильтр-мата)
- [Файловое хранилище](#файловое-хранилище)
- [Архитектура](#архитектура)

---

## Стек

| Компонент | Версия / библиотека |
|---|---|
| Runtime | .NET 10 |
| Web framework | ASP.NET Core 10 (Minimal + Controllers) |
| ORM | Entity Framework Core 10 (Npgsql) |
| База данных | PostgreSQL 15+ |
| Аутентификация | JWT Bearer (Microsoft.AspNetCore.Authentication.JwtBearer) |
| Real-time | SignalR |
| Push | Firebase Admin SDK (FCM) |
| Пароли | BCrypt.Net-Next |
| Логирование | Serilog |
| Видеопревью | FFmpeg / FFprobe |

---

## Требования

- [.NET 10 SDK](https://dotnet.microsoft.com/download)
- PostgreSQL 15+
- FFmpeg (опционально, для превью видео)
- Firebase-проект с сервисным аккаунтом (опционально, для push)

---

## Быстрый старт

```bash
# 1. Клонировать репозиторий
git clone <repo-url>
cd CaspianMessenger.Server

# 2. Скопировать настройки и отредактировать
cp appsettings.json appsettings.Development.json

# 3. Применить миграции
dotnet ef database update

# 4. Запустить
dotnet run
```

Сервер запустится на `http://localhost:5216`.

---

## Конфигурация

Все настройки — в `appsettings.json`. Для переопределения в продакшне используйте переменные окружения или `appsettings.Production.json`.

```json
{
  "ConnectionStrings": {
    "Default": "Host=localhost;Port=5432;Database=caspian_messenger;Username=postgres;Password=..."
  },

  "Jwt": {
    "Key": "минимум-32-символа-случайная-строка",
    "Issuer": "CaspianMessenger",
    "Audience": "CaspianMessengerApp",
    "ExpirationDays": 30
  },

  "Admin": {
    "Login": "admin",
    "Password": "admin123"
  },

  "FileStorage": {
    "BasePath": "./uploads",
    "MaxFileSizeMB": 50,
    "AllowedExtensions": ".jpg,.jpeg,.png,.gif,.mp4,.mov,.pdf,.doc,.docx,.xls,.xlsx"
  },

  "FFmpeg": {
    "FfmpegPath":  "ffmpeg",
    "FfprobePath": "ffprobe"
  },

  "Firebase": {
    "CredentialsPath": "./docs/firebase-adminsdk.json"
  },

  "ProfanityFilter": {
    "Words": ["слово1", "слово2"]
  }
}
```

> **ProfanityFilter.Words** — если указан, полностью заменяет встроенный список. Если не указан — используется встроенный.

---

## База данных

```bash
# Применить все миграции
dotnet ef database update

# Создать новую миграцию после изменения моделей
dotnet ef migrations add НазваниеМиграции

# Откатить последнюю миграцию
dotnet ef migrations remove
```

### Схема (основные таблицы)

| Таблица | Описание |
|---|---|
| `Users` | Аккаунты пользователей (login, role, group, FCM, сессии) |
| `People` | Справочник участников (ФИО, импортируется из Excel/JSON/SQL) |
| `Admins` | Администраторы панели управления |
| `Chats` | Чаты: `direct`, `group`, `community` |
| `ChatMembers` | Участники чатов с ролью: `creator` / `admin` / `member` |
| `Messages` | Сообщения |
| `Comments` | Комментарии к сообщениям (тред) |
| `Attachments` | Вложения (изображения, видео, документы, аудио) |
| `Sessions` | Активные JWT-сессии пользователей |
| `UserDevices` | FCM-токены устройств (несколько на пользователя) |
| `Subjects` | Учебные предметы |
| `TeacherSubjectGroups` | Назначения: преподаватель → предмет → группа |
| `Notifications` | История административных push-уведомлений |
| `Polls` / `PollOptions` / `PollVotes` | Опросы в сообщениях |
| `Calls` / `CallParticipants` | WebRTC-звонки |

---

## Аутентификация

Все защищённые эндпоинты требуют заголовок:

```
Authorization: Bearer <token>
```

Токен получается при регистрации или входе. Срок действия — `Jwt:ExpirationDays` дней (по умолчанию 30).

Сессии инвалидируются при:
- Смене пароля администратором
- Явном завершении сессии пользователем

---

## API — Пользователи

### Регистрация и вход

| Метод | URL | Auth | Описание |
|---|---|---|---|
| `POST` | `/api/auth/register` | — | Регистрация. Тело: `{ personId, name, password, phone?, email? }` |
| `POST` | `/api/auth/login` | — | Вход. Тело: `{ name, password }` |
| `GET` | `/api/auth/groups` | — | Группы с незарегистрированными участниками |
| `GET` | `/api/auth/people?group=&role=` | — | Незарегистрированные участники для выбора при регистрации |
| `GET` | `/api/auth/sessions` | ✓ | Список активных сессий текущего пользователя |
| `DELETE` | `/api/auth/sessions/{id}` | ✓ | Завершить конкретную сессию |
| `DELETE` | `/api/auth/sessions` | ✓ | Завершить все сессии |
| `PUT` | `/api/auth/login` | ✓ | Сменить логин. Тело: `{ newLogin, password }` |

#### Ответ при регистрации / входе

```json
{
  "id": "uuid",
  "login": "ivanov_i",
  "name": "ivanov_i",
  "role": "student",
  "group": "ИС-21",
  "phone": "+79001234567",
  "email": "user@example.com",
  "avatarPath": "/uploads/...",
  "description": "...",
  "isOnline": true,
  "lastSeen": "2026-05-08T10:00:00Z",
  "token": "eyJ...",
  "firstName": "Иван",
  "lastName": "Иванов",
  "middleName": "Иванович"
}
```

### Профиль

| Метод | URL | Auth | Описание |
|---|---|---|---|
| `GET` | `/api/users/me` | ✓ | Данные текущего пользователя + ФИО из People |
| `PUT` | `/api/users/me` | ✓ | Обновить профиль (phone, email, bio, avatarUrl) |
| `POST` | `/api/users/me/avatar` | ✓ | Загрузить аватар (multipart, поле `file`, до 10 МБ) |
| `GET` | `/api/users/{id}` | ✓ | Публичная карточка пользователя |

> Логин (`name`) через `PUT /api/users/me` **не меняется** — только через `PUT /api/auth/login`.

---

## API — Чаты и сообщения

### Чаты

| Метод | URL | Auth | Описание |
|---|---|---|---|
| `GET` | `/api/chats` | ✓ | Все чаты текущего пользователя |
| `GET` | `/api/chats/{id}?offset=0&limit=50` | ✓ | Один чат с историей сообщений |
| `POST` | `/api/chats/direct` | ✓ | Создать личный чат. Тело: `{ userId }` |
| `POST` | `/api/chats/group` | ✓ | Создать групповой чат. Тело: `{ name, memberIds[] }` |
| `PUT` | `/api/chats/{id}/settings` | ✓ | Изменить название/описание/аватар чата |
| `DELETE` | `/api/chats/{id}` | ✓ | Удалить чат (только creator) |
| `POST` | `/api/chats/{id}/avatar` | ✓ | Загрузить аватар чата (admin/creator, до 10 МБ) |
| `POST` | `/api/chats/{id}/read` | ✓ | Отметить все сообщения чата прочитанными |
| `GET` | `/api/chats/search?q=` | ✓ | Поиск чатов по названию |

#### Типы чатов

| `type` | `isAcademic` | Описание |
|---|---|---|
| `direct` | `false` | Личный чат (2 участника) |
| `group` | `false` / `true` | Группа. `isAcademic=true` — автоматический чат учебной группы |
| `community` | `false` | Предметный чат (преподаватель-создатель + студенты группы) |

### Участники чата

| Метод | URL | Auth | Описание |
|---|---|---|---|
| `POST` | `/api/chats/{id}/members` | ✓ | Добавить участника. Тело: `{ userId, role }` |
| `POST` | `/api/chats/{id}/join` | ✓ | Вступить самостоятельно |
| `PUT` | `/api/chats/{id}/members/{userId}` | ✓ | Изменить роль участника (только creator) |
| `DELETE` | `/api/chats/{id}/members/{userId}` | ✓ | Удалить участника |

### Сообщения

| Метод | URL | Auth | Описание |
|---|---|---|---|
| `POST` | `/api/chats/{id}/messages` | ✓ | Отправить сообщение |
| `PUT` | `/api/chats/{id}/messages/{msgId}` | ✓ | Редактировать сообщение |
| `DELETE` | `/api/chats/{id}/messages` | ✓ | Удалить сообщения. Тело: `{ ids: [] }` |
| `POST` | `/api/chats/{id}/forward` | ✓ | Переслать сообщения. Тело: `{ messageIds: [] }` |
| `POST` | `/api/chats/{id}/messages/{msgId}/pin` | ✓ | Закрепить сообщение |
| `POST` | `/api/chats/{id}/messages/{msgId}/unpin` | ✓ | Открепить сообщение |

#### Тело запроса `POST /messages`

```json
{
  "text": "Привет!",
  "replyTo": { "messageId": "uuid" },
  "attachment": {
    "path": "/uploads/2026/05/file.jpg",
    "fileName": "photo.jpg",
    "fileSize": 102400,
    "type": "image",
    "mimeType": "image/jpeg",
    "thumbnailPath": null,
    "durationMs": null
  },
  "mentions": [
    { "userId": "uuid", "username": "ivanov", "offset": 0, "length": 7 }
  ]
}
```

> В `community`-чатах писать могут только `admin` и `creator`.

### Комментарии (треды)

| Метод | URL | Auth | Описание |
|---|---|---|---|
| `POST` | `/api/chats/{id}/messages/{msgId}/comments` | ✓ | Добавить комментарий |
| `PUT` | `/api/chats/{id}/messages/{msgId}/comments/{commentId}` | ✓ | Редактировать комментарий |
| `DELETE` | `/api/chats/{id}/messages/{msgId}/comments` | ✓ | Удалить комментарии. Тело: `{ ids: [] }` |

---

## API — Звонки

| Метод | URL | Auth | Описание |
|---|---|---|---|
| `GET` | `/api/calls/ice-servers` | ✓ | ICE-серверы для WebRTC (STUN Google) |

Сигнализация звонков (offer/answer/candidate/end) проходит через SignalR хаб `/hub/calls`.

---

## API — Файлы

| Метод | URL | Auth | Лимит | Описание |
|---|---|---|---|---|
| `POST` | `/api/files/upload` | ✓ | 50 МБ | Загрузить файл (multipart, поле `file`) |
| `POST` | `/api/messages/upload-audio` | ✓ | 10 МБ | Загрузить голосовое сообщение |
| `GET` | `/api/files/search?q=&type=` | ✓ | — | Поиск вложений по имени файла |

#### Ответ `/api/files/upload`

```json
{
  "path": "/uploads/2026/05/uuid.mp4",
  "fileName": "video.mp4",
  "fileSize": 5242880,
  "type": "video",
  "mimeType": "video/mp4",
  "thumbnailPath": "/uploads/thumbnails/uuid.jpg",
  "durationMs": 12500
}
```

`thumbnailPath` и `durationMs` заполняются только для видео, если установлен FFmpeg.

Статические файлы доступны по URL напрямую: `GET /uploads/...`

---

## API — Уведомления (FCM)

### Пользовательские

| Метод | URL | Auth | Описание |
|---|---|---|---|
| `PUT` | `/api/notifications/fcm-token` | ✓ | Зарегистрировать FCM-токен устройства. Тело: `{ token, platform }` |
| `GET` | `/api/notifications?page=1&pageSize=50` | ✓ | История уведомлений для текущего пользователя |

---

## API — Опросы

| Метод | URL | Auth | Описание |
|---|---|---|---|
| `POST` | `/api/chats/{id}/polls` | ✓ | Создать опрос в чате |
| `POST` | `/api/chats/{id}/polls/{pollId}/vote` | ✓ | Проголосовать |
| `POST` | `/api/chats/{id}/polls/{pollId}/close` | ✓ | Закрыть опрос (admin/creator) |

---

## API — Поиск

| Метод | URL | Auth | Описание |
|---|---|---|---|
| `GET` | `/api/search?q=&type=` | ✓ | Полнотекстовый поиск по сообщениям и файлам |

---

## API — Админ-панель

Все эндпоинты требуют JWT-токен администратора.

### Вход

| Метод | URL | Описание |
|---|---|---|
| `POST` | `/api/admin/login` | Вход для администратора. Тело: `{ login, password }` → `{ token }` |

### Пользователи (аккаунты)

| Метод | URL | Описание |
|---|---|---|
| `GET` | `/api/admin/users` | Список всех пользователей (с ФИО из People) |
| `PUT` | `/api/admin/users/{id}` | Изменить login / role / group / phone |
| `PUT` | `/api/admin/users/{id}/password` | Сменить пароль + инвалидировать сессии |
| `DELETE` | `/api/admin/users/{id}` | Удалить аккаунт |

### Участники (справочник People)

| Метод | URL | Описание |
|---|---|---|
| `GET` | `/api/admin/people?search=&role=` | Список участников с фильтрацией |
| `PUT` | `/api/admin/people/{id}` | Изменить ФИО / роль / группу |
| `DELETE` | `/api/admin/people/{id}` | Удалить участника |
| `POST` | `/api/admin/import-people` | Импорт из Excel / JSON / CSV (multipart, поле `file`, до 10 МБ) |

#### Форматы импорта

**JSON** — массив объектов:
```json
[
  { "firstName": "Иван", "lastName": "Иванов", "middleName": "Иванович", "role": "student", "group": "ИС-21" },
  { "firstName": "Мария", "lastName": "Петрова", "role": "teacher" }
]
```

**Excel** — столбцы: `Фамилия`, `Имя`, `Отчество`, `Роль`, `Группа`.

### Группы

| Метод | URL | Описание |
|---|---|---|
| `GET` | `/api/admin/groups` | Все группы с `peopleCount` и `userCount` |
| `DELETE` | `/api/admin/groups/{name}` | Удалить группу: чат → сессии → устройства → аккаунты → очистить группу у People |

### Предметы

| Метод | URL | Описание |
|---|---|---|
| `GET` | `/api/admin/subjects` | Список предметов с кол-вом назначений |
| `POST` | `/api/admin/subjects` | Создать предмет. Тело: `{ name }` |
| `PUT` | `/api/admin/subjects/{id}` | Переименовать предмет |
| `DELETE` | `/api/admin/subjects/{id}` | Удалить предмет (каскадно удаляет назначения и чаты) |
| `GET` | `/api/admin/subjects/{id}/assignments` | Все назначения по предмету |
| `GET` | `/api/admin/people/{personId}/subjects` | Назначения преподавателя |
| `POST` | `/api/admin/people/{personId}/subjects` | Назначить преподавателя. Тело: `{ subjectId, groupName }` |
| `DELETE` | `/api/admin/people/{personId}/subjects/{assignmentId}` | Снять назначение |

При назначении (`POST`) автоматически создаётся community-чат `"{Предмет} {Группа}"` с преподавателем-создателем и всеми зарегистрированными студентами группы. При удалении назначения чат удаляется.

#### Ответ `/api/admin/people/{id}/subjects`

```json
[
  {
    "id": 3,
    "subjectId": 1,
    "subjectName": "Алгоритмизация",
    "groupName": "ПО 22-2",
    "chatId": "3fa85f64-5717-4562-b3fc-2c963f66afa6"
  }
]
```

### Административные уведомления (push)

| Метод | URL | Описание |
|---|---|---|
| `POST` | `/api/admin/notifications` | Отправить уведомление |
| `GET` | `/api/admin/notifications?page=1&pageSize=20` | История уведомлений |
| `DELETE` | `/api/admin/notifications/{id}` | Удалить запись из истории |
| `POST` | `/api/admin/notifications/upload` | Загрузить изображение для уведомления |

#### Тело запроса `POST /api/admin/notifications`

```json
{
  "title": "Важное объявление",
  "body": "Текст уведомления до 2000 символов",
  "target": "all",
  "imageUrl": "https://..."
}
```

`target`: `"all"` / `"students"` / `"teachers"`

Уведомление доставляется через **SignalR** (онлайн-клиенты) и **FCM** (фоновые/отключённые).

### Статистика

| Метод | URL | Описание |
|---|---|---|
| `GET` | `/api/admin/stats/activity?days=14` | Входы по дням |
| `GET` | `/api/admin/stats/notifications?weeks=8` | Push-уведомления по неделям |
| `GET` | `/api/admin/stats/growth?days=30` | Прирост участников с нарастающим итогом |

---

## SignalR

### Хаб чатов: `/hub/chat`

Клиент подключается с Bearer-токеном. После подключения сервер добавляет его в персональную группу по `userId`.

#### События, получаемые клиентом

| Событие | Данные | Описание |
|---|---|---|
| `ReceiveMessage` | `ChatDto` | Новое сообщение |
| `MessageEdited` | `{ chatId, messageId, text }` | Сообщение отредактировано |
| `MessagesDeleted` | `{ chatId, messageIds[] }` | Сообщения удалены |
| `UserOnlineStatus` | `{ userId, isOnline, lastSeen }` | Изменение онлайн-статуса |
| `ReceiveEvent` | произвольный объект | Системные события (pin, admin_notification и др.) |

#### События для звонков: `/hub/calls`

| Событие | Описание |
|---|---|
| `CallStarted` | Входящий звонок |
| `CallEnded` | Звонок завершён |
| `IceCandidate` | WebRTC ICE-кандидат |
| `SdpOffer` / `SdpAnswer` | WebRTC SDP |

---

## Фильтр мата

Серверный `ProfanityFilter` применяется автоматически при:
- Отправке сообщения
- Редактировании сообщения
- Отправке / редактировании комментария

Нецензурные слова заменяются символами `*` той же длины. Список расширяется через `appsettings.json`:

```json
"ProfanityFilter": {
  "Words": ["слово1", "слово2"]
}
```

Если секция `ProfanityFilter:Words` не задана — работает встроенный список.

---

## Файловое хранилище

Файлы сохраняются на диск в директорию `FileStorage:BasePath` (по умолчанию `./uploads`).

```
uploads/
  2026/05/          ← изображения, видео, документы (год/месяц)
  audio/            ← голосовые сообщения
  thumbnails/       ← превью видео (генерирует FFmpeg)
  notifications/    ← вложения к push-уведомлениям
```

Статические файлы отдаются напрямую через `app.UseStaticFiles()`.

### FFmpeg (видео)

При загрузке `.mp4` / `.mov` сервер автоматически:
1. Генерирует превью-кадр (`thumbnails/uuid.jpg`, 480px по ширине)
2. Определяет длительность через `ffprobe`

Установка FFmpeg:
```powershell
winget install Gyan.FFmpeg
```

Или вручную — распаковать и указать полные пути в конфигурации:
```json
"FFmpeg": {
  "FfmpegPath":  "C:\\ffmpeg\\bin\\ffmpeg.exe",
  "FfprobePath": "C:\\ffmpeg\\bin\\ffprobe.exe"
}
```

---

## Архитектура

```
Controllers/          ← HTTP-слой (маршрутизация, валидация входа/выхода)
Services/             ← Бизнес-логика
  AuthService         ← Регистрация, вход, групповые чаты при регистрации
  ChatService         ← CRUD чатов, участники, маппинг в DTO
  MessageService      ← Отправка/редактирование/удаление, пины, пересылка
  NotificationService ← SignalR-события
  FcmService          ← Firebase push (singleton, batch до 500 токенов)
  ProfanityFilter     ← Фильтр нецензурной лексики (singleton, Regex)
  FileService         ← Загрузка файлов, FFmpeg-обработка видео
  ImportService       ← Импорт участников из Excel/JSON
  SessionService      ← Управление JWT-сессиями
  EncryptionService   ← Шифрование сообщений E2E (Diffie-Hellman)
Models/               ← EF Core entities
DTOs/                 ← Request/Response объекты
Data/
  AppDbContext        ← EF Core контекст, конфигурация отношений и индексов
Hubs/
  ChatHub             ← SignalR хаб (чаты + звонки)
Migrations/           ← EF Core миграции
```

### Ключевые паттерны

- **Single SaveChanges** — все операции в рамках одного запроса подготавливают сущности в контексте, `SaveChangesAsync()` вызывается один раз в конце. Это предотвращает `DbUpdateConcurrencyException`.
- **Scoped DbContext, Singleton Services** — `FcmService` и `ProfanityFilter` создаются один раз. `FcmService` создаёт собственный `IServiceScope` для доступа к БД внутри singleton.
- **Автоматические чаты** — при регистрации студента: групповой академический чат + все предметные community-чаты его группы. При назначении преподавателя: community-чат предмета с текущими студентами.
