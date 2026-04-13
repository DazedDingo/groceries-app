package com.household.groceries_app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.speech.RecognizerIntent
import android.widget.Toast
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import java.util.Locale

class VoiceAddActivity : Activity() {

    companion object {
        private const val SPEECH_REQUEST_CODE = 100

        // Unit patterns for parsing "300 g flour" → qty=300, unit="g", name="flour"
        private val UNIT_REGEX = Regex(
            "^(pounds?|lbs?|kilos?|kg|grams?|g|ounces?|oz|litres?|liters?|l|ml|cups?|pints?|gallons?|bags?|boxes?|cans?|bottles?|packs?|packets?|bunche?s?|loave?s|dozen|doz)\\b\\s*(?:of\\s+)?",
            RegexOption.IGNORE_CASE
        )

        private val UNIT_NORMALISE = mapOf(
            "pound" to "lb", "pounds" to "lb", "lbs" to "lb",
            "kilo" to "kg", "kilos" to "kg",
            "gram" to "g", "grams" to "g",
            "ounce" to "oz", "ounces" to "oz",
            "litre" to "L", "litres" to "L", "liter" to "L", "liters" to "L", "l" to "L",
            "cup" to "cups", "pint" to "pints", "gallon" to "gallons",
            "bag" to "bags", "box" to "boxes", "can" to "cans", "bottle" to "bottles",
            "pack" to "packs", "packet" to "packs", "packets" to "packs",
            "bunch" to "bunches", "bunches" to "bunches",
            "loaf" to "loaves", "loaves" to "loaves",
            "doz" to "dozen"
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val speechIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PROMPT, "What do you want to add?")
        }

        try {
            startActivityForResult(speechIntent, SPEECH_REQUEST_CODE)
        } catch (e: Exception) {
            Toast.makeText(this, "Speech recognition not available", Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == SPEECH_REQUEST_CODE) {
            if (resultCode == RESULT_OK && data != null) {
                val results = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                val spoken = results?.firstOrNull()?.trim() ?: ""
                if (spoken.isNotEmpty()) {
                    addToGroceryList(spoken)
                } else {
                    finish()
                }
            } else {
                finish()
            }
        }
    }

    data class ParsedItem(val quantity: Int, val name: String, val unit: String?)

    private fun parseItemString(raw: String): ParsedItem {
        val trimmed = raw.trim()
        val match = Regex("^(\\d+)\\s+(.+)$").find(trimmed)
        if (match != null) {
            val rawQty = match.groupValues[1].toIntOrNull()?.coerceAtLeast(1) ?: 1
            val rest = match.groupValues[2].trim()
            val unitMatch = UNIT_REGEX.find(rest)
            if (unitMatch != null) {
                val rawUnit = unitMatch.groupValues[1].lowercase()
                val unit = UNIT_NORMALISE[rawUnit] ?: rawUnit
                val name = rest.substring(unitMatch.range.last + 1).trim()
                return ParsedItem(rawQty, name.ifEmpty { rest }, unit)
            }
            return ParsedItem(rawQty.coerceAtMost(99), rest, null)
        }
        return ParsedItem(1, trimmed, null)
    }

    private fun addToGroceryList(spoken: String) {
        val user = FirebaseAuth.getInstance().currentUser
        if (user == null) {
            Toast.makeText(this, "Not signed in. Open the app first.", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        val db = FirebaseFirestore.getInstance()
        db.document("users/${user.uid}").get()
            .addOnSuccessListener { userDoc ->
                val householdId = userDoc.getString("householdId")
                if (householdId.isNullOrEmpty()) {
                    Toast.makeText(this, "No household found", Toast.LENGTH_SHORT).show()
                    finish()
                    return@addOnSuccessListener
                }

                val parsed = parseItemString(spoken)
                val itemName = parsed.name.lowercase()

                val itemData = hashMapOf(
                    "name" to itemName,
                    "quantity" to parsed.quantity,
                    "unit" to parsed.unit,
                    "categoryId" to "uncategorised",
                    "preferredStores" to emptyList<String>(),
                    "pantryItemId" to null,
                    "recipeSource" to null,
                    "addedBy" to hashMapOf(
                        "uid" to user.uid,
                        "displayName" to (user.displayName ?: "Widget"),
                        "source" to "voice_in_app"
                    ),
                    "addedAt" to FieldValue.serverTimestamp()
                )

                val histData = hashMapOf(
                    "itemName" to itemName,
                    "categoryId" to "uncategorised",
                    "quantity" to parsed.quantity,
                    "action" to "added",
                    "byName" to (user.displayName ?: "Widget"),
                    "at" to FieldValue.serverTimestamp()
                )

                val batch = db.batch()
                val itemRef = db.collection("households/$householdId/items").document()
                batch.set(itemRef, itemData)
                val histRef = db.collection("households/$householdId/history").document()
                batch.set(histRef, histData)

                batch.commit()
                    .addOnSuccessListener {
                        val label = if (parsed.unit != null) {
                            "${parsed.quantity} ${parsed.unit} ${parsed.name}"
                        } else if (parsed.quantity > 1) {
                            "${parsed.quantity}x ${parsed.name}"
                        } else {
                            parsed.name
                        }
                        Toast.makeText(this, "Added: $label", Toast.LENGTH_SHORT).show()
                        finish()
                    }
                    .addOnFailureListener { e ->
                        Toast.makeText(this, "Failed: ${e.message}", Toast.LENGTH_SHORT).show()
                        finish()
                    }
            }
            .addOnFailureListener { e ->
                Toast.makeText(this, "Error: ${e.message}", Toast.LENGTH_SHORT).show()
                finish()
            }
    }
}
