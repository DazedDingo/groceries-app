# Price comparison (in progress)

Goal: before shopping, work out **where to order** the current list from. Compare
online prices and split the list across shops when that's cheaper overall.

This is separate from the old per-store fields (`preferredStores`, `stores/`),
which are still legacy cruft awaiting removal. Don't build on them.

## Decisions (2026-10-31)

- **Online shops only, to start:** Asda (home delivery) and Costco UK online
  (we have an individual membership). Published online prices are what you
  actually pay. In-store-only shops (Lidl etc.) are out for now.
- **No receipt scanning.** The point is to decide *before* shopping.
- Accurate prices matter more than coverage.
- Fetching runs **on the phone** (in-app WebView, the user's own logins).
  Asda's Cloudflare blocks datacenter IPs, and member/postcode pricing needs
  the user's session.

## Planned shape

1. **Price lab** (shipped 0.1.55, hidden): capture real Asda pages so we can
   write a reliable extractor.
2. **Product matching:** link each list item to one product per shop. The
   user confirms the match once and it's remembered. Compare on our *own*
   £/kg, £/L or £/unit, computed from pack size.
3. **Compare screen** on the shopping list: total per shop including
   delivery fees, plus the cheapest split.

### Split rule

- Fresh/chilled items are **Asda-only** (see Costco below).
- For ambient/bulk items, assign each to the cheaper shop. Only suggest a
  Costco order when the items moved there save **more than the £5.99 Costco
  grocery delivery fee** compared with Asda.

## Costco UK findings

- JSON search endpoint (works from the VPS without login):
  `https://www.costco.co.uk/rest/v2/uk/products/search?query=<term>:relevance:cartGroup:8796093380189&pageSize=N&fields=FULL&lang=en_GB&curr=GBP`
  - `cartGroup:8796093380189` = **Grocery Delivery** facet.
  - Useful fields: `name`, `code`, `price.value`, `pricePerUnit.value` +
    `unitType`, `stock.stockLevelStatus`, `potentialPromotions`,
    `membershipRestrictionApplied`, `businessDelivery`.
- **Grocery Delivery is ambient/bulk only:** rice, tins, tea, coffee, loo
  roll, laundry, dishwasher tabs, oils, cereal. Fresh items (e.g. Cravendale
  milk) are *Business Delivery*, which shows no price for our membership and
  isn't visible in the app.
- **No minimum order, £5.99 grocery delivery fee.**
- **`pricePerUnit` mixes units:** `unitType` is `PER_KG` for some items and
  `PER_UNIT` (per tin/bag) for others, e.g. Branston beans 24×410g shows
  £0.61 = per tin. Don't use it directly; compute from pack size.
- **Search relevance is poor:** "chicken breast" returns cat food, "baked
  beans" returns coffee beans, "pasta" returns Aperol. Matching must be
  user-confirmed. "Kitchen roll" returns nothing.
- Sample (2026-10-31): Tilda basmati 6×250g £5.19, Cushelle 24 roll £11.98,
  Heinz beans 24×415g £15.29, Valfrutta chopped tomatoes 12×400g £7.19,
  Yorkshire Tea 600 £14.99, Persil 95 wash £10.39, Kirkland dishwasher pacs
  115 £14.79. No promotions seen on any of these.

## Asda findings

- `asda.com/groceries/...` returns **Cloudflare 403** to plain requests from
  the VPS. Its page structure and APIs are still unknown, which is why the
  Price lab exists.

## Using the Price lab (0.1.55+)

1. Settings → tap the **About** line 7 times quickly → "Price lab unlocked".
   (A single tap still opens the About dialog after ~0.6s.)
2. In the built-in browser, **log into Asda** once. Cookies persist.
3. **Batch test** searches 12 staple terms (milk, basmati rice, toilet roll,
   kitchen roll, spaghetti, baked beans, chopped tomatoes, tea bags, olive
   oil, laundry liquid, dishwasher tablets, cereal) and captures each page.
   **Extract** captures just the current page and shows what was parsed.
4. **Share dump** produces `asda_dump_<date>.json`. Save it to Google Drive
   so Claude can read it and write the real extractor.

The dump holds, per page: title, a logged-in hint, the parsed items (JSON-LD +
DOM heuristic), up to 20 captured JSON network responses that mention
"price", page HTML (truncated to 400k chars) and interesting `window` globals.
Code: `lib/screens/settings/price_lab_screen.dart`, `price_lab_js.dart`,
`lib/models/price_lab_hit.dart`, `lib/services/price_lab_dump.dart`,
`lib/services/tap_unlock.dart`.
