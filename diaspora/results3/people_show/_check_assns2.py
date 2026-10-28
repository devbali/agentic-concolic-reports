import importlib.util
from collections import Counter

spec = importlib.util.spec_from_file_location("ca", "reports/diaspora/results3/people_show/coverage_assumptions.py")
ca = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ca)
a = ca.build()
c = Counter(type(x).__name__ for x in a.assumptions)
print("by type:", dict(c))
print("total:", len(a.assumptions))
# check the new pairs exist
ind = [x for x in a.assumptions if type(x).__name__ == "IndependenceAssumption"]
targets = [
    ("REC1", "REC1_ROWS"), ("REC1", "TOA_ROWS"),
    ("REC2", "REC1_ROWS"), ("REC2", "TOA_ROWS"),
    ("guards x ROWCC1",), ("guards x AUTHGUID_NE",),
]
import re
def short(e):
    m = re.search(r"records_[123]|records_[123]_rows|to_a_1_rows|comments_count == 1|author_guid != StringVal", e)
    return m.group(0) if m else e[:40]
pairs = [(short(getattr(x, "expr_a", "")), short(getattr(x, "expr_b", ""))) for x in ind]
for p in pairs:
    print("  ", p)