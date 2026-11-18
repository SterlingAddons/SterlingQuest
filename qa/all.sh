#!/bin/bash
# the whole suite; prints one line per test file
# needs Python 3 with lupa (pip install lupa) and Pillow
cd "$(dirname "$0")"
QA="$(pwd)"
fail=0
for t in t_sync t_offline t_pack t_multi t_guide t_smoke t_interop t_resync t_zone t_ahead t_online t_newpartner t_twopc t_app t_autopair t_hasapp t_face t_favs t_details t_gidcheck t_testmode t_minimap t_status t_style; do
  out=$(timeout 600 python3 $t.py 2>&1)
  p=$(echo "$out" | grep -c "^PASS"); f=$(echo "$out" | grep -c "^FAIL")
  last=$(echo "$out" | tail -1)
  echo "$t: $p passed, $f failed  [$last]"
  if [ "$f" != "0" ] || [ "$last" != "ALL OK" ]; then fail=1; echo "$out" | grep -v "^PASS" | head -12; fi
done
for skin in wow navy; do for fs in 1 1.25; do
  out=$(FONT_SCALE=$fs python3 t_layout.py $skin -q 2>&1 | tail -n +2)
  n=$(echo "$out" | grep -c "OVERLAP\|OUTSIDE\|CUT OFF\|AMBIGUOUS")
  echo "layout $skin font x$fs: $n findings  [$(echo "$out" | tail -1)]"
  if [ "$n" != "0" ]; then fail=1; echo "$out" | head -10; fi
done; done
out=$(python3 t_layout.py wow -q cb 2>&1 | tail -n +2); echo "layout wow colour-blind: $(echo "$out" | grep -c 'OVERLAP\|OUTSIDE\|CUT OFF\|AMBIGUOUS') findings  [$(echo "$out" | tail -1)]"
cd "$QA/old-scenarios"
for f in smoke smoke_navy order cupath cu disco stranger stranger2 lookses look navycol flatshow appear place npc sect sess me me2; do
  out=$(timeout 120 python3 "$QA/old.py" $f.lua 2>&1)
  bad=$(echo "$out" | grep -v "^CHAT" | grep -v "snags:\s*0" | grep -ci "fail\b\|traceback\|attempt to\|snag\|ERR ")
  e=$(echo "$out" | grep "^ERRORS:" | tail -1)
  if [ "$bad" != "0" ] || [ "$e" != "ERRORS: 0" ]; then fail=1; echo "old/$f: PROBLEM ($bad) $e"; echo "$out" | grep -v "^CHAT" | grep -i "fail\b\|traceback\|attempt to\|snag\|ERR " | head -5; fi
done
echo "older scenario files: 19 run"
python3 "$QA/lint.py" | tail -1
[ $fail = 0 ] && echo "SUITE OK" || echo "SUITE HAS FAILURES"
