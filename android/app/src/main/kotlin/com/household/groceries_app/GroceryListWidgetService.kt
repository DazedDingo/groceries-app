package com.household.groceries_app

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class GroceryListWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return GroceryListRemoteViewsFactory(applicationContext)
    }
}

class GroceryListRemoteViewsFactory(
    private val context: Context
) : RemoteViewsService.RemoteViewsFactory {

    data class GroceryEntry(val name: String, val quantity: Int, val unit: String?)

    private var items: List<GroceryEntry> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        // Fetch items synchronously (runs on binder thread, not main thread)
        val user = FirebaseAuth.getInstance().currentUser ?: return
        val db = FirebaseFirestore.getInstance()

        val latch = CountDownLatch(1)
        var householdId: String? = null

        db.document("users/${user.uid}").get()
            .addOnSuccessListener { doc ->
                householdId = doc.getString("householdId")
                latch.countDown()
            }
            .addOnFailureListener { latch.countDown() }

        latch.await(5, TimeUnit.SECONDS)

        if (householdId.isNullOrEmpty()) {
            items = emptyList()
            return
        }

        val itemsLatch = CountDownLatch(1)
        val fetched = mutableListOf<GroceryEntry>()

        db.collection("households/$householdId/items")
            .get()
            .addOnSuccessListener { snapshot ->
                for (doc in snapshot.documents) {
                    val name = doc.getString("name") ?: continue
                    val qty = (doc.getLong("quantity") ?: 1).toInt()
                    val unit = doc.getString("unit")
                    fetched.add(GroceryEntry(name, qty, unit))
                }
                itemsLatch.countDown()
            }
            .addOnFailureListener { itemsLatch.countDown() }

        itemsLatch.await(5, TimeUnit.SECONDS)

        // Sort alphabetically
        items = fetched.sortedBy { it.name }
    }

    override fun onDestroy() {
        items = emptyList()
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.grocery_list_item)

        if (position < items.size) {
            val item = items[position]
            views.setTextViewText(R.id.item_name, item.name.replaceFirstChar { it.uppercase() })

            val qtyLabel = when {
                item.unit != null -> "${item.quantity} ${item.unit}"
                item.quantity > 1 -> "x${item.quantity}"
                else -> ""
            }
            views.setTextViewText(R.id.item_qty, qtyLabel)
        }

        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
}
