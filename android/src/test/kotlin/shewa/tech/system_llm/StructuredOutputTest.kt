package shewa.tech.system_llm

import org.json.JSONObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class StructuredOutputTest {
    private val schema = JSONObject(
        """
        {"type":"object","properties":[
          {"name":"ids","type":"array","maxItems":8,"items":{"type":"integer"}},
          {"name":"message","type":"string","description":"Short text"}
        ]}
        """.trimIndent()
    )

    @Test
    fun acceptsMatchingObjectInsideCodeFence() {
        val text = "```json\n{\"ids\":[1,2],\"message\":\"ok\"}\n```"
        val valid = StructuredOutput.validated(schema, text)
        assertNotNull(valid)
        assertEquals(2, JSONObject(valid).getJSONArray("ids").length())
    }

    @Test
    fun rejectsWrongTypeMissingKeyAndNonJson() {
        assertNull(StructuredOutput.validated(schema, "{\"ids\":[\"a\"],\"message\":\"x\"}"))
        assertNull(StructuredOutput.validated(schema, "{\"ids\":[1]}"))
        assertNull(StructuredOutput.validated(schema, "no json here"))
    }

    @Test
    fun rejectsFractionalIntegers() {
        assertNull(StructuredOutput.validated(schema, "{\"ids\":[1.5],\"message\":\"x\"}"))
    }

    @Test
    fun rendersJsonSchemaWithRequiredProperties() {
        val rendered = StructuredOutput.toJsonSchema(schema)
        assertEquals(2, rendered.getJSONArray("required").length())
        assertEquals(8, rendered.getJSONObject("properties").getJSONObject("ids").getInt("maxItems"))
        assertTrue(StructuredOutput.instructions("Pick ids.", schema).startsWith("Pick ids."))
    }
}
