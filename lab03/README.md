# lab03 — Task Scheduler (cron) Configuration

This lab runs the script `currency_exchange_rate.py` from [lab02](../lab02) on a schedule. The
schedule is set with cron in a Docker container:

| When                  | Command                               |
|-----------------------|---------------------------------------|
| Every day at 06:00    | MDL to EUR rate for the previous day  |
| Every Friday at 17:00 | MDL to USD rate for the previous week |

The script takes one date. For "the previous week" the job uses the date 7 days before the run.

## Project structure

| File                        | Purpose                                                                                                                   |
|-----------------------------|---------------------------------------------------------------------------------------------------------------------------|
| `currency_exchange_rate.py` | The script from lab02. Gets a rate from the service and saves it to `data/*.json`.                                        |
| `cronjob`                   | The crontab with the two tasks. The output of each task goes to `/var/log/cron.log`.                                      |
| `entrypoint.sh`             | Container start script. Saves the environment to `/etc/environment`, creates the log file, shows the log and starts cron. |
| `Dockerfile`                | Builds the image: `python:3.12-slim`, installs `cron`, copies the files and installs `cronjob` with `crontab`.            |
| `docker-compose.yml`        | Builds the image and starts the container with `API_KEY` and `API_URL`.                                                   |
| `README.md`                 | This file.                                                                                                                |

The script uses only the Python standard library, so the image does not install packages with `pip`.

### Notes on the cronjob file

- cron starts jobs with an almost empty environment. `entrypoint.sh` writes the container
  environment to `/etc/environment`, and cron loads this file for each job. This is how
  `API_KEY` and `API_URL` get to the script.
- In a crontab, `%` means a new line, so the date format is written as `+\%F`.
- `/usr/local/bin/python3` is an absolute path, because the `PATH` of cron does not include
  `/usr/local/bin`.
- The container time zone is UTC, so 06:00 and 17:00 are UTC.

## Build and run

1. Start the Currency Exchange Rate service from lab02prep. It must be available on port 8080 of the
   host.

   ```bash
   cd lab02prep
   cp sample.env .env
   docker compose up -d --build
   ```

2. Build and start the cron container. Use the same API key as in the `.env` file of the service.

   ```bash
   cd lab03
   API_KEY=EXAMPLE_API_KEY docker compose up -d --build
   ```

   By default, the container connects to `http://host.docker.internal:8080`. To use another
   address, set `API_URL`.

3. Stop the container:

   ```bash
   docker compose down
   ```

## Verify that cron works

Make sure that cron runs and the tasks are installed:

```bash
docker compose top
docker compose exec cron crontab -l
```

See the log. The container prints `/var/log/cron.log` to its output, so both commands show the same
lines:

```bash
docker compose logs -f cron
docker compose exec cron tail -f /var/log/cron.log
```

You do not need to wait until 06:00 or Friday. To run a task now, run its command in the container
with the same environment as cron:

```bash
docker compose exec cron sh -c '. /etc/environment 2>/dev/null; export API_KEY API_URL;
  /usr/local/bin/python3 /app/currency_exchange_rate.py MDL EUR 2025-09-01 --url "$API_URL" >> /var/log/cron.log 2>&1'
docker compose exec cron tail /var/log/cron.log
docker compose exec cron ls /app/data
```

To see a real cron run, add a task that runs every minute and watch the log:

```bash
docker compose exec cron sh -c '(crontab -l; echo "* * * * * /usr/local/bin/python3 /app/currency_exchange_rate.py MDL EUR 2025-09-01 --url \"\$API_URL\" >> /var/log/cron.log 2>&1") | crontab -'
docker compose logs -f cron
```

A good run writes lines like these to the log:

```text
MDL -> EUR on 2025-09-01: 19.4083
Saved to /app/data/MDL_EUR_2025-09-01.json
```

### Current issue

The service has rates only from `2025-01-01` to `2025-09-15`. The script rejects other dates.
The scheduled tasks use the current date, so after this period they write an error like this to the
log
and to `/app/error.log`:

```text
Error: MDL -> EUR on 2026-10-17: date 2026-10-17 is outside the available period 2025-01-01..2025-09-15
```

This shows that cron runs the task. To get a real rate, use a date in the period, as in the examples
above.
