# ER-диаграмма базы данных — Caspian College Messenger

```mermaid
erDiagram

    Users {
        uuid    Id                          PK
        string  Name                        "макс. 100 симв., уникальный"
        string  PasswordHash                "BCrypt-хеш"
        string  Role                        "student | teacher"
        string  Group                       "учебная группа (ИС-21 и др.)"
        string  Phone
        string  Email
        string  AvatarPath
        string  Description
        bool    IsOnline
        bool    MentionNotificationsOverride
        datetime CreatedAt
        datetime LastSeen
    }

    Sessions {
        uuid    Id           PK
        uuid    UserId       FK
        string  TokenHash    "SHA-256 от JWT, уникальный"
        string  DeviceName
        string  Platform     "web | android | ios | windows | ..."
        string  Location
        bool    IsActive
        datetime CreatedAt
        datetime LastActivity
    }

    Chats {
        uuid    Id             PK
        string  Name           "макс. 200 симв."
        string  Type           "direct | group | community"
        uuid    AdminId        FK "nullable"
        string  AvatarPath
        string  Description
        bool    IsAcademic
        jsonb   PinnedMessageIds "список UUID, макс. 5"
        datetime CreatedAt
    }

    ChatMembers {
        uuid    Id        PK
        uuid    ChatId    FK
        uuid    UserId    FK
        string  Role      "creator | admin | member"
        datetime JoinedAt
    }

    Messages {
        uuid    Id         PK
        uuid    ChatId     FK
        uuid    SenderId   FK
        string  Text
        uuid    ReplyToId  FK "nullable, самоссылка"
        uuid    PollId     FK "nullable"
        string  Status     "sent | delivered | read"
        bool    IsEdited
        datetime CreatedAt
        datetime UpdatedAt
    }

    Comments {
        uuid    Id          PK
        uuid    MessageId   FK
        uuid    SenderId    FK
        string  Text
        uuid    ReplyToId   FK "nullable, самоссылка"
        bool    IsEdited
        datetime CreatedAt
    }

    Attachments {
        uuid    Id          PK
        uuid    MessageId   FK "nullable"
        uuid    CommentId   FK "nullable"
        string  FilePath
        string  FileName
        bigint  FileSize
        string  Type        "image | video | document"
        string  MimeType
        datetime CreatedAt
    }

    MessageReadStatuses {
        uuid    Id          PK
        uuid    MessageId   FK
        uuid    UserId      FK
        datetime ReadAt
    }

    Mentions {
        uuid    Id          PK
        uuid    MessageId   FK
        string  UserId      "UUID участника или 'all'"
        string  Username
        int     Offset      "позиция в тексте"
        int     Length      "длина упоминания"
    }

    Polls {
        uuid    Id            PK
        string  Question      "макс. 500 симв."
        string  Type          "single | multiple"
        bool    IsAnonymous
        bool    CanChangeVote
        bool    IsClosed
        datetime Deadline     "nullable"
        datetime CreatedAt
    }

    PollOptions {
        uuid    Id       PK
        uuid    PollId   FK
        string  Text
        int     Position "порядок отображения"
    }

    PollVotes {
        uuid    Id        PK
        uuid    PollId    FK
        uuid    OptionId  FK
        uuid    UserId    FK
        datetime VotedAt
    }

    %% ──────────────────────────────────────────
    %% Связи
    %% ──────────────────────────────────────────

    Users         ||--o{ Sessions            : "имеет сессии"
    Users         ||--o{ ChatMembers         : "участвует в чатах"
    Users         ||--o{ Messages            : "отправляет"
    Users         ||--o{ Comments            : "пишет комментарии"
    Users         ||--o{ MessageReadStatuses : "читает сообщения"
    Users         ||--o{ PollVotes           : "голосует"
    Users         |o--o{ Chats              : "администрирует"

    Chats         ||--o{ ChatMembers         : "имеет участников"
    Chats         ||--o{ Messages            : "содержит сообщения"

    Messages      ||--o{ Comments            : "имеет комментарии"
    Messages      ||--o{ Attachments         : "имеет вложения"
    Messages      ||--o{ MessageReadStatuses : "статусы прочтения"
    Messages      ||--o{ Mentions            : "содержит упоминания"
    Messages      |o--o| Polls              : "содержит опрос"
    Messages      |o--o| Messages           : "ReplyTo (цитата)"

    Comments      ||--o{ Attachments         : "имеет вложения"
    Comments      |o--o| Comments           : "ReplyTo (цитата)"

    Polls         ||--|{ PollOptions          : "содержит варианты"
    Polls         ||--o{ PollVotes           : "получает голоса"

    PollOptions   ||--o{ PollVotes           : "выбирается в голосах"
```

---

## Описание связей

| Связь | Тип | Описание |
|-------|-----|----------|
| Users → Sessions | 1:N | Один пользователь — несколько активных сессий (разные устройства) |
| Users → ChatMembers | 1:N | Пользователь может быть участником многих чатов |
| Chats → ChatMembers | 1:N | Чат содержит список участников с ролями |
| Chats → Messages | 1:N | Все сообщения принадлежат одному чату |
| Messages → Messages | 0..1:N | Самоссылка: ReplyToId — цитата другого сообщения |
| Messages → Polls | 1:0..1 | Сообщение может содержать опрос |
| Messages → Comments | 1:N | Тред комментариев под сообщением |
| Messages → Attachments | 1:N | Вложения сообщения |
| Messages → Mentions | 1:N | Упоминания @user и @all в тексте |
| Messages → MessageReadStatuses | 1:N | Таблица прочтений: кто и когда прочитал |
| Comments → Attachments | 1:N | Вложения комментария |
| Comments → Comments | 0..1:N | Самоссылка: ReplyTo — цитата комментария |
| Polls → PollOptions | 1:2..10 | Минимум 2, максимум 10 вариантов ответа |
| Polls → PollVotes | 1:N | Все голоса по опросу |
| PollOptions → PollVotes | 1:N | Голоса за конкретный вариант |

## Уникальные ограничения (UNIQUE)

| Таблица | Поля | Смысл |
|---------|------|-------|
| `Users` | `Name` | Имя пользователя — уникальный идентификатор |
| `Sessions` | `TokenHash` | Один токен — одна сессия |
| `ChatMembers` | `(ChatId, UserId)` | Пользователь входит в чат только один раз |
| `MessageReadStatuses` | `(MessageId, UserId)` | Пользователь читает сообщение один раз |
| `PollVotes` | `(PollId, OptionId, UserId)` | Нельзя проголосовать за один вариант дважды |
