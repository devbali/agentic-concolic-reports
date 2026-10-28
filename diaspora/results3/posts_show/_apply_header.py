#!/usr/bin/env python3
"""Re-apply POLICY_HEADER.txt to the top of the shipped policy file (the
canonical header is maintained in the batch dir, never edited in the .sql)."""
hdr = open("/home/dev/project/reports/diaspora/results3/posts_show/POLICY_HEADER.txt").read()
p = "/home/dev/project/reports/diaspora/results3/queries_from_runs/posts_show.sql"
s = open(p).read()
lines = s.split("\n")
i = 0
while i < len(lines) and (lines[i].startswith("--") or not lines[i].strip()):
    i += 1
open(p, "w").write(hdr.rstrip("\n") + "\n\n" + "\n".join(lines[i:]))
print(f"header re-applied ({len(hdr.splitlines())} header lines, "
      f"{sum(1 for l in lines[i:] if l.startswith('SELECT'))} SELECTs kept)")
