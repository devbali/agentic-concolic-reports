import importlib.util
from collections import Counter

spec = importlib.util.spec_from_file_location("ca", "reports/diaspora/results3/people_show/coverage_assumptions.py")
ca = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ca)
a = ca.build()
c = Counter(type(x).__name__ for x in a.assumptions)
print("by type:", dict(c))
vblanks = [x for x in a.assumptions if type(x).__name__ == "OneSideUntrackedPathAssumption" and "via_user_diaspora_handle" in str(getattr(x, "expr", ""))]
print("via_user OneSide count:", len(vblanks))
for x in vblanks:
    print(" -", getattr(x, "expr", "")[:120], "| tracked:", getattr(x, "tracked_side", None))