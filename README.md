# Clinical Reports System

JasperReports-based report generation for Acme Health Systems. Produces PDF clinical and financial reports from the clinical data warehouse (PostgreSQL).

## Overview

This system generates 7 active reports used by nursing, pharmacy, finance, and medical staff leadership. Reports are generated on a schedule via cron and on-demand via the EMR (Epic Hyperspace "Print Report" button).

See [docs/report-inventory.md](docs/report-inventory.md) for the full report list, schedules, and owners.

## Architecture

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│  Epic Hyperspace │────>│  Report Server        │────>│  Clinical Data  │
│  (on-demand)     │     │  rpt-prod-01          │     │  Warehouse      │
├─────────────────┤     │                        │     │  (PostgreSQL)   │
│  Cron Schedule   │────>│  Java + JasperReports  │     │                 │
│  (nightly/hourly)│     │  .jrxml templates      │     │  acme-warehouse │
└─────────────────┘     │                        │     │  -prod.internal │
                        └──────────┬─────────────┘     └─────────────────┘
                                   │
                                   v
                        ┌──────────────────────┐
                        │  /data/reports/output │
                        │  (NFS → OnBase DMS)   │
                        └──────────────────────┘
```

### Components

- **`reports/`** - Java/Maven project with JasperReports templates
  - `src/main/java/` - Report generator application
  - `src/main/resources/templates/` - `.jrxml` report definitions
- **`config/`** - Environment-specific configuration files
- **`scripts/`** - Shell scripts for report generation and maintenance
- **`cron/`** - Cron schedule for automated report generation
- **`docs/`** - Schema reference and report inventory

## Prerequisites

- Java 8 (JDK for building, JRE for running)
- Maven 3.6+
- PostgreSQL client libraries (for JDBC)
- Network access to the data warehouse (`acme-warehouse-prod.internal:5432`)

## Building

```bash
cd reports
mvn clean package
```

This produces `reports/target/clinical-reports-1.0.0.jar`.

## Running Reports

### Single Report

```bash
# Patient summary
java -jar reports/target/clinical-reports-1.0.0.jar patient_summary patient_id=42

# Billing statement
java -jar reports/target/clinical-reports-1.0.0.jar billing_statement encounter_id=101

# Department census (no parameters - shows current snapshot)
java -jar reports/target/clinical-reports-1.0.0.jar department_census

# Lab results for a date range
java -jar reports/target/clinical-reports-1.0.0.jar lab_results start_date=2025-01-01 end_date=2025-01-31

# Monthly revenue
java -jar reports/target/clinical-reports-1.0.0.jar monthly_revenue report_month=1 report_year=2025

# List all available reports
java -jar reports/target/clinical-reports-1.0.0.jar --list
```

### Nightly Batch

```bash
java -jar reports/target/clinical-reports-1.0.0.jar --batch
```

Or use the wrapper script:

```bash
./scripts/generate-reports.sh
```

## Configuration

Configuration is loaded with this precedence:
1. Environment variables (highest priority)
2. Properties file specified by `REPORT_CONFIG_PATH`
3. `/etc/acmehealth/reports.properties`
4. `config/production.properties` (fallback)

See `.env.example` for all available environment variables.

### Database Access

Reports connect to the clinical data warehouse using a read-only service account (`report_svc`). Contact the DBA team for credentials:
- Email: dba-team@acmehealth.com
- Slack: #dba-support

The report service account has SELECT access to:
- All tables in the `public` schema
- All views (`v_active_census`, `v_revenue_summary`, etc.)
- All functions (`calculate_age`, `length_of_stay`, `fmt_currency`)

## Deployment

Reports are deployed to `rpt-prod-01.acmehealth.internal` via Jenkins:
- Jenkins job: https://jenkins.acmehealth.internal/job/clinical-reports/
- Deploy target: `/opt/acmehealth/reports/`
- Config target: `/etc/acmehealth/reports.properties`

The deployment process:
1. Jenkins builds the JAR
2. Copies JAR and templates to the report server
3. Restarts the cron schedule
4. Runs a smoke test (generates department_census)

## Adding a New Report

1. Create the `.jrxml` template in `reports/src/main/resources/templates/`
2. Register the report in `ReportGenerator.java` (add to the `REPORTS` map)
3. Test against staging: `java -jar clinical-reports.jar <report_name> --config config/staging.properties`
4. Update `docs/report-inventory.md`
5. Add cron schedule entry if needed
6. Deploy via Jenkins

## Known Issues

See [docs/report-inventory.md](docs/report-inventory.md#known-issues) for the current list.

Key ones:
- Monthly revenue has ~0.5% variance vs GL (JIRA-4850)
- wRVU calculation uses simplified approximation (JIRA-6180)
- Medication frequency field has 47+ free-text variations (never normalized)

## Team

- **Sarah Kim** - Current maintainer (sarah.kim@acmehealth.com)
- **Marcus Chen** - Original author (no longer with company)

For questions: #clinical-reports on Slack
