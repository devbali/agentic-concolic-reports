import json, glob

# take one mobile dump and print events mentioning records_1/to_a/stream
f = "reports/diaspora/results3/people_show/dump_anon_mobile_0001.json"
d = json.load(open(f))
print("label:", d.get("label"))
n = 0
for ev in d.get("events", []):
    s = json.dumps(ev)
    if "records_1" in s or "to_a_1" in s or "stream" in s.lower() or "Decorated" in s:
        t = ev.get("type")
        if t == "symbolic_call":
            print("[symcall] result=%s" % ev.get("result_name", "")[:100])
            print("          note=%s" % ev.get("note", "")[:140])
        elif t == "path_condition":
            print("[pc] %s  T=%s" % (ev.get("expr", "")[:120], ev.get("taken")))
        n += 1
        if n > 25:
            break