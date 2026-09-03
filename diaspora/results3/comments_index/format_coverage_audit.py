#!/usr/bin/env python3
"""FORMAT COVERAGE AUDIT (cycle 3; the check that catches the adversary's
W1-W3 CLASS — an unexplored response format): every RENDERABLE format the
action declares must be a corpus scenario.

    python3 format_coverage_audit.py <batch_dir> [--controller <file>] [--action index]

Declared formats: the controller's `respond_to :a, :b, …` (responders) plus
every `format.x` block inside the action. Renderable = an explicit
`format.x` block in the action, or a template `views/<controller>/<action>.<x>.*`
exists. A declared format with neither (`.js` here — responders' to_js ->
default_render -> Template::Error, a real 500) is reported as
TEMPLATELESS and not required. Each renderable format must have >= 1 dump
whose `concolic_scenario.format` equals it; `mobile` is also satisfied by
no other format (mobile_switch is a distinct render tree). Exit 1 on any
renderable format with no dumps.
"""
import glob, json, os, re, sys

APP = "/home/dev/project/ruby_examples/dse-apps/apps/diaspora"

def main():
    args = sys.argv[1:]
    batch = args[0]
    ctrl = args[args.index("--controller") + 1] if "--controller" in args else \
        os.path.join(APP, "app/controllers/conversations_controller.rb")
    action = args[args.index("--action") + 1] if "--action" in args else "index"
    src = open(ctrl).read()
    declared = set()
    for m in re.finditer(r"^\s*respond_to\s+(.+)$", src, re.M):
        declared |= set(re.findall(r":(\w+)", m.group(1)))
    # the action body
    am = re.search(rf"^\s*def {action}\b(.*?)^\s*def ", src, re.M | re.S)
    body = am.group(1) if am else ""
    explicit = set(re.findall(r"format\.(\w+)", body))
    declared |= explicit
    cname = os.path.basename(ctrl).replace("_controller.rb", "")
    vdir = os.path.join(APP, "app/views", cname)
    templated = {f.split(".")[1] for f in os.listdir(vdir) if f.startswith(action + ".") and f.count(".") >= 2}
    renderable = {f for f in declared if f in explicit or f in templated}
    have = {}
    for p in glob.glob(os.path.join(batch, "dump_*.json")):
        d = json.load(open(p))
        f = ((d.get("concolic_scenario") or {}).get("format") or "").strip()
        if f:
            have[f] = have.get(f, 0) + 1
    print(f"== format_coverage_audit: {ctrl.split('/')[-1]}#{action} ==")
    print(f"   declared formats : {sorted(declared)}")
    print(f"   explicit blocks  : {sorted(explicit)}   templates: {sorted(templated)}")
    print(f"   renderable       : {sorted(renderable)}")
    red = False
    for f in sorted(declared):
        if f in renderable:
            n = have.get(f, 0)
            print(f"   {f:<8} {'OK ' if n else 'RED'}  dumps={n}")
            red = red or n == 0
        else:
            print(f"   {f:<8} TEMPLATELESS (declared, no template, no explicit block — real 500; not required)")
    print("RESULT: " + ("RED — a renderable declared format has no corpus scenario." if red else "every renderable format is a corpus scenario."))
    sys.exit(1 if red else 0)

if __name__ == "__main__":
    main()
