-- ============================================================
-- Views and Functions used by the reporting system
-- Created by Marcus Chen, 2019
-- Modified by Sarah Kim, 2023
-- ============================================================

-- Calculate patient age (used by multiple reports)
CREATE OR REPLACE FUNCTION calculate_age(dob DATE)
RETURNS INTEGER AS $$
BEGIN
    RETURN EXTRACT(YEAR FROM AGE(CURRENT_DATE, dob))::INTEGER;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Calculate length of stay in days
-- NOTE: Marcus originally wrote this to return 1 for same-day visits
-- but Sarah changed it to return 0. Some reports may depend on the old behavior.
CREATE OR REPLACE FUNCTION length_of_stay(admit TIMESTAMP, discharge TIMESTAMP)
RETURNS INTEGER AS $$
BEGIN
    IF discharge IS NULL THEN
        RETURN EXTRACT(DAY FROM (CURRENT_TIMESTAMP - admit))::INTEGER;
    END IF;
    RETURN GREATEST(0, EXTRACT(DAY FROM (discharge - admit))::INTEGER);
END;
$$ LANGUAGE plpgsql STABLE;

-- Format currency for display (used in billing reports)
CREATE OR REPLACE FUNCTION fmt_currency(amount DECIMAL)
RETURNS VARCHAR AS $$
BEGIN
    IF amount IS NULL THEN
        RETURN '$0.00';
    END IF;
    RETURN '$' || TO_CHAR(amount, 'FM999,999,990.00');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================
-- Views
-- ============================================================

-- Active inpatient census view (used by department_census report)
CREATE OR REPLACE VIEW v_active_census AS
SELECT
    e.encounter_id,
    e.patient_id,
    p.mrn,
    p.first_name || ' ' || p.last_name AS patient_name,
    calculate_age(p.date_of_birth) AS age,
    p.gender,
    d.name AS department_name,
    d.code AS department_code,
    d.floor_number,
    e.room_number,
    e.bed_number,
    e.admission_date,
    length_of_stay(e.admission_date, e.discharge_date) AS los_days,
    e.acuity_level,
    e.chief_complaint,
    pr.last_name || ', ' || pr.first_name || ' ' || COALESCE(pr.credential, '') AS attending_provider,
    -- Get primary diagnosis
    (SELECT dx.icd10_code || ' - ' || dx.description
     FROM diagnoses dx
     WHERE dx.encounter_id = e.encounter_id
       AND dx.diagnosis_type = 'PRIMARY'
     LIMIT 1) AS primary_diagnosis,
    p.allergies,
    p.insurance_provider
FROM encounters e
JOIN patients p ON e.patient_id = p.patient_id
JOIN departments d ON e.department_id = d.department_id
LEFT JOIN providers pr ON e.provider_id = pr.provider_id
WHERE e.status = 'ACTIVE'
  AND e.encounter_type IN ('INPATIENT', 'OBSERVATION');

-- Patient encounter summary (used by patient_summary report)
CREATE OR REPLACE VIEW v_patient_encounters AS
SELECT
    e.encounter_id,
    e.patient_id,
    e.encounter_type,
    e.admission_date,
    e.discharge_date,
    e.status,
    e.chief_complaint,
    d.name AS department_name,
    pr.last_name || ', ' || pr.first_name AS provider_name,
    length_of_stay(e.admission_date, e.discharge_date) AS los_days,
    (SELECT STRING_AGG(dx.icd10_code || ' - ' || dx.description, '; ' ORDER BY
        CASE dx.diagnosis_type WHEN 'PRIMARY' THEN 1 WHEN 'ADMITTING' THEN 2 ELSE 3 END)
     FROM diagnoses dx WHERE dx.encounter_id = e.encounter_id) AS diagnoses_list,
    (SELECT COUNT(*) FROM procedures proc WHERE proc.encounter_id = e.encounter_id) AS procedure_count,
    (SELECT COALESCE(SUM(bi.total_price), 0) FROM billing_items bi WHERE bi.encounter_id = e.encounter_id) AS total_charges
FROM encounters e
JOIN departments d ON e.department_id = d.department_id
LEFT JOIN providers pr ON e.provider_id = pr.provider_id;

-- Revenue summary (used by monthly_revenue report)
CREATE OR REPLACE VIEW v_revenue_summary AS
SELECT
    d.department_id,
    d.name AS department_name,
    d.cost_center,
    DATE_TRUNC('month', bi.service_date) AS revenue_month,
    ic.plan_type AS payer_type,
    COUNT(DISTINCT e.encounter_id) AS encounter_count,
    COUNT(DISTINCT e.patient_id) AS unique_patients,
    SUM(bi.total_price) AS gross_charges,
    SUM(bi.insurance_adjustment + bi.contractual_adjustment) AS total_adjustments,
    SUM(bi.total_price - bi.insurance_adjustment - bi.contractual_adjustment) AS net_revenue,
    SUM(CASE WHEN bi.payment_status = 'PAID' THEN bi.total_price - bi.insurance_adjustment - bi.contractual_adjustment ELSE 0 END) AS collected_revenue,
    SUM(CASE WHEN bi.payment_status = 'DENIED' THEN bi.total_price ELSE 0 END) AS denied_amount
FROM billing_items bi
JOIN encounters e ON bi.encounter_id = e.encounter_id
JOIN departments d ON e.department_id = d.department_id
LEFT JOIN insurance_claims ic ON e.encounter_id = ic.encounter_id
GROUP BY d.department_id, d.name, d.cost_center, DATE_TRUNC('month', bi.service_date), ic.plan_type;

-- Provider productivity (used by provider_productivity report)
CREATE OR REPLACE VIEW v_provider_productivity AS
SELECT
    pr.provider_id,
    pr.first_name || ' ' || pr.last_name || ', ' || COALESCE(pr.credential, '') AS provider_name,
    pr.specialty,
    d.name AS department_name,
    DATE_TRUNC('month', e.admission_date) AS activity_month,
    COUNT(DISTINCT e.encounter_id) AS total_encounters,
    COUNT(DISTINCT CASE WHEN e.encounter_type = 'INPATIENT' THEN e.encounter_id END) AS inpatient_encounters,
    COUNT(DISTINCT CASE WHEN e.encounter_type = 'OUTPATIENT' THEN e.encounter_id END) AS outpatient_encounters,
    COUNT(DISTINCT CASE WHEN e.encounter_type = 'EMERGENCY' THEN e.encounter_id END) AS ed_encounters,
    COUNT(DISTINCT e.patient_id) AS unique_patients,
    (SELECT COUNT(*) FROM procedures proc
     WHERE proc.performing_provider_id = pr.provider_id
       AND DATE_TRUNC('month', proc.procedure_date) = DATE_TRUNC('month', e.admission_date)) AS procedures_performed,
    (SELECT COALESCE(SUM(proc.unit_cost * proc.quantity), 0) FROM procedures proc
     WHERE proc.performing_provider_id = pr.provider_id
       AND DATE_TRUNC('month', proc.procedure_date) = DATE_TRUNC('month', e.admission_date)) AS procedure_revenue,
    AVG(length_of_stay(e.admission_date, e.discharge_date)) AS avg_los,
    -- Readmission rate (30-day)
    COUNT(CASE WHEN e.readmission_flag THEN 1 END)::DECIMAL /
        NULLIF(COUNT(DISTINCT e.encounter_id), 0) * 100 AS readmission_rate
FROM providers pr
JOIN encounters e ON e.provider_id = pr.provider_id
JOIN departments d ON pr.department_id = d.department_id
WHERE pr.is_active = TRUE
GROUP BY pr.provider_id, pr.first_name, pr.last_name, pr.credential, pr.specialty,
         d.name, DATE_TRUNC('month', e.admission_date);

-- Lab results with interpretation (used by lab_results report)
CREATE OR REPLACE VIEW v_lab_results_interpreted AS
SELECT
    lr.result_id,
    lr.patient_id,
    p.mrn,
    p.first_name || ' ' || p.last_name AS patient_name,
    lr.encounter_id,
    lr.test_code,
    lr.test_name,
    lr.test_category,
    lr.result_value,
    lr.result_numeric,
    lr.unit,
    lr.reference_range_low,
    lr.reference_range_high,
    CASE
        WHEN lr.reference_range_low IS NOT NULL AND lr.reference_range_high IS NOT NULL THEN
            CAST(lr.reference_range_low AS VARCHAR) || ' - ' || CAST(lr.reference_range_high AS VARCHAR) || ' ' || COALESCE(lr.unit, '')
        WHEN lr.reference_range_high IS NOT NULL THEN
            '< ' || CAST(lr.reference_range_high AS VARCHAR) || ' ' || COALESCE(lr.unit, '')
        WHEN lr.reference_range_low IS NOT NULL THEN
            '> ' || CAST(lr.reference_range_low AS VARCHAR) || ' ' || COALESCE(lr.unit, '')
        ELSE 'N/A'
    END AS reference_range_display,
    lr.abnormal_flag,
    lr.critical_flag,
    CASE
        WHEN lr.critical_flag THEN 'CRITICAL'
        WHEN lr.abnormal_flag IN ('HH', 'LL') THEN 'PANIC'
        WHEN lr.abnormal_flag IN ('H', 'L') THEN 'ABNORMAL'
        ELSE 'NORMAL'
    END AS interpretation,
    lr.collected_date,
    lr.resulted_date,
    pr.last_name || ', ' || pr.first_name AS ordering_provider,
    lr.performing_lab,
    lr.status
FROM lab_results lr
JOIN patients p ON lr.patient_id = p.patient_id
LEFT JOIN providers pr ON lr.ordering_provider_id = pr.provider_id
WHERE lr.status != 'CANCELLED';
