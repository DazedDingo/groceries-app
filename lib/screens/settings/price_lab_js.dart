// JavaScript used by the hidden Price lab screen. Kept as Dart const strings
// (raw, so JS regex escapes survive).

/// Injected at AT_DOCUMENT_START. Hooks fetch + XHR and records JSON-ish
/// responses that mention "price" into window.__priceLabNet (max 20, oldest
/// dropped). Must never break the page.
const String priceLabHookJs = r'''
(function () {
  try {
    if (window.__priceLabInstalled) return;
    window.__priceLabInstalled = true;
    window.__priceLabNet = window.__priceLabNet || [];
    var MAX = 20, BODY = 150000;

    function push(url, status, text, ct) {
      try {
        if (typeof text !== 'string' || !text) return;
        var first = text.replace(/^\s+/, '').charAt(0);
        var jsonish = (ct && String(ct).toLowerCase().indexOf('json') >= 0) ||
          first === '{' || first === '[';
        if (!jsonish) return;
        if (!/price/i.test(text)) return;
        window.__priceLabNet.push({
          url: String(url),
          status: status,
          body: text.slice(0, BODY)
        });
        while (window.__priceLabNet.length > MAX) window.__priceLabNet.shift();
      } catch (e) {}
    }

    var origFetch = window.fetch;
    if (typeof origFetch === 'function') {
      window.fetch = function () {
        var args = arguments;
        var p = origFetch.apply(this, args);
        try {
          p.then(function (resp) {
            try {
              var c = resp.clone();
              var a0 = args[0];
              var url = resp.url || (typeof a0 === 'string' ? a0 : (a0 && a0.url));
              var ct = (c.headers && c.headers.get('content-type')) || '';
              c.text().then(function (t) { push(url, resp.status, t, ct); })
                .catch(function () {});
            } catch (e) {}
          }).catch(function () {});
        } catch (e) {}
        return p;
      };
    }

    var XP = window.XMLHttpRequest && window.XMLHttpRequest.prototype;
    if (XP) {
      var origOpen = XP.open, origSend = XP.send;
      XP.open = function (m, u) {
        try { this.__plUrl = u; } catch (e) {}
        return origOpen.apply(this, arguments);
      };
      XP.send = function () {
        try {
          var x = this;
          x.addEventListener('loadend', function () {
            try {
              var ct = x.getResponseHeader('content-type') || '';
              var t = '';
              if (x.responseType === '' || x.responseType === 'text') t = x.responseText;
              else if (x.responseType === 'json') t = JSON.stringify(x.response);
              push(x.responseURL || x.__plUrl, x.status, t, ct);
            } catch (e) {}
          });
        } catch (e) {}
        return origSend.apply(this, arguments);
      };
    }
  } catch (e) {}
})();
''';

/// Defines window.__priceLabExtract() (returns a JSON string
/// {items:[{source,name,price,unitPrice,promo,url,raw}], network:[...]}) and
/// window.__priceLabSnapshot() (returns a JSON string with title,
/// loggedInHint, html, globals, extracted, network). Evaluate this once per
/// page, then call the functions.
const String priceLabExtractorJs = r'''
(function () {
  function clean(s, max) {
    s = (s == null ? '' : String(s)).replace(/\s+/g, ' ').trim();
    return max ? s.slice(0, max) : s;
  }

  function jsonLdItems() {
    var items = [];
    var nodes = document.querySelectorAll('script[type="application/ld+json"]');
    function typeHas(n, t) {
      var ty = n && n['@type'];
      if (Array.isArray(ty)) return ty.indexOf(t) >= 0;
      return ty === t;
    }
    function offerOf(n) {
      var o = n.offers;
      if (Array.isArray(o)) o = o[0];
      return o || {};
    }
    function walk(n, depth) {
      if (!n || depth > 6) return;
      if (Array.isArray(n)) { n.forEach(function (x) { walk(x, depth + 1); }); return; }
      if (typeof n !== 'object') return;
      if (n['@graph']) walk(n['@graph'], depth + 1);
      if (typeHas(n, 'Product')) {
        var o = offerOf(n);
        var price = o.price != null ? o.price : o.lowPrice;
        items.push({
          source: 'jsonld',
          name: clean(n.name, 200),
          price: price != null ? String(price) : null,
          unitPrice: null,
          promo: null,
          url: n.url || o.url || null,
          raw: clean(JSON.stringify(n), 300)
        });
      } else if (typeHas(n, 'ItemList')) {
        var els = n.itemListElement;
        if (els && !Array.isArray(els)) els = [els];
        (els || []).forEach(function (e) {
          if (e && e.item) walk(e.item, depth + 1);
          else walk(e, depth + 1);
        });
      } else if (typeHas(n, 'ListItem') && n.item) {
        walk(n.item, depth + 1);
      }
    }
    for (var i = 0; i < nodes.length; i++) {
      try { walk(JSON.parse(nodes[i].textContent), 0); } catch (e) {}
    }
    return items;
  }

  var PRICE_RE = /^(£\d+(\.\d{1,2})?|\d+p)$/;
  var UNIT_RE = /£?\d+(\.\d+)?p?\s*\/\s*(kg|100g|g|ltr|litre|l|100ml|ml|each|ea|sheet|wash)\b/i;
  var PAREN_RE = /\(([^()]*\/[^()]*)\)/;
  var PROMO_RE = /rollback|was £|\d+ for £|asda rewards|price match|save|offer/i;
  var LINK_SEL = 'a[href*="/product"], a[href*="/prod"]';

  function ownText(el) {
    var t = '';
    for (var c = el.firstChild; c; c = c.nextSibling) {
      if (c.nodeType === 3) t += c.nodeValue;
    }
    return t.trim();
  }

  function domItems() {
    var items = [], seen = {};
    var all = document.body ? document.body.querySelectorAll('*') : [];
    var limit = Math.min(all.length, 30000);
    for (var i = 0; i < limit; i++) {
      var el = all[i];
      var own = ownText(el);
      if (!own || own.length > 12 || !PRICE_RE.test(own)) continue;
      var anc = el, link = null;
      for (var d = 0; anc && d <= 8; d++, anc = anc.parentElement) {
        if (anc.matches && anc.matches('a[href]') && /\/prod/.test(anc.getAttribute('href') || '')) {
          link = anc; break;
        }
        var ls = anc.querySelectorAll ? anc.querySelectorAll(LINK_SEL) : [];
        if (ls.length) {
          var hrefs = {}, n = 0;
          for (var k = 0; k < ls.length; k++) {
            var h = ls[k].href;
            if (!hrefs[h]) { hrefs[h] = 1; n++; }
          }
          // More than one distinct product in this container = a list, not a card.
          if (n === 1) link = ls[0];
          break;
        }
      }
      if (!link || !anc) continue;
      var href = link.href;
      if (seen[href]) continue;
      seen[href] = 1;

      var name = clean(link.innerText || link.textContent, 200);
      if (!name) name = clean(link.getAttribute('aria-label'), 200);
      if (!name) {
        var img = link.querySelector('img') || anc.querySelector('img');
        if (img) name = clean(img.getAttribute('alt'), 200);
      }
      var text = anc.innerText || anc.textContent || '';
      var um = UNIT_RE.exec(text);
      var unit = um ? clean(um[0]) : null;
      if (!unit) {
        var pm = PAREN_RE.exec(text);
        if (pm) unit = clean(pm[1]);
      }
      var promos = [];
      text.split('\n').forEach(function (line) {
        line = clean(line, 120);
        if (line && PROMO_RE.test(line) && promos.indexOf(line) < 0) promos.push(line);
      });
      items.push({
        source: 'dom',
        name: name,
        price: own,
        unitPrice: unit,
        promo: promos.length ? promos.join(' | ') : null,
        url: href,
        raw: clean(text, 300)
      });
    }
    return items;
  }

  window.__priceLabExtract = function () {
    var out = { items: [], network: [] };
    try { out.items = out.items.concat(jsonLdItems()); } catch (e) {}
    try { out.items = out.items.concat(domItems()); } catch (e) {}
    try { out.network = window.__priceLabNet || []; } catch (e) {}
    return JSON.stringify(out);
  };

  window.__priceLabSnapshot = function () {
    var r = { title: null, loggedInHint: null, html: '', globals: [],
              extracted: [], network: [] };
    try { r.title = document.title; } catch (e) {}
    try {
      var txt = document.body ? (document.body.innerText || '') : '';
      r.loggedInHint = txt ? /Sign out|Log out|My account/i.test(txt) : null;
    } catch (e) {}
    try { r.html = document.documentElement.outerHTML.slice(0, 400000); } catch (e) {}
    try {
      r.globals = Object.getOwnPropertyNames(window).filter(function (k) {
        return /^__|STATE|DATA|APOLLO|NEXT/i.test(k) && k.indexOf('__priceLab') !== 0;
      });
    } catch (e) {}
    try {
      var x = JSON.parse(window.__priceLabExtract());
      r.extracted = x.items;
      r.network = x.network;
    } catch (e) {}
    return JSON.stringify(r);
  };
})();
''';
