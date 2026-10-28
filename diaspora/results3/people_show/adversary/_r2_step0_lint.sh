#!/usr/bin/env bash
# R2 step 0: hardening_lint on the fresh 078f90c corpus with R1 concrete runs (H6).
cd /home/dev/project
export PYTHONPATH=src
python3 reports/diaspora/tools/hardening_lint.py reports/diaspora/results3/people_show \
  --runs reports/diaspora/results3/people_show/adversary/runs/C01_auth_self_html.json \
         reports/diaspora/results3/people_show/adversary/runs/C02_auth_other_html.json \
         reports/diaspora/results3/people_show/adversary/runs/C03_auth_other_mutual_html.json \
         reports/diaspora/results3/people_show/adversary/runs/C04_auth_blocked_json.json \
         reports/diaspora/results3/people_show/adversary/runs/C05_auth_mobile.json \
         reports/diaspora/results3/people_show/adversary/runs/C06_anon_self_html.json \
         reports/diaspora/results3/people_show/adversary/runs/C07_anon_remote_401.json \
         reports/diaspora/results3/people_show/adversary/runs/C08_closed_account.json \
         reports/diaspora/results3/people_show/adversary/runs/C09_missing_person.json \
         --sample 2000
echo "LINT_EXIT=$?"