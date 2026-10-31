"""Pull the Price lab dump uploaded by the app (households/{hid}/config/priceLabDump*)
via the Firebase CLI's MCP server, using the CLI login on this machine.

Only touches docs named priceLabDump / priceLabDump_N. Prints a summary only;
the decoded dump is written to OUT.
"""
import base64, gzip, json, subprocess, sys

PROJECT = "gorceries-app-8c24e"
ROOT = f"projects/{PROJECT}/databases/(default)/documents"
OUT = sys.argv[1] if len(sys.argv) > 1 else "asda_dump.json"

p = subprocess.Popen(["firebase", "mcp", "--only", "firestore"], cwd=__import__("os").path.dirname(__import__("os").path.dirname(__import__("os").path.abspath(__file__))),
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
_id = 0


def rpc(method, params=None, notify=False):
    global _id
    msg = {"jsonrpc": "2.0", "method": method, "params": params or {}}
    if not notify:
        _id += 1
        msg["id"] = _id
    p.stdin.write(json.dumps(msg) + "\n")
    p.stdin.flush()
    if notify:
        return None
    while True:
        line = p.stdout.readline()
        if not line:
            raise SystemExit("firebase mcp exited")
        m = json.loads(line)
        if m.get("id") == _id:
            if "error" in m:
                raise SystemExit(f"{method} error: {m['error']}")
            return m["result"]


def call(tool, args):
    res = rpc("tools/call", {"name": tool, "arguments": args})
    text = "".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
    if res.get("isError"):
        return None, text
    try:
        return json.loads(text), text
    except ValueError:
        return None, text


def field(doc, name):
    v = (doc.get("fields") or {}).get(name) or {}
    for k in ("stringValue", "integerValue", "timestampValue", "doubleValue"):
        if k in v:
            return v[k]
    return None


rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "pricelab", "version": "1"}})
rpc("notifications/initialized", notify=True)

# Household doc names only (mask on a field that doesn't exist -> no field data).
lst, raw = call("firestore_list_documents", {"parent": ROOT, "collectionId": "households", "pageSize": 50,
                                              "mask": {"fieldPaths": ["zzNoSuchField"]}})
if lst is None:
    raise SystemExit(f"list households failed: {raw[:300]}")
hids = [d["name"].rsplit("/", 1)[1] for d in lst.get("documents", [])]

best = None
for hid in hids:
    doc, _ = call("firestore_get_document", {"name": f"{ROOT}/households/{hid}/config/priceLabDump"})
    if doc and doc.get("fields"):
        created = field(doc, "createdAt") or ""
        if best is None or created > best[1]:
            best = (hid, created, doc)
if not best:
    raise SystemExit(f"no priceLabDump manifest found in {len(hids)} household(s)")

hid, created, man = best
n = int(field(man, "chunks"))
parts = []
for i in range(n):
    doc, raw = call("firestore_get_document", {"name": f"{ROOT}/households/{hid}/config/priceLabDump_{i}"})
    if not doc:
        raise SystemExit(f"chunk {i} missing: {raw[:200]}")
    parts.append(field(doc, "data"))
p.kill()

gz = base64.b64decode("".join(parts))
want = field(man, "gzBytes")
if want is not None and int(want) != len(gz):
    raise SystemExit(f"size mismatch: manifest {want}, got {len(gz)}")
data = gzip.decompress(gz)
dump = json.loads(data)
open(OUT, "wb").write(data)
print(json.dumps({"household": hid[:6] + "…", "createdAt": created, "chunks": n, "gzBytes": len(gz),
                  "jsonBytes": len(data), "appVersion": field(man, "appVersion"),
                  "pages": len(dump.get("pages", [])), "out": OUT}))
