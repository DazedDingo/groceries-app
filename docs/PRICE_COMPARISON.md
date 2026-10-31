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
  the VPS, so fetching runs in the in-app WebView on the phone.
- **Search is Algolia** (from the first Price lab dump, 2026-10-31, 12 pages,
  logged out). The page calls
  `https://8i6wskccnv-dsn.algolia.net/1/indexes/*/queries` (multi-query;
  index `ASDA_PRODUCTS`, 30 hits per page) and `…/indexes/ASDA_PRODUCTS/query`
  (a 14-hit carousel). The API key is sent in request headers, not the URL.
  We don't extract it: the app keeps reading the responses from inside the
  WebView, exactly as the site does.
- Each hit has clean structured fields: `NAME`, `BRAND`, `CIN`/`ID`,
  `PACK_SIZE`, `SALES_TYPE`, `STATUS`, `STOCK.<storeId>` (logged-out
  default store 4647), `PRIMARY_TAXONOMY` (dept/aisle/shelf), and
  `PRICES.EN = {PRICE, WASPRICE, OFFER: List|Rollback|Dropped,
  PRICEPERUOM, PRICEPERUOMFORMATTED ("£1.06/LT", "£4.00/KG", "8.8p/EA")}`.
  Multibuys are in `PROMOS.EN[] = {NAME: "Any 5 for £5", TYPE, START_DATE,
  END_DATE}`.
- Prices are visible **without logging in**.
- **Use the Algolia JSON, not the DOM heuristic.** The DOM pass grabbed the
  *was* price for rollbacks (Taylors 160 bags showed £6.17; the real price
  is £4.50).

## First head-to-head (rough, hand-matched, 2026-10-31)

| Item | Costco online | Asda | Cheaper |
|---|---|---|---|
| Olive oil (EVOO) | Kirkland 5L £22.99 = £4.60/L | ASDA 1L £7.50 | Costco |
| Loo roll | Cushelle 24 £11.98 = 50p/roll | Shades 12 £9 = 75p (2 for £15 = 62.5p) | Costco |
| Tea bags | Yorkshire 600 £14.99 = 2.5p/bag | Taylors 160 £4.50 (rollback) = 2.8p | Costco (just) |
| Basmati (microwave) | Tilda 6×250g £5.19 = £3.46/kg | Tilda 250g £1.00 = £4/kg | Costco |
| Dishwasher tabs | Kirkland 115 £14.79 = 12.9p | ASDA 40 £3.50 = 8.8p | Asda |
| Laundry liquid | Persil 95 wash £10.39 = 10.9p/wash | ASDA 60 wash £2.84 = 4.7p (Persil 53 £10 = 18.9p) | Depends on brand |

## Using the Price lab (0.1.55+)

1. Settings → tap the **About** line 7 times quickly → "Price lab unlocked".
   (A single tap still opens the About dialog after ~0.6s.)
2. In the built-in browser, **log into Asda** once. Cookies persist.
3. **Batch test** searches 12 staple terms (milk, basmati rice, toilet roll,
   kitchen roll, spaghetti, baked beans, chopped tomatoes, tea bags, olive
   oil, laundry liquid, dishwasher tablets, cereal) and captures each page.
   **Extract** captures just the current page and shows what was parsed.
4. **Send to Claude** (0.1.56+) uploads the dump into the household's
   Firestore (`config/priceLabDump*`, gzipped and chunked). Claude pulls it on
   the VPS through the Firebase CLI's MCP server (`firestore_get_document`): `python3 tools/fetch_price_lab_dump.py out.json`.
   **Share dump** still saves `asda_dump_<date>.json` via the share sheet, but
   the Drive connector can't download files that large (8 MB failed with
   "session expired"), so prefer Send to Claude.

The dump holds, per page: title, a logged-in hint, the parsed items (JSON-LD +
DOM heuristic), up to 20 captured JSON network responses that mention
"price", page HTML (truncated to 400k chars) and interesting `window` globals.
Code: `lib/screens/settings/price_lab_screen.dart`, `price_lab_js.dart`,
`lib/models/price_lab_hit.dart`, `lib/services/price_lab_dump.dart`,
`lib/services/tap_unlock.dart`.
