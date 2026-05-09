package com.example.caspian_college_messenger

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "caspian_college_messenger/sim_info"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSimCards" -> result.success(readSimCards())
                    else          -> result.notImplemented()
                }
            }
    }

    // ── Чтение SIM-карт через SubscriptionManager ────────────────────────────
    private fun readSimCards(): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()

        // READ_PHONE_STATE — обязательное, без него API недоступно
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED) return list

        val subManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1)
            getSystemService(TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
        else null

        if (subManager == null) {
            // Fallback: только одна SIM через TelephonyManager
            val tm = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager ?: return list
            list.add(buildSimMap(slotIndex = 0, phone = null, carrier = tm.networkOperatorName, country = tm.networkCountryIso))
            return list
        }

        val subs: List<SubscriptionInfo>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1)
            subManager.activeSubscriptionInfoList
        else null

        if (subs.isNullOrEmpty()) return list

        // READ_PHONE_NUMBERS — нужно для номера (Android 8+), иначе используем sub.number
        val canReadNumbers = ContextCompat.checkSelfPermission(
            this, Manifest.permission.READ_PHONE_NUMBERS
        ) == PackageManager.PERMISSION_GRANTED

        for (sub in subs) {
            val rawNumber: String? = if (canReadNumbers || Build.VERSION.SDK_INT < Build.VERSION_CODES.O)
                sub.number?.takeIf { it.isNotBlank() }
            else null

            list.add(buildSimMap(
                slotIndex = sub.simSlotIndex,
                phone     = rawNumber,
                carrier   = sub.carrierName?.toString(),
                country   = sub.countryIso,
            ))
        }

        return list
    }

    private fun buildSimMap(
        slotIndex: Int,
        phone: String?,
        carrier: String?,
        country: String?,
    ): Map<String, Any?> = mapOf(
        "slotIndex"   to slotIndex,
        "phoneNumber" to phone,
        "carrierName" to carrier,
        "countryIso"  to country,
    )
}
