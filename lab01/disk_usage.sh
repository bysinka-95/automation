#!/usr/bin/env bash
#
# disk_usage.sh - monitor disk space usage of a directory against a quota.
#
# Usage: ./disk_usage.sh <directory> <max_size_mb> [threshold_percent]
#
# Writes one line per run to disk_usage.log and sends an email notification
# when usage exceeds the threshold (default 80%).
#
# Sizes are measured in kilobytes, so a directory smaller than one megabyte
# still reports an exact percentage. max_size_mb accepts decimals (e.g. 0.5).
# Sizes above 1024 KB are printed as megabytes. Paths are printed absolute.
#
# Environment overrides:
#   ALERT_EMAIL - notification recipient (default: current user)
#   LOG_FILE    - log file path (default: disk_usage.log next to this script)
#   MAIL_CMD    - mail client used to send the alert (default: mail)

set -euo pipefail

ALERT_EMAIL="${ALERT_EMAIL:-${USER:-root}}"
LOG_FILE="${LOG_FILE:-$(dirname "$0")/disk_usage.log}"
MAIL_CMD="${MAIL_CMD:-mail}"

if ! log_dir=$(cd "$(dirname "$LOG_FILE")" 2>/dev/null && pwd -P); then
    echo "Error: log directory '$(dirname "$LOG_FILE")' does not exist." >&2
    exit 2
fi
LOG_FILE="$log_dir/$(basename "$LOG_FILE")"

usage() {
    echo "Usage: $0 <directory> <max_size_mb> [threshold_percent]" >&2
    echo "  directory         directory to monitor" >&2
    echo "  max_size_mb       max volume reserved for the directory, in MB (decimals allowed)" >&2
    echo "  threshold_percent alert threshold in percent (default: 80)" >&2
    exit 1
}

is_number() {
    [[ $1 =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

# Print a kilobyte count as "123 KB", or as "1.2 MB" above 1024 KB.
format_size() {
    awk -v kb="$1" 'BEGIN { if (kb > 1024) printf "%.1f MB", kb / 1024; else printf "%d KB", kb }'
}

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Error: expected 2 or 3 arguments, got $#." >&2
    usage
fi

directory="$1"
max_size_mb="$2"
threshold="${3:-80}"

if [ ! -e "$directory" ]; then
    echo "Error: '$directory' does not exist." >&2
    exit 2
fi

if [ ! -d "$directory" ]; then
    echo "Error: '$directory' is not a directory." >&2
    exit 2
fi

if [ ! -r "$directory" ]; then
    echo "Error: directory '$directory' is not readable." >&2
    exit 2
fi

# Report the absolute path, so a log line stays meaningful whatever the
# working directory was at the time of the run.
directory=$(cd "$directory" && pwd -P)

if ! is_number "$max_size_mb"; then
    echo "Error: max_size_mb must be a positive number, got '$max_size_mb'." >&2
    exit 1
fi

max_kb=$(awk -v mb="$max_size_mb" 'BEGIN { printf "%.0f", mb * 1024 }')
if [ "$max_kb" -le 0 ]; then
    echo "Error: max_size_mb must be greater than 0, got '$max_size_mb'." >&2
    exit 1
fi

if ! [[ $threshold =~ ^[0-9]+$ ]] || [ "$threshold" -lt 1 ] || [ "$threshold" -gt 100 ]; then
    echo "Error: threshold_percent must be an integer in 1..100, got '$threshold'." >&2
    exit 1
fi

used_kb=$(du -sk "$directory" | cut -f1)
percent=$(awk -v u="$used_kb" -v m="$max_kb" 'BEGIN { printf "%.1f", u * 100 / m }')

used_size=$(format_size "$used_kb")
max_size=$(format_size "$max_kb")

printf '%s %s %s%% (%s of %s)\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$directory" "$percent" "$used_size" "$max_size" >> "$LOG_FILE"

echo "$directory: ${percent}% (${used_size} of ${max_size})"

# Compared in kilobytes so the decision never depends on the rounded percent.
if [ $(( used_kb * 100 )) -gt $(( threshold * max_kb )) ]; then
    subject="[disk_usage] $directory at ${percent}% of quota"
    body="Directory : $directory
          Host      : $(hostname)
          Used      : ${used_size} of ${max_size} (${percent}%)
          Threshold : ${threshold}%
          Time      : $(date '+%Y-%m-%d %H:%M:%S')"

    if command -v "$MAIL_CMD" >/dev/null 2>&1; then
        printf '%s\n' "$body" | "$MAIL_CMD" -s "$subject" "$ALERT_EMAIL"
        echo "Alert sent to $ALERT_EMAIL" >&2
    else
        echo "Warning: '$MAIL_CMD' not found, alert not sent to $ALERT_EMAIL." >&2
    fi
    exit 3
fi
