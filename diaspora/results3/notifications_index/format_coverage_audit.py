#!/usr/bin/env python3
"""FORMAT COVERAGE AUDIT (notifications_index) — the check that catches the
adversary's "unexplored response format" CLASS: every RENDERABLE format of
the action must be a corpus scenario.

    python3 format_coverage_audit.py <batch_dir> [--controller <file>] [--action index]

NotificationsController#index has an explicit `respond_to do |format|` block
declaring format.html / format.xml / format.json (all RENDERABLE: html+mobile
via templates, xml/json via their explicit render). MOBILE is a genuine
render tree reached NOT by a respond_to declaration but by mobile-fu +
ApplicationController#mobile_switch (session[:mobile_view] -> request.format
= :mobile; :mobile is register_alias'd to text/html so the bare `format.html`
serves it and default_render picks index.mobile.haml). It is therefore
required whenever an `index.mobile.*` template exists.

Renderable = an explicit `format.x` block in the action, OR a template
`views/<controller>/<action>.<x>.*` that the app can route to (html/mobile).
Each renderable format must have >= 1 dump whose concolic_scenario.format
equals it. Exit 1 on any renderable format with no dumps.
"""
import glob, json, os, re, sys

APP = "/home/dev/project/ruby_examples/dse-apps/apps/diaspora"

def main():
    args = sys.argv[1:]
    batch = args[0]
    ctrl = args[args.index("--controller") + 1] if "--controller" in args else \
        os.path.join(APP, "app/controllers/notifications_controller.rb")
    action = args[args.index("--action") + 1] if "--action" in args else "index"
    src = open(ctrl).read()
    declared = set()
    for m in re.finditer(r"^\s*respond_to\s+(:\w.*)$", src, re.M):
        declared |= set(re.findall(r":(\w+)", m.group(1)))
    am = re.search(rf"^\s*def {action}\b(.*?)^\s*def ", src, re.M | re.S)
    body = am.group(1) if am else ""
    explicit = set(re.findall(r"format\.(\w+)", body))
    declared |= explicit
    cname = os.path.basename(ctrl).replace("_controller.rb", "")
    vdir = os.path.join(APP, "app/views", cname)
    templated = {f.split(".")[1] for f in os.listdir(vdir)
                 if f.startswith(action + ".") and f.count(".") >= 2}
    # Renderable: explicit-block formats + template-backed html/mobile.
    renderable = {f for f in declared if f in explicit or f in templated}
    # mobile: reached via mobile_switch (not a respond_to declaration) whenever
    # an index.mobile.* template exists — a distinct render tree the adversary
    # attacks. Require it.
    if "mobile" in templated:
        renderable.add("mobile")
    have = {}
    for p in glob.glob(os.path.join(batch, "dump_*.json")):
        d = json.load(open(p))
        f = ((d.get("concolic_scenario") or {}).get("format") or "").strip()
        if f:
            have[f] = have.get(f, 0) + 1
    print(f"== format_coverage_audit: {os.path.basename(ctrl)}#{action} ==")
    print(f"   declared/explicit : {sorted(declared)}")
    print(f"   templated         : {sorted(templated)}")
    print(f"   renderable        : {sorted(renderable)}")
    red = False
    for f in sorted(renderable):
        n = have.get(f, 0)
        print(f"   {f:<8} {'OK ' if n else 'RED'}  dumps={n}")
        red = red or n == 0
    print("RESULT: " + ("RED — a renderable format has no corpus scenario."
                        if red else "every renderable format is a corpus scenario."))
    sys.exit(1 if red else 0)

if __name__ == "__main__":
    main()
