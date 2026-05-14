import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// Реализует схему шифрования сообщений «клиент ↔ сервер»:
///
/// 1. Клиент генерирует пару ключей X25519.
/// 2. Клиент отправляет свой публичный ключ на `POST /api/key-exchange`.
/// 3. Сервер возвращает свой публичный ключ.
/// 4. Обе стороны вычисляют общий секрет X25519 и выводят 256-битный ключ AES
///    через HKDF-SHA256.
/// 5. Весь текст сообщений шифруется AES-256-GCM.
///
/// Формат зашифрованного текста: `ENC:<base64(nonce)>.<base64(ciphertext‖mac)>`
///
/// Если обмен ключами ещё не выполнен или не поддерживается сервером,
/// методы прозрачно возвращают исходный текст (graceful degradation).
class EncryptionService {
  EncryptionService._();

  static final instance = EncryptionService._();

  // ── Константы протокола ────────────────────────────────────────────────────
  static const _prefix     = 'ENC:';
  static const _apiPath    = '/api/key-exchange';
  static const _hkdfInfo   = 'CaspianMessenger-v1';
  static const _hkdfSalt   = 'CaspianMessenger-salt-2024';

  // ── Крипто-алгоритмы (из пакета `cryptography`) ───────────────────────────
  final _x25519 = X25519();
  final _aes    = AesGcm.with256bits();   // AES-256-GCM, nonce 12 байт, тег 16 байт

  // ── Состояние ──────────────────────────────────────────────────────────────
  SimpleKeyPair? _keyPair;
  SecretKey?     _sharedKey;

  /// `true`, когда обмен ключами завершён и шифрование доступно.
  bool get isReady => _sharedKey != null;

  // ── Публичный API ──────────────────────────────────────────────────────────

  /// Генерирует пару ключей X25519, выполняет обмен с сервером и выводит
  /// общий AES-256 ключ через HKDF-SHA256.
  ///
  /// Вызывать после каждого успешного подключения SignalR.
  /// При ошибке (сеть, сервер не поддерживает) мягко деградирует — текст
  /// будет передаваться в открытом виде.
  Future<void> initAndExchange(
    String baseUrl,
    Map<String, String> authHeaders,
  ) async {
    _sharedKey = null;
    _keyPair   = null;

    try {
      // 1. Генерируем пару ключей
      _keyPair = await _x25519.newKeyPair();
      final pubKey    = await _keyPair!.extractPublicKey();
      final clientB64 = base64Encode(pubKey.bytes);

      // 2. Отправляем публичный ключ серверу
      final resp = await http.post(
        Uri.parse('$baseUrl$_apiPath'),
        headers: {
          ...authHeaders,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'clientPublicKey': clientB64}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return; // сервер не поддерживает

      final serverB64 = (jsonDecode(resp.body)
              as Map<String, dynamic>)['serverPublicKey'] as String;

      // 3. Вычисляем общий секрет X25519
      final serverPub = SimplePublicKey(
        base64Decode(serverB64),
        type: KeyPairType.x25519,
      );
      final rawShared = await _x25519.sharedSecretKey(
        keyPair: _keyPair!,
        remotePublicKey: serverPub,
      );

      // 4. Выводим 256-битный ключ через HKDF-SHA256
      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
      _sharedKey = await hkdf.deriveKey(
        secretKey: rawShared,
        info:  utf8.encode(_hkdfInfo),
        nonce: utf8.encode(_hkdfSalt),
      );
    } catch (_) {
      // Любая ошибка → мягкая деградация (plaintext)
      _sharedKey = null;
      _keyPair   = null;
    }
  }

  /// Сбрасывает состояние (при выходе / переподключении).
  void reset() {
    _sharedKey = null;
    _keyPair   = null;
  }

  /// Шифрует [text] алгоритмом AES-256-GCM.
  ///
  /// Возвращает `ENC:<base64(nonce)>.<base64(ciphertext‖mac)>`.
  /// Если ключ не готов — возвращает исходный [text].
  Future<String> encryptText(String text) async {
    if (!isReady || text.isEmpty) return text;
    try {
      final box = await _aes.encrypt(
        utf8.encode(text),
        secretKey: _sharedKey!,
      );
      final nonce   = base64Encode(Uint8List.fromList(box.nonce));
      final payload = base64Encode(
        Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
      );
      return '$_prefix$nonce.$payload';
    } catch (_) {
      return text;
    }
  }

  /// Расшифровывает [text], если он начинается с префикса `ENC:`.
  /// В противном случае (plaintext, нет ключа) возвращает текст как есть.
  Future<String> decryptText(String text) async {
    if (!isReady || !text.startsWith(_prefix)) return text;
    try {
      final body = text.substring(_prefix.length);
      final dot  = body.indexOf('.');
      if (dot < 0) return text;

      final nonce    = base64Decode(body.substring(0, dot));
      final combined = base64Decode(body.substring(dot + 1));

      const macLen = 16; // GCM tag
      if (combined.length < macLen) return text;

      final ct  = combined.sublist(0, combined.length - macLen);
      final mac = Mac(combined.sublist(combined.length - macLen));

      final plain = await _aes.decrypt(
        SecretBox(ct, nonce: nonce, mac: mac),
        secretKey: _sharedKey!,
      );
      return utf8.decode(plain);
    } catch (_) {
      return text; // расшифровка не удалась — вернём как есть
    }
  }
}
