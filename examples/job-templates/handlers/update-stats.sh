#!/bin/sh
# @id stats
# @label Update Stats
# @desc Wrapper that collects server + process metrics via update_stats.pl
# === Update Stats ===
# This is a simple wrapper that calls the full update_stats.pl script.
# It collects real-time server metrics (CPU, memory, disk, load average, etc.)
# and process-level stats for the server it runs on.
#
# Recommended: Run this frequently (every 30-60 seconds) in a dedicated "Monitoring" cluster.
update_stats.pl
