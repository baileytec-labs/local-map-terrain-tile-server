# Dockerfile for the monthly refresh scheduler
#
# Runs crond inside a container that calls each service's refresh script
# on the 1st of every month at 3:00 AM (imagery), 3:15 AM (terrain), 3:30 AM (buildings).
#
# To run manually:
#   docker compose up -d gev-scheduler
#
# To trigger a refresh immediately:
#   docker exec gev-scheduler /stack/imagery/scripts/refresh-monthly.sh
#   docker exec gev-scheduler /stack/terrain/scripts/refresh-monthly.sh
#   docker exec gev-scheduler /stack/buildings/scripts/refresh-monthly.sh

FROM alpine:latest

RUN apk add --no-cache docker-cli bash curl gdal aws-cli \
    && curl -fsSL https://github.com/duckdb/duckdb/releases/download/v1.3.1/duckdb_cli-linux-amd64.zip -o /tmp/duckdb.zip \
    && unzip /tmp/duckdb.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/duckdb \
    && rm /tmp/duckdb.zip

COPY crontab /etc/crontabs/root
RUN chmod 0640 /etc/crontabs/root

CMD ["crond", "-f"]
