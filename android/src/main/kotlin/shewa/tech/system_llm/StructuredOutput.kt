package shewa.tech.system_llm

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * Prompt-and-validate structured output. ML Kit's typed generation needs a
 * compile-time class, so schemas arriving from Dart are rendered into the
 * prompt and the model's answer is checked here.
 */
internal object StructuredOutput {
    /** Renders the Dart schema (ordered property lists) as a standard JSON Schema. */
    fun toJsonSchema(schema: JSONObject): JSONObject {
        val out = JSONObject()
        val type = schema.optString("type")
        out.put("type", type)
        if (schema.has("description")) out.put("description", schema.getString("description"))
        when (type) {
            "object" -> {
                val properties = JSONObject()
                val required = JSONArray()
                val entries = schema.optJSONArray("properties") ?: JSONArray()
                for (i in 0 until entries.length()) {
                    val entry = entries.getJSONObject(i)
                    val name = entry.getString("name")
                    properties.put(name, toJsonSchema(entry))
                    required.put(name)
                }
                out.put("properties", properties)
                out.put("required", required)
            }
            "array" -> {
                out.put("items", toJsonSchema(schema.getJSONObject("items")))
                if (schema.has("maxItems")) out.put("maxItems", schema.getInt("maxItems"))
            }
        }
        return out
    }

    /** Whether [value] has the shape [schema] describes. Extra keys are ignored. */
    fun matches(schema: JSONObject, value: Any?): Boolean = when (schema.optString("type")) {
        "object" -> value is JSONObject && (schema.optJSONArray("properties") ?: JSONArray()).let { entries ->
            (0 until entries.length()).all { i ->
                val entry = entries.getJSONObject(i)
                val name = entry.getString("name")
                value.has(name) && matches(entry, value.get(name))
            }
        }
        "array" -> value is JSONArray && schema.getJSONObject("items").let { items ->
            (0 until value.length()).all { matches(items, value.get(it)) }
        }
        "string" -> value is String
        "integer" -> value is Int || value is Long
        "boolean" -> value is Boolean
        else -> false
    }

    /** Extracts the first JSON object from [text], tolerating code fences and chatter. */
    fun parseObject(text: String): JSONObject? {
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start < 0 || end <= start) return null
        return try {
            JSONObject(text.substring(start, end + 1))
        } catch (_: JSONException) {
            null
        }
    }

    /** Parses [text] and returns it as compact JSON only if it matches [schema]. */
    fun validated(schema: JSONObject, text: String): String? {
        val parsed = parseObject(text) ?: return null
        return if (matches(schema, parsed)) parsed.toString() else null
    }

    fun instructions(base: String, schema: JSONObject): String =
        "$base\n\nAnswer with exactly one JSON object and nothing else: no markdown, " +
            "no explanation. It must satisfy this JSON Schema, and every property is required:\n" +
            toJsonSchema(schema).toString()
}
