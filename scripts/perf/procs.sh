#!/bin/bash
# procs.sh <fp tool> <Cra pid>: each process of a running Cra with its footprint (MB) and Chromium --type.
FP="$1"
for p in $2 $(pgrep -P "$2"); do
  mb=$("$FP" $p --self | python3 -I -c 'import json,sys; print(round(json.load(sys.stdin)["fpMB"]))')
  t=$(ps -o command= -p $p | grep -o -- '--type=[a-z-]*' | head -1)
  s=$(ps -o command= -p $p | grep -o -- '--utility-sub-type=[a-zA-Z.]*' | head -1)
  echo "$mb MB  pid $p ${t:---type=browser} ${s#--utility-sub-type=}"
done | sort -rn
