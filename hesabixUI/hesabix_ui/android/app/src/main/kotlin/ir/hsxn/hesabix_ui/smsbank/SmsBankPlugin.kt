package ir.hsxn.hesabix_ui.smsbank

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * MethodChannel bridge: Flutter syncs config; native pushes SMS events when engine is warm.
 */
object SmsBankPlugin {
    const val CHANNEL = "ir.hsxn.hesabix_ui/sms_bank"

    @Volatile
    private var channel: MethodChannel? = null

    fun register(flutterEngine: FlutterEngine, activity: android.app.Activity) {
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            val context = activity.applicationContext
            when (call.method) {
                "syncConfig" -> {
                    try {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val json = mapToJson(args)
                        SmsBankStore.saveConfig(context, json.toString())
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SYNC", e.message, null)
                    }
                }
                "drainPendingEvents" -> {
                    val arr = SmsBankStore.drainPending(context)
                    val list = mutableListOf<Map<String, Any?>>()
                    for (i in 0 until arr.length()) {
                        val obj = arr.optJSONObject(i) ?: continue
                        list.add(jsonToMap(obj))
                    }
                    result.success(list)
                }
                "takePendingEvent" -> {
                    val args = call.arguments as? Map<*, *>
                    val id = args?.get("event_id")?.toString()
                    if (id.isNullOrEmpty()) {
                        result.error("ARG", "event_id required", null)
                    } else {
                        val obj = SmsBankStore.takePendingEvent(context, id)
                        result.success(obj?.let { jsonToMap(it) })
                    }
                }
                "updateEventStatus" -> {
                    val args = call.arguments as? Map<*, *>
                    val id = args?.get("event_id")?.toString()
                    val status = args?.get("status")?.toString() ?: "pending"
                    if (id.isNullOrEmpty()) {
                        result.error("ARG", "event_id required", null)
                    } else {
                        SmsBankStore.updateEventStatus(context, id, status)
                        if (status == "dismissed" || status == "registered") {
                            SmsBankNotifier.cancel(context, id)
                        }
                        result.success(true)
                    }
                }
                "showNotification" -> {
                    try {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val event = mapToJson(args)
                        SmsBankNotifier.show(context, event, SmsBankStore.vibrate(context))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIF", e.message, null)
                    }
                }
                "getLaunchEventId" -> {
                    result.success(SmsBankStore.getLaunchEventId(context))
                }
                "clearLaunchEventId" -> {
                    SmsBankStore.clearLaunchEventId(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun consumeIntent(context: android.content.Context, intent: Intent?) {
        if (intent == null) return
        val eventId = intent.getStringExtra(SmsBankNotifier.EXTRA_EVENT_ID)
            ?: intent.data?.takeIf {
                it.scheme == "hesabix" && it.host == "sms-bank"
            }?.getQueryParameter("id")
        if (eventId.isNullOrEmpty()) return
        SmsBankStore.setLaunchEventId(context, eventId)
        emitNotificationAction(eventId, intent.getStringExtra(SmsBankNotifier.EXTRA_ACTION) ?: "open")
    }

    fun emitSmsEvent(event: JSONObject) {
        try {
            channel?.invokeMethod(
                "onSmsReceived",
                mapOf(
                    "event" to jsonToMap(event),
                    "sender" to event.optString("sender"),
                    "body" to event.optString("body"),
                ),
            )
        } catch (_: Exception) {
        }
    }

    fun emitNotificationAction(eventId: String, action: String) {
        try {
            channel?.invokeMethod(
                "onNotificationAction",
                mapOf(
                    "event_id" to eventId,
                    "action" to action,
                ),
            )
        } catch (_: Exception) {
        }
    }

    private fun mapToJson(map: Map<*, *>): JSONObject {
        val json = JSONObject()
        for ((k, v) in map) {
            if (k == null) continue
            json.put(k.toString(), toJsonValue(v))
        }
        return json
    }

    private fun toJsonValue(v: Any?): Any {
        return when (v) {
            null -> JSONObject.NULL
            is Map<*, *> -> mapToJson(v)
            is List<*> -> {
                val arr = JSONArray()
                for (item in v) arr.put(toJsonValue(item))
                arr
            }
            is Boolean, is Int, is Long, is Double, is String -> v
            is Float -> v.toDouble()
            is Number -> v.toDouble()
            else -> v.toString()
        }
    }

    private fun jsonToMap(obj: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val v = obj.get(key)
            map[key] = when (v) {
                JSONObject.NULL -> null
                is JSONObject -> jsonToMap(v)
                is JSONArray -> {
                    val list = mutableListOf<Any?>()
                    for (i in 0 until v.length()) {
                        val item = v.get(i)
                        list.add(
                            when (item) {
                                is JSONObject -> jsonToMap(item)
                                JSONObject.NULL -> null
                                else -> item
                            },
                        )
                    }
                    list
                }
                else -> v
            }
        }
        return map
    }
}
