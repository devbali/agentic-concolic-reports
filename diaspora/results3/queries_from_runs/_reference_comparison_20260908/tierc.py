#!/usr/bin/env python3
"""Tier C: join-substituted, blockaid-convention variant of an extracted policy (SCRATCH ONLY).
Rules are applied textually to the single-line views; every applied rule is recorded per view."""
import re, sys, json
ENDPOINT, SRC, OUT, MAP = sys.argv[1:5]

def load(path):
    out = []
    for line in open(path):
        if line.lstrip().startswith("--"): continue
        s = line.strip().rstrip(";").strip()
        if s.upper().startswith("SELECT"): out.append(s)
    return out

def from_tables(sql):
    m = re.search(r"\bFROM\s+(.*?)(\s+WHERE\s+|$)", sql)
    frm = m.group(1)
    frm2 = re.sub(r"\bON\b.*?(?=(,|\bINNER JOIN\b|\bLEFT OUTER JOIN\b|$))", "", frm)
    out = []
    for t in re.split(r",|\bINNER JOIN\b|\bLEFT OUTER JOIN\b", frm2):
        t = t.strip()
        if not t: continue
        mm = re.match(r"`(\w+)`(?:\s+AS\s+`(\w+)`)?", t)
        if mm: out.append(mm.group(2) or mm.group(1))
    return out

def add_from(sql, extra):
    if re.search(r"\s+WHERE\s+", sql):
        return re.sub(r"(\s+WHERE\s+)", ", " + extra + r"\1", sql, count=1)
    return sql + ", " + extra

def add_where(sql, pred):
    return sql + " AND " + pred if re.search(r"\s+WHERE\s+", sql) else sql + " WHERE " + pred

def ensure_me(sql, state):
    if not state.get("me"):
        sql = add_from(sql, "`people` AS `me`"); sql = add_where(sql, "`me`.`owner_id` = _MY_UID"); state["me"] = True
    return sql

PRINCIPAL = "_SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id"

def aggregates(sql, rules):
    if sql.startswith("SELECT COUNT(*) FROM"):
        pks = ", ".join(f"`{t}`.`id`" for t in from_tables(sql))
        sql = "SELECT " + pks + sql[len("SELECT COUNT(*)"):]; rules.append("COUNT(*)->pk-columns (blockaid StripCountStar, generalised to every FROM table)")
    m = re.match(r"SELECT SUM\(`(\w+)`\.`(\w+)`\) FROM", sql)
    if m:
        sql = "SELECT `%s`.`id`, `%s`.`%s`" % (m.group(1), m.group(1), m.group(2)) + sql[len(m.group(0)) - len(" FROM"):]; rules.append("SUM(t.A)->SELECT t.PK, t.A (blockaid paper rule: pk reveals multiplicity of A without duplicate rows)")
    if sql.startswith("SELECT DISTINCT "):
        sql = "SELECT " + sql[len("SELECT DISTINCT "):]; rules.append("DISTINCT dropped (set semantics)")
    return sql

def conversations(sql, rules):
    st = {}
    if PRINCIPAL in sql:
        sql = ensure_me(sql, st); sql = sql.replace(PRINCIPAL, "`me`.`id`"); rules.append("C1 principal person_id -> people AS me, me.owner_id=_MY_UID")
    p = "_SYM_RESULT_ActiveRecord__Calculations_pluck_2_pluck_author_id"
    if p in sql:
        sql = ensure_me(sql, st)
        sql = add_from(sql, "`messages` AS `m_p`, `conversation_visibilities` AS `cv_p`")
        sql = add_where(sql, "`m_p`.`conversation_id` = `cv_p`.`conversation_id` AND `cv_p`.`person_id` = `me`.`id`")
        sql = sql.replace(p, "`m_p`.`author_id`"); rules.append("C2 pluck author_id -> producer join (messages of my conversations; views 33/34 minus the unread arm)")
    for p in ("_SYM_RESULT_ActiveRecord__Relation_to_a_1_row_conversation_author_id", "_SYM_RESULT_ActiveRecord__Relation_to_a_2_row_conversation_author_id"):
        if p in sql:
            sql = ensure_me(sql, st)
            sql = add_from(sql, "`conversations` AS `c_p`, `conversation_visibilities` AS `cv_p`")
            sql = add_where(sql, "`c_p`.`id` = `cv_p`.`conversation_id` AND `cv_p`.`person_id` = `me`.`id`")
            sql = sql.replace(p, "`c_p`.`author_id`"); rules.append("C3 conversation row author_id -> producer join (conversations visible to me; view 41)")
    if "LEFT OUTER JOIN `conversations`" in sql:
        sql = sql.replace("LEFT OUTER JOIN `conversations`", "INNER JOIN `conversations`"); rules.append("C4 LEFT OUTER JOIN conversations -> INNER (FK conversation_visibilities.conversation_id -> conversations.id)")
    sql = aggregates(sql, rules)
    return [sql]

def comments(sql, rules):
    st = {}
    if PRINCIPAL in sql:
        sql = ensure_me(sql, st); sql = sql.replace(PRINCIPAL, "`me`.`id`"); rules.append("M1 principal person_id -> people AS me, me.owner_id=_MY_UID")
    n = len(re.findall(r"IN \(`\w+`\.`\w+`, _SYM_RESULT_ActiveRecord__Relation_(?:records|to_a)_\d_row2_(?:person_id|author_id)\)", sql))
    if n:
        sql = re.sub(r"IN \((`\w+`\.`\w+`), _SYM_RESULT_ActiveRecord__Relation_(?:records|to_a)_\d_row2_(?:person_id|author_id)\)", r"= \1", sql)
        rules.append("M2 IN(join-col, row-2 placeholder of the SAME relation) -> = join-col")
    sql = aggregates(sql, rules)
    return [sql]

def people(sql, rules):
    st = {}
    sql = re.sub(r"`(share_visibilities|contacts|blocks)`\.`user_id` = 1\b", r"`\1`.`user_id` = _MY_UID", sql)
    sql = re.sub(r"`notifications`\.`recipient_id` = 1\b", "`notifications`.`recipient_id` = _MY_UID", sql)
    if "_MY_UID" in sql and "= 1 OR" not in sql: pass
    if re.search(r"= _MY_UID", sql) and "P1" not in rules and ("`user_id` = _MY_UID" in sql or "`recipient_id` = _MY_UID" in sql): rules.append("P1 literal principal id 1 -> _MY_UID (POLICY_HEADER F6)")
    if "= `Post`" in sql or "= `admin`" in sql:
        sql = sql.replace("= `Post`", "= 'Post'").replace("= `admin`", "= 'admin'"); rules.append("P8 double-quoted string literal (app SQL) rendered as identifier -> string literal")
    if "_assoc_person_id" in sql:
        sql = ensure_me(sql, st); sql = sql.replace("_assoc_person_id", "`me`.`id`"); rules.append("P2 _assoc_person_id (people WHERE owner_id = SYM_USER_PE_id) -> people AS me, me.owner_id=_MY_UID")
    if "_assoc_profile_id" in sql:
        sql = add_from(sql, "`profiles` AS `shown_pr`, `people` AS `shown`")
        sql = add_where(sql, "`shown_pr`.`person_id` = `shown`.`id` AND `shown`.`closed_account` = FALSE")
        sql = sql.replace("_assoc_profile_id", "`shown_pr`.`id`"); rules.append("P3 _assoc_profile_id (profiles WHERE person_id = shown person) -> profiles/people join, closed_account = FALSE")
    m = re.search(r"`people`\.`owner_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_[12]_id", sql)
    if m:
        sql = sql.replace(m.group(0), "`people`.`owner_id` = `u_by`.`id`"); sql = add_from(sql, "`users` AS `u_by`")
        rules.append("P6 User.find_by(username:) id (WHERE dropped by interceptor) -> users join, username param broadened")
    # P7: restore the parenthesised OR and split the two arms
    mo = re.search(r"`share_visibilities`\.`user_id` = _MY_UID OR `(posts0?|photos)`\.`public` = 't'", sql)
    if mo:
        tbl = mo.group(1)
        rules.append("P7 parentheses restored: (share_visibilities.user_id = _MY_UID OR %s.public = TRUE) per raw dump SQL; split into sv-arm and public-arm views" % tbl)
        armA = sql.replace(mo.group(0), "`share_visibilities`.`user_id` = _MY_UID")
        armB = sql.replace(mo.group(0), "`%s`.`public` = TRUE" % tbl)
        # arm A: LEFT OUTER JOIN sv -> INNER
        armA = armA.replace("LEFT OUTER JOIN `share_visibilities`", "INNER JOIN `share_visibilities`")
        # arm B: drop share_visibilities entirely
        armB = re.sub(r"\s*LEFT OUTER JOIN `share_visibilities` ON `share_visibilities`\.`shareable_id` = `\w+`\.`id` AND `share_visibilities`\.`shareable_type` = '\w+'", "", armB)
        armB = armB.replace(", `share_visibilities`", "")
        head, _, where = armB.partition(" WHERE ")
        atoms = [a for a in where.split(" AND ") if "share_visibilities" not in a]
        armB = head + " WHERE " + " AND ".join(atoms)
        outs = [aggregates(armA, rules), aggregates(armB, [])]
        return outs
    if "'t'" in sql: rules.append("WARNING: residual 't' literal")
    sql = aggregates(sql, rules)
    return [sql]

fn = {"conversations_index": conversations, "comments_index": comments, "people_show": people}[ENDPOINT]
views = load(SRC)
out_views, mapping = [], []
for i, v in enumerate(views):
    rules = []
    outs = fn(v, rules)
    residue = [o for o in outs if re.search(r"_SYM_|_assoc_", o)]
    mapping.append({"orig_idx1": i + 1, "orig": v, "rules": rules, "out": outs, "residue": bool(residue), "out_idx1": [len(out_views) + k + 1 for k in range(len(outs))]})
    out_views.extend(outs)
with open(OUT, "w") as f:
    f.write("-- TIER C (scratch): join-substituted / blockaid-convention variant of %s\n" % SRC)
    for v in out_views: f.write(v + ";\n")
json.dump(mapping, open(MAP, "w"), indent=1)
n_res = sum(1 for m in mapping if m["residue"])
print(f"{ENDPOINT}: {len(views)} views -> {len(out_views)} tier-C views; {n_res} original views still carry a placeholder (residue)")
for m in mapping:
    if m["residue"]: print(f"   residue orig#{m['orig_idx1']}: {re.findall(r'_SYM_[A-Za-z0-9_]+|_assoc_[a-z_]+', m['orig'])}")
