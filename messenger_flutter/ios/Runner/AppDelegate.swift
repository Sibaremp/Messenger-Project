import Flutter
import UIKit
import CoreTelephony

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupSimChannel(binaryMessenger: engineBridge.binaryMessenger)
  }

  // ── SIM / Carrier channel ────────────────────────────────────────────────────
  private func setupSimChannel(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "caspian_college_messenger/sim_info",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getSimCards" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.readCarriers() ?? [])
    }
  }

  /// На iOS номер телефона недоступен через публичный API.
  /// Возвращаем только данные оператора (carrierName, countryIso).
  /// Для dual-SIM (iOS 12+) используем serviceSubscriberCellularProviders.
  private func readCarriers() -> [[String: Any?]] {
    let info = CTTelephonyNetworkInfo()
    var cards: [[String: Any?]] = []

    if #available(iOS 12.0, *) {
      // Dual-SIM: словарь serviceKey → CTCarrier
      if let providers = info.serviceSubscriberCellularProviders {
        // Сортируем по ключу для стабильного порядка
        let sorted = providers.sorted { $0.key < $1.key }
        for (index, (_, carrier)) in sorted.enumerated() {
          cards.append(carrierMap(carrier: carrier, slotIndex: index))
        }
      }
    } else {
      // iOS < 12: только одна SIM
      if let carrier = info.subscriberCellularProvider {
        cards.append(carrierMap(carrier: carrier, slotIndex: 0))
      }
    }

    return cards
  }

  private func carrierMap(carrier: CTCarrier, slotIndex: Int) -> [String: Any?] {
    return [
      "slotIndex":   slotIndex,
      "phoneNumber": nil,          // iOS не предоставляет номер через публичный API
      "carrierName": carrier.carrierName,
      "countryIso":  carrier.isoCountryCode,
    ]
  }
}
