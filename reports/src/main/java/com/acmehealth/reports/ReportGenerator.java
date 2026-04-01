package com.acmehealth.reports;

import net.sf.jasperreports.engine.*;
import net.sf.jasperreports.engine.export.JRPdfExporter;
import net.sf.jasperreports.export.SimpleExporterInput;
import net.sf.jasperreports.export.SimpleOutputStreamExporterOutput;
import net.sf.jasperreports.export.SimplePdfExporterConfiguration;

import java.io.File;
import java.io.IOException;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.text.SimpleDateFormat;
import java.util.*;

/**
 * Main report generator for Acme Health clinical and financial reports.
 * 
 * Compiles JasperReports .jrxml templates and generates PDF output.
 * Can run individual reports or batch all reports for nightly generation.
 * 
 * Usage:
 *   java -jar clinical-reports.jar [report_name] [param=value ...]
 *   java -jar clinical-reports.jar --batch          # run all scheduled reports
 *   java -jar clinical-reports.jar --list            # list available reports
 * 
 * Examples:
 *   java -jar clinical-reports.jar patient_summary patient_id=42
 *   java -jar clinical-reports.jar monthly_revenue report_month=1 report_year=2025
 *   java -jar clinical-reports.jar department_census
 *   java -jar clinical-reports.jar --batch
 * 
 * @author Marcus Chen
 * @since 2019-04-01
 * @modified Sarah Kim 2024-01-09 - refactored to support batch mode
 */
public class ReportGenerator {

    private static final String VERSION = "1.4.2";

    // Report definitions: name -> required parameters
    // Marcus: I tried to make this data-driven with a YAML config but
    // JasperReports doesn't play nice with dynamic parameter loading.
    // So we hardcode the report list here. Add new reports manually.
    private static final Map<String, ReportDef> REPORTS = new LinkedHashMap<>();

    static {
        REPORTS.put("patient_summary", new ReportDef(
                "patient_summary.jrxml",
                "Patient Summary",
                new String[]{"patient_id"},
                new String[]{"as_of_date"}
        ));
        REPORTS.put("billing_statement", new ReportDef(
                "billing_statement.jrxml",
                "Billing Statement",
                new String[]{"encounter_id"},
                new String[]{}
        ));
        REPORTS.put("department_census", new ReportDef(
                "department_census.jrxml",
                "Department Census",
                new String[]{},
                new String[]{}
        ));
        REPORTS.put("lab_results", new ReportDef(
                "lab_results.jrxml",
                "Laboratory Results",
                new String[]{},
                new String[]{"patient_id", "start_date", "end_date"}
        ));
        REPORTS.put("monthly_revenue", new ReportDef(
                "monthly_revenue.jrxml",
                "Monthly Revenue Summary",
                new String[]{},
                new String[]{"report_month", "report_year"}
        ));
        REPORTS.put("provider_productivity", new ReportDef(
                "provider_productivity.jrxml",
                "Provider Productivity",
                new String[]{},
                new String[]{"report_month", "report_year", "department_id"}
        ));
        REPORTS.put("medication_administration", new ReportDef(
                "medication_administration.jrxml",
                "Medication Administration Record",
                new String[]{"patient_id"},
                new String[]{"include_discontinued"}
        ));
    }

    private final ReportConfig config;

    public ReportGenerator(ReportConfig config) {
        this.config = config;
    }

    public static void main(String[] args) {
        try {
            ReportConfig config = new ReportConfig();
            ReportGenerator generator = new ReportGenerator(config);

            if (args.length == 0 || "--help".equals(args[0])) {
                printUsage();
                System.exit(0);
            }

            if ("--list".equals(args[0])) {
                listReports();
                System.exit(0);
            }

            if ("--version".equals(args[0])) {
                System.out.println("Acme Health Clinical Reports v" + VERSION);
                System.exit(0);
            }

            if ("--batch".equals(args[0])) {
                generator.runBatch();
                System.exit(0);
            }

            // Single report mode
            String reportName = args[0];
            Map<String, Object> params = parseParams(args, 1);
            generator.generateReport(reportName, params);

        } catch (Exception e) {
            System.err.println("[ERROR] " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }

    /**
     * Generate a single report.
     */
    public String generateReport(String reportName, Map<String, Object> params) 
            throws JRException, SQLException, IOException {

        ReportDef def = REPORTS.get(reportName);
        if (def == null) {
            throw new IllegalArgumentException("Unknown report: " + reportName
                    + ". Use --list to see available reports.");
        }

        // Validate required parameters
        for (String required : def.requiredParams) {
            if (!params.containsKey(required)) {
                throw new IllegalArgumentException(
                        "Missing required parameter '" + required + "' for report " + reportName);
            }
        }

        String templatePath = config.getTemplateDir() + "/" + def.templateFile;
        System.out.println("[REPORT] Compiling template: " + templatePath);

        // Compile the template
        JasperReport jasperReport = JasperCompileManager.compileReport(templatePath);

        // Set the subreport directory for reports with subreports
        params.put("SUBREPORT_DIR", config.getTemplateDir() + "/");

        // Connect to database and fill report
        System.out.println("[REPORT] Connecting to database: " + config.getJdbcUrl());
        try (Connection conn = getConnection()) {
            System.out.println("[REPORT] Filling report: " + def.displayName);
            JasperPrint jasperPrint = JasperFillManager.fillReport(
                    jasperReport, new HashMap<>(params), conn);

            // Generate output filename
            String timestamp = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new Date());
            String outputFile = String.format("%s/%s_%s.pdf",
                    config.getOutputDir(), reportName, timestamp);

            // Ensure output directory exists
            new File(config.getOutputDir()).mkdirs();

            // Export to PDF
            System.out.println("[REPORT] Exporting to PDF: " + outputFile);
            exportToPdf(jasperPrint, outputFile);

            System.out.println("[REPORT] Successfully generated: " + outputFile);
            return outputFile;
        }
    }

    /**
     * Run all reports in batch mode (nightly generation).
     * 
     * The batch runs these reports:
     * 1. Department census (no parameters, current snapshot)
     * 2. Lab results for the past 24 hours
     * 3. Monthly revenue (current month, if past the 5th)
     * 4. Provider productivity (previous month, if we're in the first week)
     * 
     * Patient-specific reports (patient_summary, billing_statement,
     * medication_administration) are only generated on-demand since they
     * require a patient_id. The nightly batch used to generate summaries
     * for all active patients but Marcus removed that after it took 3 hours
     * to run for 200+ active patients and filled up the disk. - Sarah
     */
    public void runBatch() throws JRException, SQLException, IOException {
        System.out.println("[BATCH] Starting nightly report batch - v" + VERSION);
        System.out.println("[BATCH] Config: " + config);

        List<String> generated = new ArrayList<>();
        List<String> failed = new ArrayList<>();

        Calendar cal = Calendar.getInstance();
        int currentMonth = cal.get(Calendar.MONTH) + 1;
        int currentYear = cal.get(Calendar.YEAR);
        int dayOfMonth = cal.get(Calendar.DAY_OF_MONTH);

        // 1. Department Census - always runs
        try {
            String path = generateReport("department_census", new HashMap<>());
            generated.add(path);
        } catch (Exception e) {
            System.err.println("[BATCH] Failed: department_census - " + e.getMessage());
            failed.add("department_census");
        }

        // 2. Lab Results - past 24 hours
        try {
            Map<String, Object> labParams = new HashMap<>();
            labParams.put("start_date", new java.sql.Date(
                    System.currentTimeMillis() - 24 * 60 * 60 * 1000));
            labParams.put("end_date", new java.sql.Date(System.currentTimeMillis()));
            String path = generateReport("lab_results", labParams);
            generated.add(path);
        } catch (Exception e) {
            System.err.println("[BATCH] Failed: lab_results - " + e.getMessage());
            failed.add("lab_results");
        }

        // 3. Monthly Revenue - only after the 5th (to allow for late postings)
        if (dayOfMonth >= 5) {
            try {
                // Run for previous month
                int reportMonth = currentMonth == 1 ? 12 : currentMonth - 1;
                int reportYear = currentMonth == 1 ? currentYear - 1 : currentYear;
                Map<String, Object> revParams = new HashMap<>();
                revParams.put("report_month", reportMonth);
                revParams.put("report_year", reportYear);
                String path = generateReport("monthly_revenue", revParams);
                generated.add(path);
            } catch (Exception e) {
                System.err.println("[BATCH] Failed: monthly_revenue - " + e.getMessage());
                failed.add("monthly_revenue");
            }
        }

        // 4. Provider Productivity - first week of month only
        if (dayOfMonth <= 7) {
            try {
                int reportMonth = currentMonth == 1 ? 12 : currentMonth - 1;
                int reportYear = currentMonth == 1 ? currentYear - 1 : currentYear;
                Map<String, Object> prodParams = new HashMap<>();
                prodParams.put("report_month", reportMonth);
                prodParams.put("report_year", reportYear);
                String path = generateReport("provider_productivity", prodParams);
                generated.add(path);
            } catch (Exception e) {
                System.err.println("[BATCH] Failed: provider_productivity - " + e.getMessage());
                failed.add("provider_productivity");
            }
        }

        // Summary
        System.out.println("[BATCH] Complete. Generated: " + generated.size()
                + ", Failed: " + failed.size());
        if (!failed.isEmpty()) {
            System.err.println("[BATCH] Failed reports: " + String.join(", ", failed));
            // Exit with error code so cron job alerts on failure
            // The monitoring system (Nagios) checks for this
            System.exit(1);
        }
    }

    private Connection getConnection() throws SQLException {
        return DriverManager.getConnection(
                config.getJdbcUrl(), config.getDbUser(), config.getDbPassword());
    }

    private void exportToPdf(JasperPrint jasperPrint, String outputPath) throws JRException {
        JRPdfExporter exporter = new JRPdfExporter();
        exporter.setExporterInput(new SimpleExporterInput(jasperPrint));
        exporter.setExporterOutput(new SimpleOutputStreamExporterOutput(outputPath));

        SimplePdfExporterConfiguration pdfConfig = new SimplePdfExporterConfiguration();
        pdfConfig.setMetadataAuthor("Acme Health Systems");
        pdfConfig.setMetadataCreator("Clinical Reports v" + VERSION);
        // PDF/A compliance required by legal for medical records retention
        // Marcus added this after compliance audit in 2021
        pdfConfig.setPdfaConformance(null); // TODO: enable PDF/A-1b
        exporter.setConfiguration(pdfConfig);

        exporter.exportReport();
    }

    /**
     * Parse command-line parameters in key=value format.
     * Attempts type conversion for common parameter types.
     */
    private static Map<String, Object> parseParams(String[] args, int startIndex) {
        Map<String, Object> params = new HashMap<>();
        for (int i = startIndex; i < args.length; i++) {
            String[] parts = args[i].split("=", 2);
            if (parts.length != 2) {
                System.err.println("[WARN] Ignoring malformed parameter: " + args[i]);
                continue;
            }

            String key = parts[0];
            String value = parts[1];

            // Try to convert to appropriate types
            Object typedValue = convertParamValue(key, value);
            params.put(key, typedValue);
        }
        return params;
    }

    /**
     * Convert string parameter values to Java types expected by JasperReports.
     * This is fragile but necessary because JasperReports is strict about types.
     */
    private static Object convertParamValue(String key, String value) {
        // Integer parameters
        if (key.endsWith("_id") || key.equals("report_month") || key.equals("report_year")) {
            try {
                return Integer.parseInt(value);
            } catch (NumberFormatException e) {
                return value;
            }
        }

        // Date parameters
        if (key.endsWith("_date")) {
            try {
                return java.sql.Date.valueOf(value); // expects yyyy-MM-dd
            } catch (IllegalArgumentException e) {
                System.err.println("[WARN] Could not parse date '" + value
                        + "' for " + key + ". Expected format: yyyy-MM-dd");
                return value;
            }
        }

        // Boolean parameters
        if (key.startsWith("include_") || key.startsWith("is_")) {
            return Boolean.parseBoolean(value);
        }

        return value;
    }

    private static void printUsage() {
        System.out.println("Acme Health Clinical Reports v" + VERSION);
        System.out.println();
        System.out.println("Usage: java -jar clinical-reports.jar [report_name] [param=value ...]");
        System.out.println("       java -jar clinical-reports.jar --batch");
        System.out.println("       java -jar clinical-reports.jar --list");
        System.out.println();
        System.out.println("Examples:");
        System.out.println("  java -jar clinical-reports.jar patient_summary patient_id=42");
        System.out.println("  java -jar clinical-reports.jar monthly_revenue report_month=1 report_year=2025");
        System.out.println("  java -jar clinical-reports.jar department_census");
        System.out.println("  java -jar clinical-reports.jar lab_results start_date=2025-01-01 end_date=2025-01-31");
        System.out.println("  java -jar clinical-reports.jar --batch");
        System.out.println();
        System.out.println("Environment variables:");
        System.out.println("  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD");
        System.out.println("  REPORT_OUTPUT_DIR, REPORT_TEMPLATE_DIR");
        System.out.println("  REPORT_CONFIG_PATH (path to .properties file)");
    }

    private static void listReports() {
        System.out.println("Available reports:");
        System.out.println();
        for (Map.Entry<String, ReportDef> entry : REPORTS.entrySet()) {
            ReportDef def = entry.getValue();
            System.out.printf("  %-30s %s%n", entry.getKey(), def.displayName);
            if (def.requiredParams.length > 0) {
                System.out.printf("    Required: %s%n", String.join(", ", def.requiredParams));
            }
            if (def.optionalParams.length > 0) {
                System.out.printf("    Optional: %s%n", String.join(", ", def.optionalParams));
            }
            System.out.println();
        }
    }

    /**
     * Report definition container.
     */
    static class ReportDef {
        final String templateFile;
        final String displayName;
        final String[] requiredParams;
        final String[] optionalParams;

        ReportDef(String templateFile, String displayName,
                  String[] requiredParams, String[] optionalParams) {
            this.templateFile = templateFile;
            this.displayName = displayName;
            this.requiredParams = requiredParams;
            this.optionalParams = optionalParams;
        }
    }
}
