"""names — the two spellings of a symbolic variable, and loud lookups across them.

WHY THIS MODULE EXISTS
----------------------
A symbolic variable in this project has more than one legal written form, and
the form depends on WHICH STAGE wrote it down:

  * LENGTH SPELLING.  `ruby_runtime/list.rb` names a SymbolicList's length
    variable literally ``len(X)`` — a valid Z3 identifier but not a valid
    Python one, so `coverage.py`'s declaration builder cannot emit it. Every
    batch therefore renames ``len(X)`` -> ``SYM_LEN_X`` at load
    (`coverage_report.fix_len_names`). Dumps, seed files and the runtime say
    ``len(X)``; the checker, the demand universe, the enumerator and every
    summary say ``SYM_LEN_X``.

  * ORDINAL vs CANONICAL.  `call_interceptor` names a result by WHEN it was
    called (``..._records_2`` — an ORDINAL), and an AliasAssumption re-identifies
    it by WHAT it did (``..._records_mentions_66022a8b`` — a CANONICAL), via
    `assumptions.alias_map_for` / `assumptions.renamer`. The map is MANY-TO-ONE:
    one canonical is backed by several ordinals. Seeds and the runtime consume
    ORDINALS; the checker and the enumerator emit CANONICALS.

Any code that builds a table at one stage and looks it up with a name from the
other stage MISSES — and the miss is SILENT. ``d.get(name)`` returns None,
``name in seeds`` is False, ``LIDX.get(L)`` is None. The caller then reads that
falsy answer as a MEANINGFUL NEGATIVE: "never minted", "not seedable", "no
compatible base", "never evaluated", "no seed needed", "pin unachievable".

This has cost the project multiple multi-hour failures. Documenting the trap
(RUNBOOK Phase 2) demonstrably did not stop it: four separate agents hit it in
one night AFTER it was written down. So the rule is now mechanical:

    A BARE DICT LOOKUP ACROSS THE NAME BOUNDARY IS A DEFECT.
    Use `NameSpace`, and the miss that is really a spelling miss RAISES.

THE GENUINE-ABSENCE DISTINCTION (the whole design hinges on this)
-----------------------------------------------------------------
Turning every miss into an exception would be worse than the disease: real
absences are meaningful and common. So `NameSpace.get` raises

    IF AND ONLY IF the table does not hold the key, but DOES hold some OTHER
    name denoting THE SAME underlying variable under one of the conversions
    above.

The raise is conditioned on a POSITIVE OBSERVATION — a sibling key that IS
present — never on the absence itself. A variable genuinely missing from the
table has no sibling present, so `get` returns the default exactly as a plain
dict would, and existing "not in the table" logic keeps working unchanged.

Two consequences, stated so nobody has to rediscover them:

  * This is not a completeness claim. If a name is misspelled AND the table
    lacks the other spelling too, the lookup stays silent — but then the falsy
    answer is right for the right reason: the variable is not in the table
    under any spelling.
  * The sibling search runs ONLY on the miss path. A hit is one plain dict
    lookup, so a NameSpace is free to use in the inner loops that dominate
    the index scans.

Self-contained by design: this module imports nothing from the rest of the
package (nor from any runtime), so it is safe to import from anywhere,
including from scripts that must not drag Z3 in. `to_canonical` deliberately
mirrors `assumptions.renamer`'s longest-name-first, never-a-prefix-of-a-longer-
ordinal substitution; `test_names.py` pins the two against each other.
"""

import re
import typing as t

__all__ = [
    "LEN_RE", "SYM_LEN_RE", "LEN_PREFIX",
    "WrongSpelling", "AmbiguousSpelling",
    "to_checker", "to_runtime", "is_checker_len", "is_runtime_len",
    "len_spellings", "same_variable", "normalize",
    "NameSpace",
]

#: ``len(X)`` as the runtime and the dumps write it.
LEN_RE = re.compile(r"len\(([^()]+)\)")
#: ``SYM_LEN_X`` as the checker and its summaries write it.
SYM_LEN_RE = re.compile(r"SYM_LEN_([A-Za-z0-9_]+)")
LEN_PREFIX = "SYM_LEN_"


class WrongSpelling(KeyError):
    """A lookup missed, but the table holds the SAME variable under another
    spelling. Carries both forms so the message says what to convert."""

    def __init__(self, key, found, table_name="table", hint=""):
        self.key = key
        self.found = list(found)
        self.table_name = table_name
        msg = (
            "name-boundary miss in %s: %r is absent, but the same variable IS "
            "present spelled %s. These are two spellings of ONE variable "
            "(runtime/dump form 'len(X)' vs checker/summary form 'SYM_LEN_X'; "
            "raw ordinal '..._2' vs canonical '..._mentions_<hash>'). "
            "Convert with concolic_engine.names.to_checker / to_runtime / "
            "NameSpace(alias_map=...) instead of looking the raw name up -- "
            "a falsy answer here would be misread as 'never minted' / "
            "'not seedable' / 'never evaluated'."
            % (table_name, key, ", ".join(repr(f) for f in found))
        )
        if hint:
            msg += " " + hint
        super().__init__(msg)

    def __str__(self):                       # KeyError quotes its arg otherwise
        return self.args[0] if self.args else ""


class AmbiguousSpelling(WrongSpelling):
    """The table holds the key AND a sibling spelling of it, with DIFFERENT
    values — so the table itself straddles the boundary and no lookup on it
    can be trusted. Only raised when `strict_ambiguity=True`."""

    def __init__(self, key, found, table_name="table"):
        self.key = key
        self.found = list(found)
        self.table_name = table_name
        KeyError.__init__(self, (
            "ambiguous name in %s: %r and its other spelling(s) %s are BOTH "
            "present with different values. The table was built from two "
            "stages at once; normalize it (NameSpace.normalized) before "
            "looking anything up in it."
            % (table_name, key, ", ".join(repr(f) for f in found))
        ))


# --------------------------------------------------------------------------
# length spelling
# --------------------------------------------------------------------------

def to_checker(name):
    """Runtime/dump spelling -> checker spelling: ``len(X)`` -> ``SYM_LEN_X``.

    Works on whole names and on expressions carrying them. IDEMPOTENT: a name
    already in checker spelling comes back unchanged. None/'' pass through."""
    if not name:
        return name
    return LEN_RE.sub(r"SYM_LEN_\1", name)


def to_runtime(name):
    """Checker spelling -> runtime/dump spelling: ``SYM_LEN_X`` -> ``len(X)``.

    Works on whole names and on expressions. IDEMPOTENT. None/'' pass through."""
    if not name:
        return name
    return SYM_LEN_RE.sub(r"len(\1)", name)


def is_runtime_len(name):
    """True if `name` carries at least one ``len(...)``."""
    return bool(name) and bool(LEN_RE.search(name))


def is_checker_len(name):
    """True if `name` carries at least one ``SYM_LEN_...``."""
    return bool(name) and bool(SYM_LEN_RE.search(name))


def len_spellings(name):
    """Both length spellings of `name` (one element when it is not a length)."""
    if not name:
        return [name]
    out = [name]
    for f in (to_checker(name), to_runtime(name)):
        if f not in out:
            out.append(f)
    return out


def normalize(name):
    """The form used to decide "same variable": checker spelling."""
    return to_checker(name)


def same_variable(a, b):
    """Do these two names denote the same variable, modulo length spelling?"""
    return normalize(a) == normalize(b)


# --------------------------------------------------------------------------
# ordinal <-> canonical
# --------------------------------------------------------------------------

def _ordinal_pattern(amap):
    """Longest name first; never match a name as the PREFIX of a longer ordinal
    (``records_1`` inside ``records_11``). Mirrors `assumptions.renamer`."""
    return re.compile(
        r"(" + "|".join(sorted(map(re.escape, amap), key=len, reverse=True))
        + r")(?![0-9])")


class NameSpace:
    """A dict lookup that is LOUD about the two name spellings.

    >>> ns = NameSpace({"SYM_LEN_rows": 3}, name="index lens")
    >>> ns.get("SYM_LEN_rows")
    3
    >>> ns.get("SYM_LEN_other")          # genuine absence -> normal negative
    >>> ns.get("len(rows)")              # doctest: +IGNORE_EXCEPTION_DETAIL
    Traceback (most recent call last):
    concolic_engine.names.WrongSpelling: ...

    `alias_map` is an ordinal->canonical map (`assumptions.alias_map_for`).
    Given one, ordinal/canonical forms join the sibling set too, in both
    directions and in combination with either length spelling.
    """

    def __init__(self, table, name="table", alias_map=None,
                 strict_ambiguity=False):
        self.table = table if table is not None else {}
        self.name = name
        self.strict_ambiguity = strict_ambiguity
        self.alias_map = dict(alias_map or {})
        self._pat = _ordinal_pattern(self.alias_map) if self.alias_map else None
        self._inv = {}
        for o, c in self.alias_map.items():
            self._inv.setdefault(c, []).append(o)
        # The sibling SET is a pure function of (key, alias_map), so it is
        # memoized: the miss path runs in the inner loop of every index scan
        # and the regex work would otherwise be paid per dump. Table
        # MEMBERSHIP is never cached -- seed dicts are mutated in place.
        self._sib_cache = {}

    # -- conversions ------------------------------------------------------
    def to_canonical(self, name):
        """Ordinal -> canonical, via the alias map. Identity without one, and
        identity for a name carrying no ordinal. IDEMPOTENT (a canonical is
        never itself a key of the map)."""
        if not name or self._pat is None:
            return name
        return self._pat.sub(lambda m: self.alias_map[m.group(1)], name)

    def to_ordinals(self, name):
        """Every ordinal form of `name` — the alias map is MANY-TO-ONE, so a
        canonical may be backed by several ordinals. [] when none apply."""
        if not name or not self._inv:
            return []
        out = []
        for canon, ords in self._inv.items():
            if canon in name:
                for o in ords:
                    v = name.replace(canon, o)
                    if v != name and v not in out:
                        out.append(v)
        return out

    def siblings(self, key):
        """Every OTHER name denoting the same variable as `key`: the other
        length spelling, the canonical/ordinal forms, and the combinations."""
        hit = self._sib_cache.get(key)
        if hit is not None:
            return hit
        out = self._sib_cache[key] = self._siblings_uncached(key)
        if len(self._sib_cache) > 200000:            # bound a pathological scan
            self._sib_cache.clear()
        return out

    def _siblings_uncached(self, key):
        forms = {key}
        for _ in range(2):                      # close the cross product
            grown = set(forms)
            for f in forms:
                grown.update(len_spellings(f))
                c = self.to_canonical(f)
                if c:
                    grown.add(c)
                grown.update(self.to_ordinals(f))
            if grown == forms:
                break
            forms = grown
        forms.discard(key)
        return sorted(forms)

    # -- lookups ----------------------------------------------------------
    def _present_siblings(self, key):
        return [s for s in self.siblings(key) if s in self.table]

    def get(self, key, default=None):
        """`table[key]`, except that a miss WHICH IS REALLY A SPELLING MISS
        raises `WrongSpelling` naming both forms. A genuine absence — no
        sibling spelling present either — returns `default`, silently, exactly
        as `dict.get` would."""
        if key in self.table:
            if self.strict_ambiguity:
                sibs = [s for s in self._present_siblings(key)
                        if self.table[s] != self.table[key]]
                if sibs:
                    raise AmbiguousSpelling(key, sibs, self.name)
            return self.table[key]
        sibs = self._present_siblings(key)
        if sibs:
            raise WrongSpelling(key, sibs, self.name)
        return default

    def has(self, key):
        """`key in table`, loud on a spelling miss. Use instead of ``in``."""
        sentinel = object()
        return self.get(key, sentinel) is not sentinel

    __contains__ = has

    def require(self, key):
        """Like `get`, but a genuine absence raises KeyError too — naming both
        spellings, so the message is useful either way."""
        sentinel = object()
        v = self.get(key, sentinel)
        if v is sentinel:
            raise KeyError(
                "%r is absent from %s under EVERY spelling (tried: %s). This "
                "is a genuine absence, not a name-boundary miss."
                % (key, self.name, ", ".join([repr(key)]
                                             + [repr(s) for s in self.siblings(key)])))
        return v

    def resolve(self, key, default=None):
        """The FORGIVING sibling of `get`: returns the value under whichever
        spelling the table actually uses, without raising. For call sites that
        want the lookup to work rather than to complain."""
        if key in self.table:
            return self.table[key]
        for s in self.siblings(key):
            if s in self.table:
                return self.table[s]
        return default

    def keys_for(self, name):
        """EVERY key of the table denoting the same variable as `name` --
        itself if present, plus every present sibling spelling/ordinal.

        This is the many-to-one seed-key resolution the batch constructors
        keep re-implementing by hand (`_ordinals_raw`, `inv.get(canon)`): the
        alias map is many-to-one BY DESIGN, so seeding one ordinal
        contradicts the demand whenever the path takes another -- all of them
        must be written. Returns [] for a genuine absence, which is the only
        honest "not seedable"."""
        out = [name] if name in self.table else []
        out += [s for s in self.siblings(name) if s in self.table]
        seen, uniq = set(), []
        for k in out:
            if k not in seen:
                seen.add(k)
                uniq.append(k)
        return uniq

    # -- table hygiene ----------------------------------------------------
    def normalized(self):
        """The table re-keyed into checker/canonical form — every entry
        reachable under one spelling. Later duplicates do not clobber earlier
        ones with a different value; that is reported instead."""
        out, clashes = {}, []
        for k, v in self.table.items():
            nk = to_checker(self.to_canonical(k))
            if nk in out and out[nk] != v:
                clashes.append(nk)
            else:
                out[nk] = v
        if clashes:
            raise AmbiguousSpelling(clashes[0], [], self.name)
        return out

    def audit(self, keys):
        """Which of `keys` would MISS on spelling against this table. Returns
        ``{key: [present siblings]}`` — the sweep tool for an existing script:
        run it over the names a call site looks up and see what it has been
        silently answering 'no' to."""
        out = {}
        for k in keys:
            if k in self.table:
                continue
            sibs = self._present_siblings(k)
            if sibs:
                out[k] = sibs
        return out

    def __len__(self):
        return len(self.table)

    def __repr__(self):
        return "NameSpace(%s, %d entries)" % (self.name, len(self.table))
