#!/usr/bin/env python3
"""apply_fix8_scaffold_params.py — the scaffold misses a required param that
the action reads through one of its own private helpers.

MEASURED.  `links_resolve` stops with

    ActionController::ParameterMissing: param is missing or the value is empty: q
    actionpack-5.2.4.3/lib/action_controller/metal/strong_parameters.rb:445:in `require'

and its `config.json` carries NO inputs at all.  The reason is visible in
`app/controllers/links_controller.rb`:

    def resolve
      entity = DiasporaLinkService.new(query).find_or_fetch_entity
      ...
    end

    private

    def query
      @query ||= params.fetch(:q)
    end

`tools/introspect_entrypoints.rb:295` runs `scan_body` over the ACTION's body
only, so `params.fetch(:q)` — which lives in the private helper `query` — is
never seen, and `tools/scaffold.py:152` therefore makes no symbolic param.
`PARAMS_RE` itself is fine; it is the body that is too narrow.

THE WIDENING IS DELIBERATELY ONE LEVEL AND NAME-DIRECTED: only the
controller's OWN private/protected methods whose NAME APPEARS IN THE ACTION
BODY are scanned.  Scanning every method on the class would make a param
symbolic for an action that never reads it, which costs a stray symbolic_vars
entry and widens the flip space for nothing.

THREE ENDPOINTS, NOT ONE.  The same shape was then measured on the two
federation receive endpoints:

    diaspora_federation_receive_public
    diaspora_federation_receive_private
      TypeError: no implicit conversion of nil into String
        org/jruby/ext/cgi/escape/CGIEscape.java:416:in `unescape'
        diaspora_federation-rails-0.2.6/app/controllers/diaspora_federation/
          receive_controller.rb:48:in `data_for_public_message'   (:58 for private)
        .../receive_controller.rb:14:in `public'                  (:28 for private)

`CGI.unescape(params[:xml])` — `params[:xml]` is nil because it is read in the
private helper `data_for_public_message`, which the action calls by name.  Both
configs list no inputs at all.  `PARAMS_RE` matches `params[:xml]` perfectly
well; nothing ever showed it that line.

NOT FIXED BY THIS, and recorded as residue instead: `registrations_create`
needs `params.require(:user)`, which is a NESTED HASH.  The scaffold's input
model is flat symbolic strings, so making `:user` "symbolic" as a string
would still fail `require(:user).permit(...)`.  That needs a typed nested
param and is a scaffold design change, not a scan widening.
"""
from __future__ import annotations
import shutil, sys

INTRO = "/home/dev/project/reports/autolab/entrypoints/tools/introspect_entrypoints.rb"
BUILD = "/home/dev/project/reports/autolab/entrypoints/tools/build_manifest.py"
SCAFF = "/home/dev/project/reports/autolab/entrypoints/tools/scaffold.py"

INTRO_OLD = '''        body, complete = method_source(loc[0], loc[1])
        entry["body_extracted"] = complete
        entry.merge!(scan_body(body))
        entry["defined_in"] = um.owner.name'''

INTRO_NEW = '''        body, complete = method_source(loc[0], loc[1])
        entry["body_extracted"] = complete
        entry.merge!(scan_body(body))
        entry["defined_in"] = um.owner.name
        # e2e FIX-8. An action often reads its params through one of the
        # controller's OWN private helpers -- LinksController#resolve calls
        # `query`, and `query` is `params.fetch(:q)`. Scanning the action
        # body alone misses it and the scaffold then makes no symbolic param
        # at all, so the endpoint stops at ParameterMissing.
        #
        # ONE LEVEL, NAME-DIRECTED: only the class's own private/protected
        # methods whose name appears in the action body. Scanning every
        # method on the class would symbolise params for actions that never
        # read them.
        helper_params = []
        helper_names = []
        (klass.private_instance_methods(false) +
         klass.protected_instance_methods(false)).each do |hm|
          next if hm.to_s == act.to_s
          next unless body.to_s =~ /(?<![A-Za-z0-9_])#{Regexp.escape(hm.to_s)}(?![A-Za-z0-9_])/
          hloc = (klass.instance_method(hm).source_location rescue nil)
          next unless hloc
          hbody, = method_source(hloc[0], hloc[1])
          next unless hbody
          found = hbody.scan(PARAMS_RE).flatten.compact.uniq
          next if found.empty?
          helper_names << hm.to_s
          helper_params.concat(found)
        end
        entry["params_read_in_helpers"] = helper_params.uniq.sort
        entry["helpers_scanned"] = helper_names.uniq.sort'''

BUILD_OLD = '''        read = head.get("params_read") or []'''
BUILD_NEW = '''        read = head.get("params_read") or []
        # e2e FIX-8: params the action reads through its own private helpers
        # (see introspect_entrypoints.rb). Appended, never substituted, so the
        # action-body order still leads.
        for _p in (head.get("params_read_in_helpers") or []):
            if _p not in read:
                read.append(_p)'''


def patch(path, edits, apply):
    s = open(path).read()
    for old, new in edits:
        n = s.count(old)
        if n != 1:
            print(f"  !! anchor x{n} in {path}: {old[:60]!r}")
            return False
        s = s.replace(old, new)
    if apply:
        shutil.copy(path, path + ".bak_e2e_fix8")
        open(path, "w").write(s)
        print(f"  patched {path}")
    else:
        print(f"  would patch {path}")
    return True


def main():
    apply = "--apply" in sys.argv
    ok = patch(INTRO, [(INTRO_OLD, INTRO_NEW)], apply)
    ok &= patch(BUILD, [(BUILD_OLD, BUILD_NEW)], apply)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
