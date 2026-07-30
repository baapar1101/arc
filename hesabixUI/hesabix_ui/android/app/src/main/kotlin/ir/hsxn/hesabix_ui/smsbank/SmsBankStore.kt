package ir.hsxn.hesabix_ui.smsbank

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * SharedPreferences bridge between Flutter MethodChannel and SMS BroadcastReceiver.
 * Prefs file is dedicated so it works while Flutter is dead.
 */
object SmsBankStore {
    private const val PREFS = "hesabix_sms_bank_native_v1"
    private const val KEY_CONFIG = "config_json"
    private const val KEY_PENDING = "pending_events_json"
    private const val KEY_FINGERPRINTS = "fingerprints_json"
    private const val KEY_LAUNCH_EVENT = "launch_event_id"

    fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun saveConfig(context: Context, configJson: String) {
        prefs(context).edit().putString(KEY_CONFIG, configJson).apply()
    }

    fun getConfig(context: Context): JSONObject {
        val raw = prefs(context).getString(KEY_CONFIG, null) ?: return JSONObject()
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            JSONObject()
        }
    }

    fun isEnabled(context: Context): Boolean = getConfig(context).optBoolean("enabled", false)

    fun interruptMode(context: Context): String =
        getConfig(context).optString("interrupt_mode", "notification")

    fun minAmount(context: Context): Double = getConfig(context).optDouble("min_amount", 0.0)

    fun vibrate(context: Context): Boolean = getConfig(context).optBoolean("vibrate", true)

    fun quietStartHour(context: Context): Int? {
        val c = getConfig(context)
        return if (c.has("quiet_start_hour") && !c.isNull("quiet_start_hour")) {
            c.optInt("quiet_start_hour")
        } else null
    }

    fun quietEndHour(context: Context): Int? {
        val c = getConfig(context)
        return if (c.has("quiet_end_hour") && !c.isNull("quiet_end_hour")) {
            c.optInt("quiet_end_hour")
        } else null
    }

    fun isInQuietHours(context: Context): Boolean {
        val start = quietStartHour(context) ?: return false
        val end = quietEndHour(context) ?: return false
        val h = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
        if (start == end) return true
        return if (start < end) h >= start && h < end else h >= start || h < end
    }

    fun patterns(context: Context): JSONArray {
        return getConfig(context).optJSONArray("patterns") ?: JSONArray()
    }

    fun appendPending(context: Context, event: JSONObject) {
        val arr = pendingArray(context)
        // de-dupe by id / fingerprint
        val id = event.optString("id")
        val fp = event.optString("fingerprint")
        val next = JSONArray()
        for (i in 0 until arr.length()) {
            val item = arr.optJSONObject(i) ?: continue
            if (item.optString("id") == id || item.optString("fingerprint") == fp) continue
            next.put(item)
        }
        next.put(event)
        // keep last 50
        val trimmed = JSONArray()
        val start = (next.length() - 50).coerceAtLeast(0)
        for (i in start until next.length()) trimmed.put(next.get(i))
        prefs(context).edit().putString(KEY_PENDING, trimmed.toString()).apply()
    }

    fun pendingArray(context: Context): JSONArray {
        val raw = prefs(context).getString(KEY_PENDING, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    fun drainPending(context: Context): JSONArray {
        val arr = pendingArray(context)
        prefs(context).edit().putString(KEY_PENDING, JSONArray().toString()).apply()
        return arr
    }

    fun updateEventStatus(context: Context, eventId: String, status: String) {
        val arr = pendingArray(context)
        val next = JSONArray()
        for (i in 0 until arr.length()) {
            val item = arr.optJSONObject(i) ?: continue
            if (item.optString("id") == eventId) {
                item.put("status", status)
            }
            next.put(item)
        }
        prefs(context).edit().putString(KEY_PENDING, next.toString()).apply()
    }

    fun rememberFingerprint(context: Context, fingerprint: String): Boolean {
        val arr = try {
            JSONArray(prefs(context).getString(KEY_FINGERPRINTS, "[]"))
        } catch (_: Exception) {
            JSONArray()
        }
        for (i in 0 until arr.length()) {
            if (arr.optString(i) == fingerprint) return true
        }
        val next = JSONArray()
        next.put(fingerprint)
        for (i in 0 until arr.length().coerceAtMost(199)) {
            next.put(arr.get(i))
        }
        prefs(context).edit().putString(KEY_FINGERPRINTS, next.toString()).apply()
        return false
    }

    fun setLaunchEventId(context: Context, id: String?) {
        prefs(context).edit().putString(KEY_LAUNCH_EVENT, id).apply()
    }

    fun getLaunchEventId(context: Context): String? =
        prefs(context).getString(KEY_LAUNCH_EVENT, null)

    fun clearLaunchEventId(context: Context) {
        prefs(context).edit().remove(KEY_LAUNCH_EVENT).apply()
    }
}
