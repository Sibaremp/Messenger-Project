import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

// ─── Модель одной SIM-карты ───────────────────────────────────────────────────

class SimCard {
  final int slotIndex;
  final String? phoneNumber;
  final String? carrierName;
  final String? countryIso;

  const SimCard({
    required this.slotIndex,
    this.phoneNumber,
    this.carrierName,
    this.countryIso,
  });

  /// Отображаемое название слота (SIM 1 / SIM 2)
  String get slotLabel => 'SIM ${slotIndex + 1}';

  /// Краткое описание для UI (оператор + страна)
  String get displayInfo {
    final parts = <String>[];
    if (carrierName?.isNotEmpty == true) parts.add(carrierName!);
    if (countryIso?.isNotEmpty == true) parts.add(countryIso!.toUpperCase());
    return parts.isEmpty ? 'Неизвестный оператор' : parts.join(' · ');
  }
}

// ─── Результат операции ───────────────────────────────────────────────────────

enum SimResult { success, permissionDenied, permissionPermanentlyDenied, unsupported, noSimFound, error }

class SimServiceResult {
  final SimResult status;
  final List<SimCard> simCards;
  final String? errorMessage;

  const SimServiceResult({
    required this.status,
    this.simCards = const [],
    this.errorMessage,
  });

  bool get isSuccess => status == SimResult.success;
}

// ─── Сервис ───────────────────────────────────────────────────────────────────

class SimService {
  static const _channel = MethodChannel('caspian_college_messenger/sim_info');

  /// SIM-функция доступна на Android и iOS (не Web, не Desktop).
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// На Android SIM возвращает реальный номер телефона.
  /// На iOS — только данные оператора (Apple не предоставляет номер).
  static bool get canReadNumber => !kIsWeb && Platform.isAndroid;

  /// Запрашивает разрешения и возвращает список доступных SIM-карт.
  ///
  /// Возможные статусы результата:
  /// - [SimResult.success]                  — список получен (номера могут быть null на iOS)
  /// - [SimResult.permissionDenied]         — пользователь отклонил запрос
  /// - [SimResult.permissionPermanentlyDenied] — нужно открыть настройки
  /// - [SimResult.unsupported]              — платформа не поддерживается
  /// - [SimResult.noSimFound]               — SIM не вставлена / не определена
  /// - [SimResult.error]                    — нативная ошибка
  static Future<SimServiceResult> fetchSimCards() async {
    if (!isSupported) {
      return const SimServiceResult(status: SimResult.unsupported);
    }

    // ── Запрос прав (только Android — iOS не требует разрешения для carrier info) ─
    if (Platform.isAndroid) {
      final phoneState = await Permission.phone.request();
      if (phoneState.isPermanentlyDenied) {
        return const SimServiceResult(status: SimResult.permissionPermanentlyDenied);
      }
      if (!phoneState.isGranted) {
        return const SimServiceResult(status: SimResult.permissionDenied);
      }
    }

    // ── Вызов нативного кода ─────────────────────────────────────────────────
    try {
      final raw = await _channel.invokeMethod<List>('getSimCards');
      if (raw == null || raw.isEmpty) {
        return const SimServiceResult(status: SimResult.noSimFound);
      }

      final cards = raw
          .cast<Map>()
          .map((m) => SimCard(
                slotIndex:   (m['slotIndex']   as int?)  ?? 0,
                phoneNumber: m['phoneNumber']  as String?,
                carrierName: m['carrierName']  as String?,
                countryIso:  m['countryIso']   as String?,
              ))
          .toList();

      return SimServiceResult(status: SimResult.success, simCards: cards);
    } on PlatformException catch (e) {
      return SimServiceResult(status: SimResult.error, errorMessage: e.message);
    }
  }

  /// Открывает системные настройки разрешений приложения.
  static Future<void> openSettings() => openAppSettings();
}
