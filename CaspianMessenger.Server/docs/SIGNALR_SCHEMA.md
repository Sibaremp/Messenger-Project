# Схема работы SignalR — Caspian College Messenger

---

## 1. Архитектура групп (Hubs & Groups)

```mermaid
flowchart TD
    Client(["📱 Flutter-клиент"])

    subgraph HUB["SignalR Hub  /hub/chat"]
        direction TB
        G1["Группа: {userId}\n(все устройства пользователя)"]
        G2["Группа: session_{tokenHash}\n(конкретное устройство)"]
    end

    subgraph EVENTS["Типы событий"]
        direction TB
        E1["message_received\nmessage_edited\nmessage_deleted\nmessage_status\nmessage_reply\nmessage_mention"]
        E2["message_pinned\nmessage_unpinned\nchat_updated\nchat_deleted"]
        E3["poll_voted\npoll_closed"]
        E4["user_online\nsession_terminated"]
    end

    Client -->|"JWT в query: ?access_token=..."| HUB
    HUB --> G1
    HUB --> G2
    G1 --> E1
    G1 --> E2
    G1 --> E3
    G2 --> E4
```

> **Группа `{userId}`** — получает все события, связанные с контентом (сообщения, чаты, опросы).  
> **Группа `session_{tokenHash}`** — получает только системные события для конкретного устройства (принудительный выход).

---

## 2. Жизненный цикл подключения

```mermaid
sequenceDiagram
    actor Client as 📱 Клиент
    participant Hub as ChatHub
    participant DB as PostgreSQL
    participant Others as 📱 Другие клиенты

    Client->>Hub: WS connect /hub/chat?access_token=JWT

    Hub->>DB: Проверить сессию (tokenHash)
    DB-->>Hub: Сессия активна ✓

    Hub->>Hub: AddToGroup(userId)
    Hub->>Hub: AddToGroup("session_" + tokenHash)

    Hub->>DB: user.IsOnline = true
    Hub->>DB: Сохранить LastSeen

    Hub->>Others: ReceiveEvent { type: "user_online", userId, isOnline: true }

    Note over Client,Hub: Соединение установлено — клиент получает события

    Client->>Hub: WS disconnect (закрыл приложение)

    Hub->>Hub: RemoveFromGroup(userId)
    Hub->>Hub: RemoveFromGroup("session_" + tokenHash)

    Hub->>DB: user.IsOnline = false
    Hub->>DB: Сохранить LastSeen = UtcNow

    Hub->>Others: ReceiveEvent { type: "user_online", userId, isOnline: false }
```

---

## 3. Отправка сообщения

```mermaid
sequenceDiagram
    actor Sender as 📱 Отправитель
    participant API as REST API
    participant DB as PostgreSQL
    participant NS as NotificationService
    participant Members as 📱 Участники чата
    participant Replied as 📱 Автор оригинала
    participant Mentioned as 📱 Упомянутые

    Sender->>API: POST /api/chats/{id}/messages
    API->>DB: Сохранить Message + Attachment + Mentions
    DB-->>API: OK

    API->>DB: Получить всех участников чата
    API->>NS: NotifyMessageReceived(memberIds, message)
    NS->>Members: ReceiveEvent { type: "message_received", chatId, message }

    alt Сообщение является ответом (replyTo != null)
        API->>DB: Найти автора оригинального сообщения
        API->>NS: SendRawEvent(originalAuthorId, ...)
        NS->>Replied: ReceiveEvent { type: "message_reply", chatId, message }
    end

    alt Есть упоминания @user
        loop Каждый упомянутый пользователь
            API->>NS: SendMentionEvent(userId, message)
            NS->>Mentioned: ReceiveEvent { type: "message_mention", chatId, message }
        end
    end

    alt Упоминание @all (только admin/creator)
        API->>NS: SendMentionEvent(каждый участник)
        NS->>Members: ReceiveEvent { type: "message_mention", chatId, message }
    end

    API-->>Sender: 200 OK { chat }
```

---

## 4. Прочтение сообщений

```mermaid
sequenceDiagram
    actor Reader as 📱 Читатель
    participant API as REST API
    participant DB as PostgreSQL
    participant NS as NotificationService
    participant Senders as 📱 Авторы сообщений

    Reader->>API: POST /api/chats/{id}/read
    Note over Reader,API: Вызывается при открытии чата

    API->>DB: Найти все непрочитанные сообщения (senderId ≠ userId)
    DB-->>API: Список сообщений

    loop Каждое непрочитанное сообщение
        API->>DB: INSERT MessageReadStatus (messageId, userId)
        API->>DB: message.Status = "read"
    end

    API->>DB: SaveChanges()

    loop Уведомить каждого автора
        API->>NS: NotifyMessageStatus(senderId, chatId, messageId, "read")
        NS->>Senders: ReceiveEvent { type: "message_status", chatId, messageId, status: "read" }
    end

    API-->>Reader: 204 No Content
```

---

## 5. Голосование в опросе

```mermaid
sequenceDiagram
    actor Voter as 📱 Голосующий
    participant API as REST API
    participant DB as PostgreSQL
    participant NS as NotificationService
    participant Members as 📱 Участники чата

    Voter->>API: POST /api/chats/{id}/polls/{msgId}/vote
    Note right of Voter: { optionIds: [uuid] }

    API->>DB: Проверить: опрос открыт, пользователь — участник
    API->>DB: Проверить: canChangeVote / уже голосовал?
    API->>DB: Сохранить PollVote(s)
    DB-->>API: OK

    API->>DB: Пересчитать голоса → PollDto
    API->>DB: Получить участников чата

    API->>NS: SendRawEvent(каждый участник, ...)
    NS->>Members: ReceiveEvent { type: "poll_voted", chatId, messageId, poll }

    API-->>Voter: 200 OK { chat }
```

---

## 6. Автоматическое закрытие опроса (фоновая задача)

```mermaid
sequenceDiagram
    participant BG as ⏱ PollAutoCloseService
    participant DB as PostgreSQL
    participant NS as NotificationService
    participant Members as 📱 Участники чата

    loop Каждую минуту
        BG->>DB: SELECT polls WHERE Deadline <= UtcNow AND IsClosed = false
        DB-->>BG: Список истёкших опросов

        loop Каждый истёкший опрос
            BG->>DB: poll.IsClosed = true
            BG->>DB: Найти chatId через Messages
            BG->>DB: Получить участников чата
            BG->>NS: SendRawEvent(каждый участник, ...)
            NS->>Members: ReceiveEvent { type: "poll_closed", chatId, messageId, poll }
        end

        BG->>DB: SaveChanges()
    end
```

---

## 7. Принудительное завершение сессии

```mermaid
sequenceDiagram
    actor Admin as 👤 Пользователь (другое устройство)
    participant API as REST API
    participant DB as PostgreSQL
    participant NS as NotificationService
    participant Target as 📱 Завершаемое устройство

    Admin->>API: DELETE /api/auth/sessions/{sessionId}

    API->>DB: session.IsActive = false
    DB-->>API: OK

    API->>NS: SendRawEvent(сессионная группа, ...)
    Note right of NS: Группа: session_{tokenHash}
    NS->>Target: ReceiveEvent { type: "session_terminated", reason: "logged_out" }

    Note over Target: Клиент получает событие → разлогинивается

    API-->>Admin: 204 No Content
```

---

## 8. Полная карта событий

```mermaid
flowchart LR
    subgraph REST["REST API (HTTP)"]
        R1["POST /messages"]
        R2["PUT /messages/{id}"]
        R3["DELETE /messages"]
        R4["POST /messages/{id}/pin"]
        R5["POST /messages/{id}/unpin"]
        R6["POST /chats/{id}/read"]
        R7["PUT /chats/{id}/settings\nDELETE /chats/{id}"]
        R8["POST /polls/{id}/vote"]
        R9["POST /polls/{id}/close"]
        R10["DELETE /auth/sessions"]
    end

    subgraph BG["Фоновые задачи"]
        B1["PollAutoCloseService\n(каждую минуту)"]
        B2["SessionCleanupService\n(каждые 6 часов)"]
    end

    subgraph SIG["SignalR Events (→ клиент)"]
        S1["message_received"]
        S2["message_edited"]
        S3["message_deleted"]
        S4["message_reply"]
        S5["message_mention"]
        S6["message_pinned\nmessage_unpinned"]
        S7["message_status"]
        S8["chat_updated\nchat_deleted"]
        S9["poll_voted"]
        S10["poll_closed"]
        S11["user_online"]
        S12["session_terminated"]
    end

    R1 --> S1
    R1 --> S4
    R1 --> S5
    R2 --> S2
    R3 --> S3
    R4 --> S6
    R5 --> S6
    R6 --> S7
    R7 --> S8
    R8 --> S9
    R9 --> S10
    B1 --> S10
    B2 --> S12
    R10 --> S12

    Hub["ChatHub\nOnConnected\nOnDisconnected"] --> S11
```

---

## Итоговая таблица событий

| Событие | Получатель | Источник |
|---------|-----------|---------|
| `message_received` | Все участники чата | POST /messages |
| `message_edited` | Все участники чата | PUT /messages/{id} |
| `message_deleted` | Все участники чата | DELETE /messages |
| `message_reply` | Автор оригинального сообщения | POST /messages (если replyTo) |
| `message_mention` | Упомянутые пользователи | POST /messages (если mentions) |
| `message_pinned` | Все участники чата | POST /messages/{id}/pin |
| `message_unpinned` | Все участники чата | POST /messages/{id}/unpin |
| `message_status` | Автор сообщения | POST /chats/{id}/read |
| `chat_updated` | Все участники чата | PUT /chats/{id}/settings |
| `chat_deleted` | Все участники чата | DELETE /chats/{id} |
| `poll_voted` | Все участники чата | POST /polls/{id}/vote |
| `poll_closed` | Все участники чата | POST /polls/{id}/close, PollAutoCloseService |
| `user_online` | Все участники общих чатов | ChatHub.OnConnected/OnDisconnected |
| `session_terminated` | Конкретное устройство | DELETE /auth/sessions, SessionCleanupService |
