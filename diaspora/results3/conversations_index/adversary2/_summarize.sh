#!/usr/bin/env bash
cd /home/dev/project/reports/diaspora/results3/conversations_index/adversary2/runs
for j in *.judge.txt; do n=${j%.judge.txt}; echo "##### $n  $(grep -c 'adversary2\] ' $n.log) requests; $(grep -o 'raised [A-Za-z:]*' $n.log | sort | uniq -c | tr '\n' ';')  probe EXIT=$(grep -o 'EXIT=[0-9]*' $n.log | tail -1)"; grep -v "^   [a-zA-Z]" $j | grep -v "^$\|^--\|^==\|NOTE-OK\|wildcard" | grep "MISMATCH\|MISSING\|STAR\|AGG\|DIFF\|RESULT\|ABSENT\|METHOD-NAME\|OUTSIDE\|error=\|real:" | sed 's/^/   /'; done
for l in *.log; do n=${l%.log}; [ -f $n.judge.txt ] || echo "##### $n NO JUDGE — probe EXIT=$(grep -o 'EXIT=[0-9]*' $l | tail -1) $(grep -i 'free()\|abort\|SIGSEGV\|fatal' $l | head -2)"; done
