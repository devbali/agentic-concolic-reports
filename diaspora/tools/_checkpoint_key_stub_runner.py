"""Run an _engine_section.py copy with concolic_engine.completion STUBBED.
No real engine, no audits, no JRuby: attach_to_summary just marks the summary."""
import os, sys, types
_pkg = types.ModuleType("concolic_engine"); _pkg.__path__ = []
_mod = types.ModuleType("concolic_engine.completion")
def attach_to_summary(S, cfg):
    print("STUB-ATTACH-RAN", flush=True)
    S["completion"] = {"complete": True, "blocking": [], "audits": [], "shims": [],
                       "shim_verdict_counts": {"PASS": 1},
                       "note_check": {"green": True}, "assumptions": {"green": True},
                       "stub_run_tag": os.environ.get("RUN_TAG", "")}
    S["complete"] = bool(S.get("coverage_complete"))
    return S
_mod.attach_to_summary = attach_to_summary
sys.modules["concolic_engine"] = _pkg
sys.modules["concolic_engine.completion"] = _mod
p = sys.argv[1]
exec(compile(open(p).read(), p, "exec"), {"__name__": "__main__", "__file__": p})
