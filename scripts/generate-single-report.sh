#!/bin/bash
# =============================================================
# generate-single-report.sh - Generate a single report on demand
#
# Used by the web application to generate reports for individual
# patients/encounters. Called via the "Print Report" button in
# the EMR (Epic Hyperspace).
#
# Usage:
#   ./generate-single-report.sh <report_name> [param=value ...]
#
# Examples:
#   ./generate-single-report.sh patient_summary patient_id=42
#   ./generate-single-report.sh billing_statement encounter_id=101
#   ./generate-single-report.sh medication_administration patient_id=42
#
# The script outputs the path to the generated PDF on stdout.
# The web application reads this path and serves the PDF to the user.
#
# Author: Marcus Chen, 2019
# Modified: Sarah Kim, 2024-02-10 - added timeout (JIRA-6100)
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/acmehealth/reports-ondemand.log"

# Source environment
if [ -f /etc/acmehealth/reports.env ]; then
    source /etc/acmehealth/reports.env
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <report_name> [param=value ...]" >&2
    exit 1
fi

REPORT_NAME="$1"
shift

echo "[$(date)] On-demand report: $REPORT_NAME $@" >> "$LOG_FILE"

# Timeout after 60 seconds - if a report takes longer than that,
# something is wrong. The billing_statement report was hanging
# occasionally due to a lock on the billing_items table. - Sarah
cd "$APP_DIR"
timeout 60 java -Xmx256m \
     -jar reports/target/clinical-reports-1.0.0.jar \
     "$REPORT_NAME" "$@" \
     2>> "$LOG_FILE"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
    echo "[$(date)] ERROR: Report $REPORT_NAME timed out after 60s" >> "$LOG_FILE"
    exit 1
fi

exit $EXIT_CODE
