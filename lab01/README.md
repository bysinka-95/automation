# lab01 — disk_usage.sh

Shell script that monitors how much of a reserved volume a directory uses. The script logs the
result. It sends an email notification when usage goes above a threshold.

## What it does

1. Checks the arguments. Checks that the target directory exists, is a directory, and is readable.
2. Measures the directory size with `du -sk` and computes usage as a percentage of the reserved
   volume: `used_kb * 100 / max_kb`.
3. Appends one timestamped line to `disk_usage.log` and prints the same information to stdout.
4. If usage is **greater than** the threshold, emails an alert to the configured recipient and exits
   with code `3`.

The script measures all sizes in kilobytes. A directory smaller than one megabyte still gets an
exact percentage, and `max_size_mb` accepts decimals such as `0.5`. The script reports the
percentage with one decimal place. The script compares kilobytes, not the rounded percentage, so the
alert decision stays exact.

Output uses the unit that reads best: kilobytes up to 1024 KB, megabytes with one decimal above
that. The script prints the absolute path of the directory and writes to an absolute log path. A log
line stays readable whatever the working directory was.

## Usage

```
./disk_usage.sh <directory> <max_size_mb> [threshold_percent]
```

| Argument            | Required | Description                                                       |
|---------------------|----------|-------------------------------------------------------------------|
| `directory`         | yes      | Directory to monitor                                              |
| `max_size_mb`       | yes      | Volume reserved for the directory, in megabytes, decimals allowed |
| `threshold_percent` | no       | Alert threshold in percent, integer 1..100 (default `80`)         |

### Environment variables

| Variable      | Default                             | Purpose                         |
|---------------|-------------------------------------|---------------------------------|
| `ALERT_EMAIL` | `$USER`                             | Notification recipient          |
| `LOG_FILE`    | `disk_usage.log` next to the script | Log file path                   |
| `MAIL_CMD`    | `mail`                              | Mail client used to send alerts |

### Exit codes

| Code | Meaning                                        |
|------|------------------------------------------------|
| `0`  | Usage is at or below the threshold             |
| `1`  | Invalid arguments                              |
| `2`  | Directory missing, not a directory, unreadable |
| `3`  | Threshold exceeded, notification sent          |

## Examples

Monitor `/var/log` against a 500 MB quota with the default 80% threshold:

```console
$ ./disk_usage.sh /var/log 500
/var/log: 15.4% (77.2 MB of 500.0 MB)
```

Same directory with a stricter 15% threshold. The script sends an alert:

```console
$ ALERT_EMAIL=admin@example.com ./disk_usage.sh /var/log 500 15
/var/log: 15.4% (77.2 MB of 500.0 MB)
Alert sent to admin@example.com
```

A small directory against a fractional quota, given as a relative path. Sizes at or below 1024 KB
stay in kilobytes, and the output names the absolute path:

```console
$ ./disk_usage.sh ../ 0.5
/absolute/path/to/file: 62.5% (320 KB of 512 KB)
```

Error handling:

```console
$ ./disk_usage.sh /nonexistent 500
Error: '/nonexistent' does not exist.

$ ./disk_usage.sh /var/log
Error: expected 2 or 3 arguments, got 1.
Usage: ./disk_usage.sh <directory> <max_size_mb> [threshold_percent]
  directory         directory to monitor
  max_size_mb       max volume reserved for the directory, in MB (decimals allowed)
  threshold_percent alert threshold in percent (default: 80)
```

Log file contents after a few runs:

```
2026-09-14 10:00:01 /var/log 42.1% (210.4 MB of 500.0 MB)
2026-09-14 11:00:01 /var/log 51.3% (256.5 MB of 500.0 MB)
```

Run every hour via cron:

```cron
0 * * * * ALERT_EMAIL=admin@example.com /home/user/automation/lab01/disk_usage.sh /var/log 500 80
```
