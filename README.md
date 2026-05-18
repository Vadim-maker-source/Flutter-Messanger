# Flutter Messenger

Мобильное приложение мессенджера на Flutter, работающее с API Next.js.

## Структура проекта

```
lib/
├── models/           # Модели данных
│   ├── user.dart
│   ├── chat.dart
│   └── message.dart
├── services/         # API сервисы
│   └── api_service.dart
├── screens/          # Экраны приложения
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── home_screen.dart
│   ├── chat_screen.dart
│   └── profile_screen.dart
└── main.dart
```

## API Endpoints

Приложение использует следующие эндпоинты (базовый URL: `http://localhost:3000/api/mobile`):

- `POST /auth/login` - Вход
- `POST /auth/register` - Регистрация
- `GET /chats` - Получить список чатов
- `GET /messages/:chatId` - Получить сообщения чата
- `POST /messages/send` - Отправить сообщение
- `GET /profile` - Получить профиль пользователя

## Установка и запуск

1. Установите зависимости:
```bash
flutter pub get
```

2. Запустите Next.js backend на порту 3000:
```bash
cd path/to/nextjs/project
npm run dev
```

3. Запустите Flutter приложение:
```bash
flutter run
```

## Смена API URL

Для использования другого URL (не localhost), измените константу `baseUrl` в файле `lib/services/api_service.dart`:

```dart
static const String baseUrl = 'https://your-api-url.com/api/mobile';
```

## Функционал

- ✅ Аутентификация (вход/регистрация)
- ✅ Список чатов
- ✅ Просмотр сообщений
- ✅ Отправка сообщений
- ✅ Профиль пользователя
- ✅ Выход из аккаунта

## Требования

- Flutter SDK 3.11.5+
- Dart 3.0+
- Next.js backend запущен на localhost:3000
