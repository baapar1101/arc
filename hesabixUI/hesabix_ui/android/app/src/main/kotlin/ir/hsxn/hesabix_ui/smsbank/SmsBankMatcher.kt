package ir.hsxn.hesabix_ui.smsbank

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.regex.Matcher
import java.util.regex.Pattern
import kotlin.math.abs

/**
 * Lightweight Kotlin port of the Dart SmsBankPatternEngine for when Flutter is dead.
 * Uses numbered capture groups (API 21+ safe) instead of named groups.
 */
object SmsBankMatcher {
    const val MIN_ACCEPT_CONFIDENCE = 0.72
    private const val HEURISTIC_CONFIDENCE_WITH_SENDER_HINT = 0.78
    private const val HEURISTIC_CONFIDENCE_BANK_SENDER_ONLY = 0.72
    private const val MIN_BODY_HINT_LENGTH = 5

    private val commonBankSenderHints = listOf(
        "بانک تجارت", "tejarat", "تجارت",
        "بانک ملت", "bmellat", "mellat", "ملت",
        "بانک ملی", "bmi", "melli", "ملی",
        "بانک صادرات", "bsi", "saderat", "صادرات",
        "پاسارگاد", "pasargad",
        "پارسیان", "parsian",
        "سامان", "saman",
        "اقتصاد نوین", "enbank", "آوای نوین",
        "توسعه تعاون", "ttbank",
        "کشاورزی", "bki",
        "مسکن", "maskan",
        "رفاه", "refah",
        "سینا", "sina",
        "آینده", "ayandeh",
        "شهر", "shahr",
        "بانک دی", "day",
        "رسالت", "resalat",
        "گردشگری", "tourism",
        "ایران زمین", "izbank",
        "کارآفرین", "karafarin",
        "مهر", "mebank",
        "سپه", "banksepah",
        "postbank", "پست بانک",
        "blu", "blubank",
        "bank",
    )

    private val placeholderBodies = mapOf(
        "amount" to "[+\\-]?\\d{1,3}(?:[,\\u066C\\u066B٫٬]\\d{3})*(?:[.,]\\d+)?|[+\\-]?\\d+(?:[.,]\\d+)?",
        "amount_signed" to "[+\\-]?\\d{1,3}(?:[,\\u066C\\u066B٫٬]\\d{3})*(?:[.,]\\d+)?\\s*-?|-?\\s*[+\\-]?\\d{1,3}(?:[,\\u066C\\u066B٫٬]\\d{3})*(?:[.,]\\d+)?",
        "balance" to "[+\\-]?\\d{1,3}(?:[,\\u066C\\u066B٫٬]\\d{3})*(?:[.,]\\d+)?|[+\\-]?\\d+(?:[.,]\\d+)?",
        "account" to "[\\d×xX*\\-.\\u00D7]+",
        "direction" to "برداشت(?:\\s*از)?|واریز|واريز|برداشت|واریزی|واريزي|debit|credit|withdraw|deposit",
        "date" to "\\d{2,4}[/\\-_.]\\d{1,2}[/\\-_.]\\d{1,4}|\\d{1,2}[/\\-_.]\\d{1,2}",
        "time" to "\\d{1,2}:\\d{2}(?::\\d{2})?",
        "channel" to "[^\\s\\n]+",
        "ref" to "[\\w.\\-×xX*]+",
        "any" to "[\\s\\S]*?",
    )

    private data class Compiled(val pattern: Pattern, val groups: Map<String, Int>)

    fun match(
        sender: String,
        body: String,
        patterns: JSONArray,
        preferredBusinessId: Int? = null,
        ambiguityDelta: Double = 0.12,
    ): JSONObject? {
        // Align with Flutter: no patterns → no match (do not fall into heuristic alone).
        if (patterns.length() == 0) return null

        val normBody = normalize(body)
        val normSender = normalize(sender)
        val results = mutableListOf<JSONObject>()

        for (i in 0 until patterns.length()) {
            val p = patterns.optJSONObject(i) ?: continue
            if (!p.optBoolean("enabled", true)) continue
            val hints = p.optJSONArray("sender_hints") ?: JSONArray()
            if (hints.length() == 0) continue

            val patternId = p.optString("id", "")
            val requireSender = isGenericSeedId(patternId)
            val hintsOk = senderHintsAllowMatch(normSender, normBody, hints, requireSender)
            if (!hintsOk) continue
            if (requireSender && !senderLooksLikeBank(normSender)) continue

            val template = p.optString("template", "").trim()
            if (template.isEmpty()) continue

            val result = matchTemplate(normBody, p, template) ?: continue
            applyScoreBonuses(result, p, hintsMatched = true)
            if (result.optDouble("confidence", 0.0) < MIN_ACCEPT_CONFIDENCE) continue
            results.add(result)
        }

        if (results.isEmpty()) {
            val h = heuristic(normBody, normSender, patterns) ?: return null
            if (h.optDouble("confidence", 0.0) < MIN_ACCEPT_CONFIDENCE) return null
            results.add(h)
        }

        results.sortByDescending { it.optDouble("confidence", 0.0) }
        val top = results.first()
        val topScore = top.optDouble("confidence", 0.0)

        val byBusiness = linkedMapOf<Int, JSONObject>()
        for (r in results) {
            if (r.optDouble("confidence", 0.0) < topScore - ambiguityDelta) continue
            if (!r.has("business_id") || r.isNull("business_id")) continue
            val bid = r.optInt("business_id")
            val existing = byBusiness[bid]
            if (existing == null || r.optDouble("confidence", 0.0) > existing.optDouble("confidence", 0.0)) {
                byBusiness[bid] = r
            }
        }

        if (byBusiness.size >= 2) {
            val candidates = JSONArray()
            for ((_, r) in byBusiness) {
                candidates.put(candidateFromMatch(r))
            }
            val ambiguous = JSONObject(top.toString())
            ambiguous.put("needs_business_choice", true)
            ambiguous.put("candidates", candidates)
            ambiguous.remove("business_id")
            return ambiguous
        }

        if (byBusiness.size == 1) {
            val chosen = byBusiness.values.first()
            chosen.put("needs_business_choice", false)
            chosen.put("candidates", JSONArray())
            return chosen
        }

        if (preferredBusinessId != null) {
            top.put("business_id", preferredBusinessId)
        }
        top.put("needs_business_choice", !top.has("business_id") || top.isNull("business_id"))
        top.put("candidates", JSONArray())
        return top
    }

    private fun isGenericSeedId(patternId: String): Boolean =
        patternId.startsWith("seed_generic")

    private fun senderLooksLikeBank(sender: String): Boolean {
        val s = normalize(sender).lowercase()
        if (s.isEmpty()) return false
        for (token in commonBankSenderHints) {
            val t = normalize(token).lowercase()
            if (t.isNotEmpty() && s.contains(t)) return true
        }
        return false
    }

    private fun hintMatchesSender(sender: String, hints: JSONArray): Boolean {
        val hay = normalize(sender).lowercase()
        for (i in 0 until hints.length()) {
            val needle = normalize(hints.optString(i)).lowercase()
            if (needle.isNotEmpty() && hay.contains(needle)) return true
        }
        return false
    }

    private fun hintMatchesBody(body: String, hints: JSONArray): Boolean {
        val hay = normalize(body).lowercase()
        for (i in 0 until hints.length()) {
            val needle = normalize(hints.optString(i)).lowercase()
            if (needle.length >= MIN_BODY_HINT_LENGTH && hay.contains(needle)) return true
        }
        return false
    }

    private fun senderHintsAllowMatch(
        sender: String,
        body: String,
        hints: JSONArray,
        requireSenderForGeneric: Boolean,
    ): Boolean {
        if (hints.length() == 0) return false
        if (hintMatchesSender(sender, hints)) return true
        if (requireSenderForGeneric) return false
        return hintMatchesBody(body, hints)
    }

    private fun bodyHasStrongBankStructure(body: String): Boolean {
        val hasDirection = Regex("برداشت|واریز|واريز").containsMatchIn(body)
        val hasBalance = Regex("مانده|موجودی|موجودي").containsMatchIn(body)
        val hasAmountCue = Regex("مبلغ|ریال|ريال").containsMatchIn(body)
        return hasDirection && hasBalance && hasAmountCue
    }

    private fun applyScoreBonuses(result: JSONObject, pattern: JSONObject, hintsMatched: Boolean) {
        var score = result.optDouble("confidence", 0.0)
        if (pattern.has("bank_account_id") && !pattern.isNull("bank_account_id")) score += 0.18
        if (pattern.has("business_id") && !pattern.isNull("business_id")) score += 0.10
        val hints = pattern.optJSONArray("sender_hints")
        if (hintsMatched && hints != null && hints.length() > 0) score += 0.06
        if (!pattern.optBoolean("is_seed", false)) score += 0.04
        result.put("confidence", score)
        pattern.optString("business_name", "").takeIf { it.isNotEmpty() }?.let {
            result.put("business_name", it)
        }
    }

    private fun candidateFromMatch(r: JSONObject): JSONObject {
        val c = JSONObject()
        c.put("business_id", r.optInt("business_id"))
        r.optString("business_name", "").takeIf { it.isNotEmpty() }?.let { c.put("business_name", it) }
        r.optString("pattern_id", "").takeIf { it.isNotEmpty() }?.let { c.put("pattern_id", it) }
        r.optString("pattern_name", "").takeIf { it.isNotEmpty() }?.let { c.put("pattern_name", it) }
        if (r.has("bank_account_id")) c.put("bank_account_id", r.optInt("bank_account_id"))
        r.optString("bank_account_name", "").takeIf { it.isNotEmpty() }?.let { c.put("bank_account_name", it) }
        c.put("confidence", r.optDouble("confidence", 0.0))
        return c
    }

    private fun normalize(input: String): String {
        var s = toEnglishDigits(input)
        s = s.replace('ي', 'ی').replace('ك', 'ک')
        s = s.replace("\u200f", "").replace("\u200e", "")
            .replace("\u202a", "").replace("\u202c", "").replace("\u202b", "")
            .replace('\u00a0', ' ')
        return s.trim()
    }

    private fun toEnglishDigits(input: String): String {
        val map = mapOf(
            '۰' to '0', '۱' to '1', '۲' to '2', '۳' to '3', '۴' to '4',
            '۵' to '5', '۶' to '6', '۷' to '7', '۸' to '8', '۹' to '9',
            '٠' to '0', '١' to '1', '٢' to '2', '٣' to '3', '٤' to '4',
            '٥' to '5', '٦' to '6', '٧' to '7', '٨' to '8', '٩' to '9',
        )
        val sb = StringBuilder()
        for (ch in input) sb.append(map[ch] ?: ch)
        return sb.toString()
    }

    private fun matchTemplate(body: String, pattern: JSONObject, template: String): JSONObject? {
        val normalizedTemplate = normalize(template).trim()
        if (normalizedTemplate.isEmpty()) return null
        val compiled = templateToRegex(normalizedTemplate) ?: return null
        var m = compiled.pattern.matcher(body)
        var confidence = 1.0
        var groups = compiled.groups
        var matchedBody = body
        if (!m.find()) {
            val softBody = body.replace(Regex("\\s+"), " ")
            val softTemplate = normalizedTemplate.replace(Regex("\\s+"), " ")
            val soft = templateToRegex(softTemplate) ?: return null
            m = soft.pattern.matcher(softBody)
            if (!m.find()) return null
            confidence = 0.85
            groups = soft.groups
            matchedBody = softBody
        }
        return resultFromMatcher(m, groups, pattern, matchedBody, confidence)
    }

    private fun templateToRegex(template: String): Compiled? {
        val buf = StringBuilder("^")
        var i = 0
        var groupIndex = 1
        val groups = mutableMapOf<String, Int>()
        val usedNames = mutableMapOf<String, Int>()
        while (i < template.length) {
            if (template[i] == '{') {
                val end = template.indexOf('}', i + 1)
                if (end > i) {
                    val name = template.substring(i + 1, end).trim().lowercase()
                    val body = placeholderBodies[name]
                    if (body != null) {
                        val count = usedNames[name] ?: 0
                        usedNames[name] = count + 1
                        if (count == 0) {
                            buf.append('(').append(body).append(')')
                            groups[name] = groupIndex
                            groupIndex++
                        } else {
                            buf.append("(?:").append(body).append(')')
                        }
                        i = end + 1
                        continue
                    }
                }
            }
            val ch = template[i]
            when {
                ch == '\n' || ch == '\r' -> buf.append("\\s*")
                ch.isWhitespace() -> {
                    buf.append("\\s*")
                    while (i + 1 < template.length && template[i + 1].isWhitespace()) i++
                }
                else -> buf.append(Pattern.quote(ch.toString()))
            }
            i++
        }
        buf.append("\\s*$")
        return try {
            Compiled(Pattern.compile(buf.toString(), Pattern.CASE_INSENSITIVE or Pattern.DOTALL), groups)
        } catch (_: Exception) {
            null
        }
    }

    private fun resultFromMatcher(
        m: Matcher,
        groups: Map<String, Int>,
        pattern: JSONObject,
        body: String,
        confidence: Double,
    ): JSONObject? {
        fun group(name: String): String? {
            val idx = groups[name] ?: return null
            return try {
                m.group(idx)
            } catch (_: Exception) {
                null
            }
        }

        val amountRaw = group("amount") ?: group("amount_signed") ?: return null
        val amount = parseAmount(amountRaw) ?: return null
        if (amount <= 0) return null
        val directionWord = group("direction")
        var direction = resolveDirection(directionWord, amountRaw)
        if (direction == "unknown") {
            if (body.contains("برداشت")) direction = "debit"
            else if (body.contains("واریز") || body.contains("واريز")) direction = "credit"
        }
        val balanceRaw = group("balance")
        val balance = balanceRaw?.let { parseAmount(it) }

        val out = JSONObject()
        out.put("matched", true)
        out.put("amount", abs(amount))
        out.put("direction", direction)
        if (balance != null) out.put("balance", abs(balance))
        group("account")?.let { out.put("account_mask", it) }
        group("channel")?.let { out.put("channel", it) }
        out.put("pattern_id", pattern.optString("id"))
        out.put("pattern_name", pattern.optString("name"))
        if (pattern.has("bank_account_id") && !pattern.isNull("bank_account_id")) {
            out.put("bank_account_id", pattern.optInt("bank_account_id"))
        }
        pattern.optString("bank_account_name", "").takeIf { it.isNotEmpty() }?.let {
            out.put("bank_account_name", it)
        }
        if (pattern.has("business_id") && !pattern.isNull("business_id")) {
            out.put("business_id", pattern.optInt("business_id"))
        }
        pattern.optString("business_name", "").takeIf { it.isNotEmpty() }?.let {
            out.put("business_name", it)
        }
        out.put("confidence", confidence)
        return out
    }

    private fun heuristic(body: String, sender: String, patterns: JSONArray): JSONObject? {
        var hinted: JSONObject? = null
        for (i in 0 until patterns.length()) {
            val p = patterns.optJSONObject(i) ?: continue
            if (!p.optBoolean("enabled", true)) continue
            val hints = p.optJSONArray("sender_hints") ?: JSONArray()
            if (hints.length() == 0) continue
            if (hintMatchesSender(sender, hints)) {
                hinted = p
                break
            }
        }

        val senderLooksBank = senderLooksLikeBank(sender)
        if (hinted == null && !senderLooksBank) return null
        if (!bodyHasStrongBankStructure(body)) return null

        var direction = "unknown"
        if (body.contains("برداشت")) direction = "debit"
        else if (body.contains("واریز") || body.contains("واريز")) direction = "credit"

        var amount: Double? = null
        val labeled = Regex(
            "(?:برداشت|واریز|واريز|مبلغ)\\s*(?:از\\s*[:：]?\\s*)?[:：]?\\s*([+\\-]?\\d[\\d,٬٫]*)\\s*(?:ریال|ريال)?",
            RegexOption.IGNORE_CASE,
        ).find(body)
        if (labeled != null) amount = parseAmount(labeled.groupValues[1])

        if (amount == null) {
            val trailing = Regex("((?:\\d{1,3},)*\\d{3}|\\d+)\\s*-").find(body)
            if (trailing != null) {
                amount = parseAmount(trailing.groupValues[1])
                if (direction == "unknown") direction = "debit"
            }
        }
        if (amount == null || amount <= 0) return null

        val balanceMatch = Regex(
            "(?:مانده|موجودی|موجودي)\\s*[:：]?\\s*([+\\-]?\\d[\\d,٬٫]*)",
            RegexOption.IGNORE_CASE,
        ).find(body)
        val balance = balanceMatch?.let { parseAmount(it.groupValues[1]) }
        if (balance != null && amount == abs(balance) && labeled == null) {
            return null
        }

        val out = JSONObject()
        out.put("matched", true)
        out.put("amount", abs(amount))
        out.put("direction", direction)
        if (balance != null) out.put("balance", abs(balance))
        hinted?.let { p ->
            out.put("pattern_id", p.optString("id"))
            out.put("pattern_name", p.optString("name"))
            if (p.has("bank_account_id") && !p.isNull("bank_account_id")) {
                out.put("bank_account_id", p.optInt("bank_account_id"))
            }
            p.optString("bank_account_name", "").takeIf { it.isNotEmpty() }?.let {
                out.put("bank_account_name", it)
            }
            if (p.has("business_id") && !p.isNull("business_id")) {
                out.put("business_id", p.optInt("business_id"))
            }
        }
        out.put(
            "confidence",
            if (hinted != null) HEURISTIC_CONFIDENCE_WITH_SENDER_HINT
            else HEURISTIC_CONFIDENCE_BANK_SENDER_ONLY,
        )
        return out
    }

    private fun resolveDirection(word: String?, amountRaw: String): String {
        val w = (word ?: "").lowercase()
        if (w.contains("برداشت") || w.contains("withdraw") || w.contains("debit")) return "debit"
        if (w.contains("واریز") || w.contains("واريز") || w.contains("deposit") || w.contains("credit")) return "credit"
        val raw = amountRaw.trim()
        if (raw.startsWith("+")) return "credit"
        if (raw.startsWith("-") || raw.endsWith("-")) return "debit"
        return "unknown"
    }

    fun parseAmount(raw: String): Double? {
        var s = toEnglishDigits(raw)
            .replace("٬", ",")
            .replace("٫", ".")
            .replace(" ", "")
            .replace("ریال", "")
            .replace("ريال", "")
            .trim()
        var negative = false
        if (s.endsWith("-")) {
            negative = true
            s = s.dropLast(1)
        }
        if (s.startsWith("-")) {
            negative = true
            s = s.drop(1)
        }
        if (s.startsWith("+")) s = s.drop(1)
        s = s.replace(",", "")
        val v = s.toDoubleOrNull() ?: return null
        return if (negative) -abs(v) else v
    }

    fun fingerprint(sender: String, body: String, receivedAtMs: Long): String {
        val norm = normalize(body).replace(Regex("\\s+"), " ")
        val bucket = receivedAtMs / 60000
        return "${sender.trim()}|$bucket|${norm.hashCode()}"
    }

    fun buildEvent(
        sender: String,
        body: String,
        receivedAtMs: Long,
        match: JSONObject,
        activeBusinessId: Int?,
    ): JSONObject {
        val event = JSONObject()
        event.put("id", UUID.randomUUID().toString())
        event.put("fingerprint", fingerprint(sender, body, receivedAtMs))
        event.put("sender", sender)
        event.put("body", body)
        event.put("amount", match.optDouble("amount"))
        event.put("direction", match.optString("direction", "unknown"))
        if (match.has("balance")) event.put("balance", match.optDouble("balance"))
        match.optString("account_mask", "").takeIf { it.isNotEmpty() }?.let {
            event.put("account_mask", it)
        }
        match.optString("channel", "").takeIf { it.isNotEmpty() }?.let {
            event.put("channel", it)
        }
        match.optString("pattern_id", "").takeIf { it.isNotEmpty() }?.let {
            event.put("pattern_id", it)
        }
        match.optString("pattern_name", "").takeIf { it.isNotEmpty() }?.let {
            event.put("pattern_name", it)
        }
        if (match.has("bank_account_id")) event.put("bank_account_id", match.optInt("bank_account_id"))
        match.optString("bank_account_name", "").takeIf { it.isNotEmpty() }?.let {
            event.put("bank_account_name", it)
        }
        val needsChoice = match.optBoolean("needs_business_choice", false)
        event.put("needs_business_choice", needsChoice)
        if (match.has("candidates")) {
            event.put("candidates", match.optJSONArray("candidates") ?: JSONArray())
        } else {
            event.put("candidates", JSONArray())
        }
        match.optString("business_name", "").takeIf { it.isNotEmpty() }?.let {
            event.put("business_name", it)
        }

        val biz = when {
            needsChoice -> null
            match.has("business_id") && !match.isNull("business_id") -> match.optInt("business_id")
            else -> null
        }
        if (biz != null) event.put("business_id", biz)
        if (biz == null && !needsChoice && activeBusinessId != null) {
            event.put("preferred_business_id", activeBusinessId)
            event.put("needs_business_choice", true)
        }
        event.put(
            "received_at",
            java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply {
                timeZone = java.util.TimeZone.getTimeZone("UTC")
            }.format(java.util.Date(receivedAtMs)),
        )
        event.put("status", "pending")
        event.put("confidence", match.optDouble("confidence", 1.0))
        return event
    }
}
