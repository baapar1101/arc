package ir.hsxn.hesabix_ui.smsbank

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * Event-driven SMS receiver — works even when the Flutter UI process is killed.
 */
class SmsBankReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!SmsBankStore.isEnabled(context)) return

        try {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
            if (messages.isEmpty()) return
            val sender = messages.firstOrNull()?.displayOriginatingAddress ?: ""
            val body = messages.joinToString(separator = "") { it.messageBody ?: "" }
            if (body.isBlank()) return

            val receivedAt = System.currentTimeMillis()
            val fingerprint = SmsBankMatcher.fingerprint(sender, body, receivedAt)
            if (SmsBankStore.rememberFingerprint(context, fingerprint)) return

            val patterns = SmsBankStore.patterns(context)
            if (patterns.length() == 0) return

            val config = SmsBankStore.getConfig(context)
            val activeBiz = if (config.has("active_business_id") && !config.isNull("active_business_id")) {
                config.optInt("active_business_id")
            } else null

            val match = SmsBankMatcher.match(sender, body, patterns, activeBiz) ?: return
            if (match.optDouble("confidence", 0.0) < SmsBankMatcher.MIN_ACCEPT_CONFIDENCE) return

            val amount = match.optDouble("amount", 0.0)
            if (amount < SmsBankStore.minAmount(context)) return

            val event = SmsBankMatcher.buildEvent(sender, body, receivedAt, match, activeBiz)
            event.put("fingerprint", fingerprint)
            SmsBankStore.appendPending(context, event)

            val quiet = SmsBankStore.isInQuietHours(context)
            // Both interrupt modes show a notification; auto_open is honored in Flutter after unlock.
            if (!quiet) {
                SmsBankNotifier.show(context, event, SmsBankStore.vibrate(context))
            }

            SmsBankPlugin.emitSmsEvent(event)
            Log.i(TAG, "SMS bank match amount=${event.optDouble("amount")} id=${event.optString("id")}")
        } catch (e: Exception) {
            Log.e(TAG, "SMS bank receive failed", e)
        }
    }

    companion object {
        private const val TAG = "SmsBankReceiver"
    }
}

class SmsBankActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        val eventId = intent.getStringExtra(SmsBankNotifier.EXTRA_EVENT_ID) ?: return
        when (intent.action) {
            SmsBankNotifier.ACTION_DISMISS -> {
                SmsBankStore.updateEventStatus(context, eventId, "dismissed")
                SmsBankNotifier.cancel(context, eventId)
                SmsBankPlugin.emitNotificationAction(eventId, "dismiss")
            }
        }
    }
}
