# Changelog

All notable changes to the clinical reports system.

## [1.4.2] - 2024-02-20
### Fixed
- Lab results report now groups by test category (JIRA-6200)
- Provider productivity handles part-time providers correctly (JIRA-6050)

## [1.4.1] - 2024-01-15
### Fixed
- Medication administration record highlights high-alert drugs (JIRA-5950)
- Department census includes OBSERVATION encounter type (JIRA-6102)

### Changed
- Census report schedule adjusted per nursing request (every 4hrs)

## [1.4.0] - 2024-01-09
### Fixed
- Billing statement insurance adjustment rounding error (JIRA-5890)
- Monthly revenue contractual adjustment double-counting (JIRA-5920)

### Changed
- Refactored batch mode to support selective report generation
- Added timeout to on-demand report generation (JIRA-6100)

## [1.3.0] - 2023-12-01
### Added
- Critical value highlighting in lab results (JIRA-5601)

## [1.2.0] - 2023-08-15
### Added
- Allergies section to patient summary (JIRA-4521)

## [1.1.0] - 2023-06-15
### Added
- Payer mix breakdown in monthly revenue (JIRA-4200)

## [1.0.0] - 2019-04-01
### Added
- Initial release with 5 core reports
- Patient summary, billing statement, department census, lab results, monthly revenue
- Batch mode for nightly generation
- Cron scheduling

### Contributors
- Marcus Chen (original author, no longer with company)
- Sarah Kim (current maintainer)
