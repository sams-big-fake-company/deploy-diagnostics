package com.acmehealth.reports;

import java.io.FileInputStream;
import java.io.IOException;
import java.util.Properties;

/**
 * Configuration loader for the report generator.
 * 
 * Reads database connection parameters from a properties file or
 * environment variables. Environment variables take precedence over
 * the properties file.
 * 
 * Properties file locations (checked in order):
 *   1. Path specified by REPORT_CONFIG_PATH env var
 *   2. /etc/acmehealth/reports.properties (production)
 *   3. ./config/production.properties (development fallback)
 * 
 * @author Marcus Chen
 * @since 2019-04-01
 */
public class ReportConfig {

    private final Properties props;

    // Database connection
    private final String dbHost;
    private final int dbPort;
    private final String dbName;
    private final String dbUser;
    private final String dbPassword;
    private final String dbSchema;

    // Report output
    private final String outputDir;
    private final String templateDir;

    // SMTP for email delivery (used by nightly batch)
    private final String smtpHost;
    private final int smtpPort;
    private final String smtpFrom;

    public ReportConfig() throws IOException {
        this.props = loadProperties();

        // Database - env vars override properties file
        this.dbHost = getConfigValue("DB_HOST", "db.host", "acme-warehouse-prod.internal");
        this.dbPort = Integer.parseInt(getConfigValue("DB_PORT", "db.port", "5432"));
        this.dbName = getConfigValue("DB_NAME", "db.name", "clinical_warehouse");
        this.dbUser = getConfigValue("DB_USER", "db.user", "report_svc");
        this.dbPassword = getConfigValue("DB_PASSWORD", "db.password", "");
        this.dbSchema = getConfigValue("DB_SCHEMA", "db.schema", "public");

        // Report paths
        this.outputDir = getConfigValue("REPORT_OUTPUT_DIR", "report.output.dir",
                "/data/reports/output");
        this.templateDir = getConfigValue("REPORT_TEMPLATE_DIR", "report.template.dir",
                "/opt/acmehealth/reports/templates");

        // SMTP
        this.smtpHost = getConfigValue("SMTP_HOST", "smtp.host", "mail.acmehealth.internal");
        this.smtpPort = Integer.parseInt(getConfigValue("SMTP_PORT", "smtp.port", "25"));
        this.smtpFrom = getConfigValue("SMTP_FROM", "smtp.from", "reports@acmehealth.com");
    }

    /**
     * Load properties from the first available config file.
     */
    private Properties loadProperties() throws IOException {
        Properties p = new Properties();

        String[] configPaths = {
            System.getenv("REPORT_CONFIG_PATH"),
            "/etc/acmehealth/reports.properties",
            "config/production.properties",
            "config/staging.properties"
        };

        for (String path : configPaths) {
            if (path != null) {
                try (FileInputStream fis = new FileInputStream(path)) {
                    p.load(fis);
                    System.out.println("[CONFIG] Loaded configuration from: " + path);
                    return p;
                } catch (IOException e) {
                    // Try next path
                }
            }
        }

        System.out.println("[CONFIG] No properties file found, using environment variables and defaults");
        return p;
    }

    /**
     * Get a config value with precedence: env var > properties file > default.
     */
    private String getConfigValue(String envVar, String propKey, String defaultValue) {
        String envValue = System.getenv(envVar);
        if (envValue != null && !envValue.isEmpty()) {
            return envValue;
        }
        return props.getProperty(propKey, defaultValue);
    }

    public String getJdbcUrl() {
        return String.format("jdbc:postgresql://%s:%d/%s?currentSchema=%s",
                dbHost, dbPort, dbName, dbSchema);
    }

    public String getDbUser() { return dbUser; }
    public String getDbPassword() { return dbPassword; }
    public String getOutputDir() { return outputDir; }
    public String getTemplateDir() { return templateDir; }
    public String getSmtpHost() { return smtpHost; }
    public int getSmtpPort() { return smtpPort; }
    public String getSmtpFrom() { return smtpFrom; }

    @Override
    public String toString() {
        return String.format("ReportConfig{db=%s@%s:%d/%s, output=%s, templates=%s}",
                dbUser, dbHost, dbPort, dbName, outputDir, templateDir);
    }
}
