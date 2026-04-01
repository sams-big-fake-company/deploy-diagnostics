# Clinical Reports Inventory

Last updated: 2024-02-20 by Sarah Kim

## Active Reports

| Report | Template | Schedule | Owner | Notes |
|--------|----------|----------|-------|-------|
| Patient Summary | `patient_summary.jrxml` | On-demand | Nursing | Has 3 subreports (encounters, meds, labs) |
| Billing Statement | `billing_statement.jrxml` | On-demand | Finance | Groups by revenue code category |
| Department Census | `department_census.jrxml` | Every 4hrs + nightly | Nursing | Landscape orientation, color-coded acuity |
| Lab Results | `lab_results.jrxml` | Every 2hrs + nightly | Lab | Can run per-patient or all-patients |
| Monthly Revenue | `monthly_revenue.jrxml` | 5th of month | CFO Office | Known ~0.5% discrepancy vs GL (JIRA-4850) |
| Provider Productivity | `provider_productivity.jrxml` | 3rd of month | Medical Staff | wRVU estimates only - see JIRA-6180 |
| Medication Administration | `medication_administration.jrxml` | On-demand | Pharmacy | High-alert drug highlighting per Joint Commission |

## Decommissioned Reports

| Report | Decommissioned | Reason |
|--------|---------------|--------|
| Daily Admission Log | 2022-06 | Replaced by Epic dashboard |
| Infection Control | 2023-01 | Moved to Tableau |
| Bed Utilization | 2023-09 | Merged into department census |

## Report Dependencies

```
patient_summary
├── patient_summary_encounters (subreport)
├── patient_summary_medications (subreport)
└── patient_summary_labs (subreport)

All reports depend on:
├── PostgreSQL views (docs/views-and-functions-reference.sql)
├── calculate_age() function
├── length_of_stay() function
└── fmt_currency() function
```

## Database Views Used

| View | Used By |
|------|---------|
| `v_active_census` | department_census |
| `v_patient_encounters` | (currently unused - was for the old admission log) |
| `v_revenue_summary` | monthly_revenue |
| `v_provider_productivity` | provider_productivity |
| `v_lab_results_interpreted` | (currently unused - Sarah was going to use it for a new lab dashboard) |

## Known Issues

- **JIRA-4850**: Monthly revenue doesn't match GL exactly (~0.5% variance from late adjustments)
- **JIRA-5920**: Fixed contractual adjustment double-counting in January 2024
- **JIRA-6050**: Part-time provider productivity numbers are estimated (no actual hours tracking)
- **JIRA-6180**: Year-over-year comparison requested by Dr. Martinez, not yet implemented
- **JIRA-6200**: Lab results test category grouping added Feb 2024
- Medication frequency field is free-text with 47+ variations (never normalized)
- wRVU calculation uses simplified CMS rate approximation, not actual RVU table

## Contacts

- **Report issues**: Sarah Kim (sarah.kim@acmehealth.com) or #clinical-reports on Slack
- **Database access**: DBA team (dba-team@acmehealth.com) or #dba-support on Slack
- **Report server access**: IT Operations (ops@acmehealth.com)
- **Business requirements**: Contact the report owner listed above
