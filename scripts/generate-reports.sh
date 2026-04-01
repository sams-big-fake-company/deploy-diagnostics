#!/bin/bash
# =============================================================
# generate-reports.sh - Run the nightly report batch
#
# This script is called by cron. See cron/report-schedule.crontab
# for the schedule.
#
# Deployment: This script lives at /opt/acmehealth/reports/scripts/
# on the report server (rpt-prod-01). It's deployed by Jenkins.
#
# Author: Marcus Chen, 2019
# Modified: Sarah Kim, 2024-01-09 - added log rotation check
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/var/log/acmehealth"
LOG_FILE="$LOG_DIR/reports-$(date +%Y%m%d).log"
LOCK_FILE="/tmp/acmehealth-reports.lock"

# Source environment
if [ -f /etc/acmehealth/reports.env ]; then
    source /etc/acmehealth/reports.env
fi

# Prevent concurrent runs (happened once and generated duplicate reports)
if [ -f "$LOCK_FILE" ]; then
    LOCK_PID=$(cat "$LOCK_FILE")
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "[$(date)] ERROR: Another instance is running (PID $LOCK_PID)" >> "$LOG_FILE"
        exit 1
    else
        echo "[$(date)] WARN: Stale lock file found, removing" >> "$LOG_FILE"
        rm -f "$LOCK_FILE"
    fi
fi

echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

echo "[$(date)] Starting nightly report generation" >> "$LOG_FILE"

# Check disk space before generating reports
# Marcus learned this the hard way when /data filled up in Dec 2023
DISK_USAGE=$(df -h /data/reports/output | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    echo "[$(date)] ERROR: Disk usage at ${DISK_USAGE}% - aborting" >> "$LOG_FILE"
    # Send alert to ops
    echo "Report generation aborted - disk at ${DISK_USAGE}%" | \
        mail -s "ALERT: Report server disk full" ops-alerts@acmehealth.com
    exit 1
fi

# Run the batch
cd "$APP_DIR"
java -Xmx512m \
     -jar reports/target/clinical-reports-1.0.0.jar \
     --batch \
     >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "[$(date)] Nightly report generation completed successfully" >> "$LOG_FILE"
else
    echo "[$(date)] ERROR: Report generation failed with exit code $EXIT_CODE" >> "$LOG_FILE"
    # Alert on-call
    echo "Nightly report generation failed. Check $LOG_FILE on rpt-prod-01" | \
        mail -s "ALERT: Report generation failed" ops-alerts@acmehealth.com
fi

# Clean up old reports (keep 90 days)
RETENTION_DAYS=${REPORT_RETENTION_DAYS:-90}
echo "[$(date)] Cleaning up reports older than $RETENTION_DAYS days" >> "$LOG_FILE"
find /data/reports/output -name "*.pdf" -mtime +$RETENTION_DAYS -delete 2>> "$LOG_FILE"

# Clean up old logs (keep 30 days)
find "$LOG_DIR" -name "reports-*.log" -mtime +30 -delete 2>> "$LOG_FILE"

echo "[$(date)] Done" >> "$LOG_FILE"
exit $EXIT_CODE
