package ir.hsxn.hesabix_ui.smsbank

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import ir.hsxn.hesabix_ui.MainActivity
import ir.hsxn.hesabix_ui.R
import org.json.JSONObject
import java.text.NumberFormat
import java.util.Locale

object SmsBankNotifier {
    const val CHANNEL_ID = "hesabix_sms_bank_v1"
    const val ACTION_OPEN = "ir.hsxn.hesabix_ui.SMS_BANK_OPEN"
    const val ACTION_DISMISS = "ir.hsxn.hesabix_ui.SMS_BANK_DISMISS"
    const val EXTRA_EVENT_ID = "sms_bank_event_id"
    const val EXTRA_ACTION = "sms_bank_action"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "تراکنش پیامک بانکی",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "اعلان شناسایی تراکنش از پیامک بانک"
            enableVibration(true)
        }
        mgr.createNotificationChannel(channel)
    }

    fun show(context: Context, event: JSONObject, vibrate: Boolean) {
        ensureChannel(context)
        val eventId = event.optString("id")
        if (eventId.isEmpty()) return

        val direction = event.optString("direction", "unknown")
        val dirLabel = when (direction) {
            "credit" -> "واریز"
            "debit" -> "برداشت"
            else -> "تراکنش"
        }
        val amount = event.optDouble("amount", 0.0)
        val amountStr = NumberFormat.getNumberInstance(Locale.US).format(amount.toLong())
        val account = event.optString("bank_account_name")
            .ifEmpty { event.optString("account_mask") }
            .ifEmpty { event.optString("pattern_name") }
        val needsChoice = event.optBoolean("needs_business_choice", false)
        val bizName = event.optString("business_name")

        val title = if (needsChoice) {
            "تراکنش بانکی — انتخاب کسب‌وکار"
        } else {
            "تراکنش بانکی شناسایی شد"
        }
        var body = "$dirLabel $amountStr ریال"
        if (account.isNotEmpty()) body += " · $account"
        if (bizName.isNotEmpty()) body += " · $bizName"
        else if (needsChoice) body += " · چند کسب‌وکار محتمل"

        // Do not set intent.data — Flutter GoRouter would map hesabix://sms-bank/capture
        // to /capture (no route → 404). Event id is delivered via EXTRA_EVENT_ID.
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_EVENT_ID, eventId)
            putExtra(EXTRA_ACTION, "open")
        }
        val openPending = PendingIntent.getActivity(
            context,
            eventId.hashCode(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val dismissIntent = Intent(context, SmsBankActionReceiver::class.java).apply {
            action = ACTION_DISMISS
            putExtra(EXTRA_EVENT_ID, eventId)
        }
        val dismissPending = PendingIntent.getBroadcast(
            context,
            eventId.hashCode() + 1,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notifId = (eventId.hashCode() and 0x7fffffff)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_hesabix)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(openPending)
            .addAction(0, "ثبت سریع", openPending)
            .addAction(0, "نادیده", dismissPending)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)

        if (vibrate) {
            builder.setDefaults(NotificationCompat.DEFAULT_ALL)
        }

        try {
            NotificationManagerCompat.from(context).notify(notifId, builder.build())
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS may be missing on Android 13+
        }
    }

    fun cancel(context: Context, eventId: String) {
        val notifId = (eventId.hashCode() and 0x7fffffff)
        NotificationManagerCompat.from(context).cancel(notifId)
    }
}
