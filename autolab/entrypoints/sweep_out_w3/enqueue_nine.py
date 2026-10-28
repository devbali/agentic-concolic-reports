"""Enqueue the nine remaining sample endpoints (posts_destroy is the proof box)."""
import sys
sys.path.insert(0, "/home/dev/project/src_new")
from sweep.queue.store import Entry, QueueStore
from sweep.queue.cli import new_entry_id

TEN = ["blocks_create", "devise_passwords_create", "people_retrieve_remote",
       "posts_destroy", "profiles_show", "services_create", "sessions_create",
       "streams_liked", "tag_followings_destroy",
       "two_factor_authentications_recovery_codes"]
Q = "/home/dev/project/reports/autolab/entrypoints/sweep_out_w3/queue"
store = QueueStore(Q).create()
have = {e.endpoint for e in store.all()}
put = []
for name in TEN:
    if name in have:
        continue
    store.put(Entry(id=new_entry_id(name, "batch"), sweep="autolab",
                    endpoint=name, kind="batch", attempt=1))
    put.append(name)
print("enqueued:", len(put))
for n in put:
    print("  ", n)
print("counts:", store.counts())
