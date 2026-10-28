#!/usr/bin/env python3
"""Test the classify() search regex."""
import re
conj = '(SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found == True)'
m = re.search(r'([A-Za-z0-9_]+)_(?:_not_found|_closed_account)\s*==\s*True', conj)
print("search result:", m)
if m:
    print("group1:", repr(m.group(1)))
    print("group0:", repr(m.group(0)))
else:
    print("NO MATCH")