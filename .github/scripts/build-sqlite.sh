#!/usr/bin/env bash
# Builds a snapshot-enabled libsqlite3 for Linux CI.
#
# GRDB uses SQLite's snapshot API (sqlite3_snapshot_open etc.) which the
# distro's libsqlite3 omits. We compile the matching release amalgamation with
# -DSQLITE_ENABLE_SNAPSHOT and install it ahead of the system library.
set -euo pipefail

SQLITE_VERSION="${SQLITE_VERSION:-3460100}"
SQLITE_YEAR="2024"

cd "$RUNNER_TEMP"
curl -fLsS -o sqlite-amal.zip "https://www.sqlite.org/${SQLITE_YEAR}/sqlite-amalgamation-${SQLITE_VERSION}.zip"
unzip -q -o sqlite-amal.zip -d sqlite-src
cd "sqlite-src/sqlite-amalgamation-${SQLITE_VERSION}"

gcc -shared -fPIC -O2 -Wl,-soname,libsqlite3.so.0 -o libsqlite3.so.0 sqlite3.c \
  -DSQLITE_ENABLE_SNAPSHOT \
  -DSQLITE_ENABLE_FTS5 \
  -DSQLITE_ENABLE_FTS4 \
  -DSQLITE_ENABLE_RTREE \
  -DSQLITE_ENABLE_COLUMN_METADATA \
  -DSQLITE_ENABLE_UNLOCK_NOTIFY \
  -DSQLITE_ENABLE_DBSTAT_VTAB \
  -DSQLITE_THREADSAFE=1 \
  -DSQLITE_DEFAULT_MEMSTATUS=0 \
  -DHAVE_USLEEP=1 \
  -DHAVE_UTIME=1 \
  -lm -lpthread -ldl

sudo cp libsqlite3.so.0 /usr/local/lib/
sudo ln -sf /usr/local/lib/libsqlite3.so.0 /usr/local/lib/libsqlite3.so
# Point the -dev link symlink at our build so the toolchain links it too.
sudo ln -sf /usr/local/lib/libsqlite3.so.0 /usr/lib/x86_64-linux-gnu/libsqlite3.so
sudo ldconfig

echo "snapshot-enabled sqlite installed:"
nm -D /usr/local/lib/libsqlite3.so.0 | grep -c sqlite3_snapshot || true