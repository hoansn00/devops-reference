#!/usr/bin/env bash
# Restore the newest backup into a scratch database and compare it, document by
# document count, against the live one. Nothing touches the live data.
set -uo pipefail
PORT=27217
AR=$(ls -1t /opt/omada-backups/omada-*.archive | grep -v omada_data | head -1)
echo "archive: $AR"

echo
echo '=== live: collections and document counts ==='
mongosh --quiet --port $PORT omada --eval '
  db.getCollectionNames().sort().forEach(c => print(c.padEnd(34) + db.getCollection(c).countDocuments()))' > /tmp/live.txt
wc -l < /tmp/live.txt | xargs echo 'collections:'
head -8 /tmp/live.txt

echo
echo '=== restore into scratch db "omada_restoretest" ==='
mongosh --quiet --port $PORT --eval 'db.getSiblingDB("omada_restoretest").dropDatabase()' >/dev/null
mongorestore --quiet --port $PORT --gzip --archive="$AR" \
  --nsFrom='omada.*' --nsTo='omada_restoretest.*' 2>&1 | tail -3
echo "restore exit: $?"

echo
echo '=== restored: collections and document counts ==='
mongosh --quiet --port $PORT omada_restoretest --eval '
  db.getCollectionNames().sort().forEach(c => print(c.padEnd(34) + db.getCollection(c).countDocuments()))' > /tmp/restored.txt
wc -l < /tmp/restored.txt | xargs echo 'collections:'

echo
echo '=== diff live vs restored ==='
if diff -q /tmp/live.txt /tmp/restored.txt >/dev/null; then
  echo 'IDENTICAL - every collection and every document count matches'
else
  echo 'DIFFERENCES:'
  diff /tmp/live.txt /tmp/restored.txt | head -20
fi

echo
echo '=== spot check: a real document survives the round trip ==='
mongosh --quiet --port $PORT --eval '
  const a = db.getSiblingDB("omada").setting.findOne();
  const b = db.getSiblingDB("omada_restoretest").setting.findOne({_id: a && a._id});
  print("live  _id: " + (a ? a._id : "none"));
  print("restored : " + (b ? "found, fields=" + Object.keys(b).length : "MISSING"));
  print("equal    : " + (a && b ? JSON.stringify(a) === JSON.stringify(b) : "n/a"));'

echo
echo '=== cleanup scratch db ==='
mongosh --quiet --port $PORT --eval 'db.getSiblingDB("omada_restoretest").dropDatabase(); print("dropped")'
echo '=== live still intact ==='
mongosh --quiet --port $PORT omada --eval 'print("collections still live: " + db.getCollectionNames().length)'
