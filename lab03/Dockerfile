FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends cron \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

WORKDIR /app

COPY currency_exchange_rate.py cronjob entrypoint.sh ./
RUN chmod +x entrypoint.sh && crontab cronjob

ENTRYPOINT ["/app/entrypoint.sh"]
