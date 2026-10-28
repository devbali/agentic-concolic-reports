#!/usr/bin/env python3
# _scan_all_shapes.py — scan ALL campaign dumps for the C01-C09 demand shapes.
import json, glob, collections, sys, re

# demand universe (from ADVERSARY_REPORT / real-run analysis)
SHAPES = {
    "C01_find_person_by_handle":   (re.compile(r'SELECT "people".* FROM "people".*WHERE "people"\."diaspora_handle"'), "find_person WHERE diaspora_handle"),
    "C02_notifications_select":    (re.compile(r'SELECT "notifications".\* FROM "notifications".*recipient_id'), "notifications SELECT"),
    "C03_update_column_dml":       (re.compile(r'UPDATE "notifications" SET "notifications"\."unread"'), "P-1 update_column DML"),
    "C04_contact_for_find_by":     (re.compile(r'SELECT "contacts".\* FROM "contacts".*"user_id".*"person_id"'), "P-4 contact_for WHERE user_id+person_id"),
    "C05_block_for_find_by":       (re.compile(r'SELECT "blocks".\* FROM "blocks".*"person_id"'), "P-5 block_for WHERE person_id"),
    "C06_aspects_exists":          (re.compile(r'SELECT 1 AS one FROM "aspects"'), "P-2 aspects exists?"),
    "C07_photos_count_visible":    (re.compile(r'SELECT COUNT\(\*\) FROM "photos".*author_id'), "P-7 photos count author_id"),
    "C08_tags_pluck":              (re.compile(r'SELECT "tags"\."name" FROM "tags" INNER JOIN "taggings"'), "P-9 tags pluck projection"),
    "C09_roles_likes_exists":      (re.compile(r'SELECT 1 AS one FROM "roles"'), "roles exists?"),
    "C10_aspects_records":         (re.compile(r'SELECT "aspects".\* FROM "aspects".*user_id'), "aspects records"),
    "C11_services_records":        (re.compile(r'SELECT "services".\* FROM "services".*user_id'), "services records"),
    "C12_profiles_find_target":    (re.compile(r'SELECT "profiles".\* FROM "profiles".*person_id'), "profiles find_target person_id"),
    "C13_stream_posts":            (re.compile(r'SELECT .*FROM "posts"|FROM "status_messages"|for_visible_shareable_sql'), "posts/stream SQL"),
    "C14_conv_unread_sum":         (re.compile(r'SUM\("conversation_visibilities"\."unread"\)'), "conv unread SUM"),
    "C15_notif_count":             (re.compile(r'SELECT COUNT\(\*\) FROM "notifications".*recipient_id'), "notifications COUNT"),
    "C16_contacts_count":          (re.compile(r'SELECT COUNT\(\*\) FROM "contacts"'), "contacts COUNT"),
}

files = sorted(glob.glob("dump_*.json"))
by_scen = collections.defaultdict(list)
for f in files:
    scen = f.split("_")[0] + ("_" + f.split("_")[1] if f.count("_") > 1 else "")
    # better: prefix before _NNNN
    m = re.match(r"dump_(.*)_\d{4}\.json", f)
    scen = m.group(1) if m else f
    by_scen[scen].append(f)

print(f"total files: {len(files)}")
for scen in sorted(by_scen):
    fs = by_scen[scen]
    print(f"\n==== {scen} ({len(fs)} dumps) ====")
    counts = collections.Counter()
    err_types = collections.Counter()
    for f in fs:
        try:
            d = json.load(open(f))
        except Exception:
            continue
        err = d.get("error") or {}
        if err:
            err_types[err.get("type") or "?"] += 1
        notes = [str(e.get("note", "")) for e in d.get("events", []) if e.get("type") == "symbolic_call"]
        allnotes = " || ".join(notes)
        for k, (rx, desc) in SHAPES.items():
            if rx.search(allnotes):
                counts[k] += 1
    # union across dumps in scenario
    for k, (rx, desc) in SHAPES.items():
        if counts[k]:
            print(f"  {k:26s} in {counts[k]}/{len(fs)} dumps  ({desc})")
    if err_types:
        print(f"  errors: {dict(err_types)}")