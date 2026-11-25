#!/bin/sh
# Final 1600x900 captures into /tmp/webshots
D=$(dirname "$0"); O=/tmp/webshots; mkdir -p $O
s() { timeout 400 python3 "$D/shot.py" "$O/$1.png" "$2" 1600 900 --wait ${3:-0.5} 2>&1 | grep -v "GPU stall\|PCFSoft\|agent-proxy\|accounts.google\|Allowed\|Use the Read\|^$"; }
s title "shot=title" 1.5
s paint "shot=paint"
s cats "shot=cats" 2
s dogs "shot=dogs" 2
s dogfp "shot=dogfp&breed=shiba&nolock=1"
s dogfp_corgi "shot=dogfp&breed=corgi&nolock=1"
s dogfp_bull "shot=dogfp&breed=bull&nolock=1"
s dogfp_poodle "shot=dogfp&breed=poodle&nolock=1"
s reveal "shot=reveal&nolock=1"
s room "shot=room"
s painted "shot=painted"
s pose "shot=poses&row=0" 2
s pose2 "shot=poses&row=1" 2
s pose3 "shot=poses&row=2" 2
