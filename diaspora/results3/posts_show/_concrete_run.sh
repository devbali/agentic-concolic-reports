#!/bin/bash
# posts_show Phase-5 CONCRETE round. ONE JRuby per manifest (crash isolation:
# a scenario body can abort the JVM natively and per-scenario `error` capture
# only catches Ruby exceptions), then MERGE the five one-scenario outputs into
# the single `concrete_run.json` that completion_config.json names.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/posts_show
LOG="$B/_concrete_run.log"; : > "$LOG"
say(){ echo "[$(date -Is)] $*" | tee -a "$LOG"; }
for M in anon_html anon_nonpublic anon_json auth_html auth_json; do
  say "=== manifest $M ==="
  rm -f "$B/concrete_run.json"
  /home/dev/project/reports/diaspora/tools/slot env JRUBY_OPTS=--debug CONCRETE_COVERAGE=1 \
    /home/dev/project/scripts/diaspora-concolic \
    /home/dev/project/reports/diaspora/tools/concrete_checker/concrete_run_probe.rb \
    "$B/concrete_manifest_${M}.rb" >> "$LOG" 2>&1
  rc=$?
  if [ -f "$B/concrete_run.json" ]; then
    mv "$B/concrete_run.json" "$B/concrete_run_${M}.json"
    say "$M rc=$rc -> concrete_run_${M}.json"
  else
    say "$M rc=$rc -> NO OUTPUT (JVM abort or load failure) — NOT silently skipped"
  fi
done
python3 - "$B" <<'PY' | tee -a "$LOG"
import glob, json, os, sys
B = sys.argv[1]
merged = []
for f in sorted(glob.glob(os.path.join(B, "concrete_run_*.json"))):
    for sc in json.load(open(f)):
        if sc["name"] == "_cumulative_coverage" and any(
                m["name"] == "_cumulative_coverage" for m in merged):
            # keep ONE cumulative-coverage entry, unioned
            tgt = next(m for m in merged if m["name"] == "_cumulative_coverage")
            for k, v in sc["coverage"].items():
                tgt["coverage"][k] = sorted(set(tgt["coverage"].get(k, [])) | set(v))
            continue
        merged.append(sc)
json.dump(merged, open(os.path.join(B, "concrete_run.json"), "w"), indent=1)
for m in merged:
    print("%-30s target_calls=%-5d statements=%-4d error=%s" % (
        m["name"], len(m.get("target_calls") or []),
        len(m.get("statements") or []), m.get("error")))
print("merged -> concrete_run.json (%d scenarios)" % len(merged))
PY
say "=== CONCRETE ROUND END ==="
