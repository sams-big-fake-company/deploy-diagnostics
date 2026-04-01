-- ============================================================
-- Acme Health Systems - Clinical Data Warehouse Schema
-- Originally created: 2019-03-14 by Marcus Chen (no longer with company)
-- Last modified: 2023-11-02 by Sarah Kim
--
-- WARNING: This file is a reference copy only. The production
-- schema may have drifted from this file. Always check the
-- live database for the current schema. Last verified against
-- prod by Sarah on 2023-11-02.
--
-- Production DB: acme-warehouse-prod.internal (port 5432)
-- Database: clinical_warehouse
-- ============================================================

-- Departments
CREATE TABLE departments (
    department_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(10) UNIQUE NOT NULL,
    floor_number INTEGER,
    bed_count INTEGER,
    cost_center VARCHAR(20),
    department_head VARCHAR(200),
    is_active BOOLEAN DEFAULT TRUE
);

-- Providers (physicians, nurses, etc.)
CREATE TABLE providers (
    provider_id SERIAL PRIMARY KEY,
    npi VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    credential VARCHAR(20),            -- MD, DO, NP, PA
    specialty VARCHAR(100),
    department_id INTEGER REFERENCES departments(department_id),
    license_number VARCHAR(50),
    hire_date DATE,
    hourly_rate DECIMAL(8,2),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Patients
CREATE TABLE patients (
    patient_id SERIAL PRIMARY KEY,
    mrn VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender CHAR(1) CHECK (gender IN ('M', 'F', 'O', 'U')),
    ssn_last_four CHAR(4),
    address_line1 VARCHAR(200),
    address_line2 VARCHAR(200),
    city VARCHAR(100),
    state CHAR(2),
    zip_code VARCHAR(10),
    phone VARCHAR(20),
    email VARCHAR(200),
    emergency_contact_name VARCHAR(200),
    emergency_contact_phone VARCHAR(20),
    -- Insurance info (denormalized - this was a quick fix by Marcus in 2019)
    insurance_provider VARCHAR(200),
    insurance_plan VARCHAR(200),
    insurance_member_id VARCHAR(50),
    insurance_group_number VARCHAR(50),
    primary_care_provider_id INTEGER REFERENCES providers(provider_id),
    blood_type VARCHAR(5),
    allergies TEXT,                      -- comma-separated, should have been a separate table
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Encounters (visits, admissions, ED visits)
CREATE TABLE encounters (
    encounter_id SERIAL PRIMARY KEY,
    patient_id INTEGER NOT NULL REFERENCES patients(patient_id),
    provider_id INTEGER REFERENCES providers(provider_id),
    department_id INTEGER REFERENCES departments(department_id),
    encounter_type VARCHAR(20) NOT NULL CHECK (encounter_type IN ('INPATIENT', 'OUTPATIENT', 'EMERGENCY', 'OBSERVATION')),
    admission_date TIMESTAMP NOT NULL,
    discharge_date TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DISCHARGED', 'TRANSFERRED', 'DECEASED')),
    room_number VARCHAR(10),
    bed_number VARCHAR(5),
    chief_complaint TEXT,
    discharge_summary TEXT,
    discharge_disposition VARCHAR(50),
    readmission_flag BOOLEAN DEFAULT FALSE,
    -- This field was added by Marcus and is used by the billing report
    -- It's calculated differently depending on encounter_type
    acuity_level INTEGER CHECK (acuity_level BETWEEN 1 AND 5),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Diagnoses (ICD-10 codes)
CREATE TABLE diagnoses (
    diagnosis_id SERIAL PRIMARY KEY,
    encounter_id INTEGER NOT NULL REFERENCES encounters(encounter_id),
    icd10_code VARCHAR(10) NOT NULL,
    description VARCHAR(500) NOT NULL,
    diagnosis_type VARCHAR(20) NOT NULL CHECK (diagnosis_type IN ('PRIMARY', 'SECONDARY', 'ADMITTING', 'DISCHARGE')),
    diagnosed_date DATE NOT NULL,
    diagnosed_by INTEGER REFERENCES providers(provider_id),
    is_chronic BOOLEAN DEFAULT FALSE,
    present_on_admission BOOLEAN
);

-- Procedures (CPT codes)
CREATE TABLE procedures (
    procedure_id SERIAL PRIMARY KEY,
    encounter_id INTEGER NOT NULL REFERENCES encounters(encounter_id),
    cpt_code VARCHAR(10) NOT NULL,
    description VARCHAR(500) NOT NULL,
    procedure_date TIMESTAMP NOT NULL,
    performing_provider_id INTEGER REFERENCES providers(provider_id),
    assisting_provider_id INTEGER REFERENCES providers(provider_id),
    quantity INTEGER DEFAULT 1,
    unit_cost DECIMAL(10,2) NOT NULL,
    modifier VARCHAR(10),
    -- anesthesia_minutes only populated for surgical procedures
    anesthesia_minutes INTEGER,
    notes TEXT
);

-- Lab Results
CREATE TABLE lab_results (
    result_id SERIAL PRIMARY KEY,
    encounter_id INTEGER REFERENCES encounters(encounter_id),
    patient_id INTEGER NOT NULL REFERENCES patients(patient_id),
    test_code VARCHAR(20) NOT NULL,
    test_name VARCHAR(200) NOT NULL,
    test_category VARCHAR(50),          -- CHEMISTRY, HEMATOLOGY, MICROBIOLOGY, etc.
    result_value VARCHAR(100),
    result_numeric DECIMAL(12,4),
    unit VARCHAR(50),
    reference_range_low DECIMAL(12,4),
    reference_range_high DECIMAL(12,4),
    abnormal_flag VARCHAR(5) CHECK (abnormal_flag IN ('N', 'L', 'H', 'LL', 'HH', 'A')),
    -- critical_flag was added later and is only used by the lab results report
    critical_flag BOOLEAN DEFAULT FALSE,
    collected_date TIMESTAMP NOT NULL,
    resulted_date TIMESTAMP,
    ordering_provider_id INTEGER REFERENCES providers(provider_id),
    performing_lab VARCHAR(100) DEFAULT 'ACME CLINICAL LAB',
    status VARCHAR(20) DEFAULT 'FINAL' CHECK (status IN ('PRELIMINARY', 'FINAL', 'CORRECTED', 'CANCELLED'))
);

-- Medications
CREATE TABLE medications (
    medication_id SERIAL PRIMARY KEY,
    patient_id INTEGER NOT NULL REFERENCES patients(patient_id),
    encounter_id INTEGER REFERENCES encounters(encounter_id),
    drug_name VARCHAR(200) NOT NULL,
    generic_name VARCHAR(200),
    ndc_code VARCHAR(20),
    drug_class VARCHAR(100),
    dosage VARCHAR(100) NOT NULL,
    frequency VARCHAR(100) NOT NULL,
    route VARCHAR(50) CHECK (route IN ('ORAL', 'IV', 'IM', 'SUBCUTANEOUS', 'TOPICAL', 'INHALATION', 'RECTAL', 'OPHTHALMIC')),
    start_date DATE NOT NULL,
    end_date DATE,
    prescribing_provider_id INTEGER REFERENCES providers(provider_id),
    is_active BOOLEAN DEFAULT TRUE,
    is_prn BOOLEAN DEFAULT FALSE,       -- "as needed"
    pharmacy_notes TEXT,
    -- high_alert added by Sarah for medication safety reports
    high_alert BOOLEAN DEFAULT FALSE
);

-- Billing Items
CREATE TABLE billing_items (
    billing_id SERIAL PRIMARY KEY,
    encounter_id INTEGER NOT NULL REFERENCES encounters(encounter_id),
    patient_id INTEGER NOT NULL REFERENCES patients(patient_id),
    charge_code VARCHAR(20) NOT NULL,
    description VARCHAR(500) NOT NULL,
    revenue_code VARCHAR(10),
    service_date DATE NOT NULL,
    quantity INTEGER DEFAULT 1,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(10,2) NOT NULL,
    insurance_adjustment DECIMAL(10,2) DEFAULT 0,
    contractual_adjustment DECIMAL(10,2) DEFAULT 0,
    patient_responsibility DECIMAL(10,2),
    payment_status VARCHAR(20) DEFAULT 'PENDING'
        CHECK (payment_status IN ('PENDING', 'SUBMITTED', 'PAID', 'PARTIAL', 'DENIED', 'APPEALED', 'WRITTEN_OFF')),
    claim_number VARCHAR(50),
    posted_date DATE
);

-- Insurance Claims
CREATE TABLE insurance_claims (
    claim_id SERIAL PRIMARY KEY,
    encounter_id INTEGER NOT NULL REFERENCES encounters(encounter_id),
    patient_id INTEGER NOT NULL REFERENCES patients(patient_id),
    claim_number VARCHAR(50) UNIQUE NOT NULL,
    payer_name VARCHAR(200) NOT NULL,
    payer_id VARCHAR(50),
    plan_type VARCHAR(50),              -- HMO, PPO, MEDICARE, MEDICAID, SELF_PAY
    submitted_date DATE,
    received_date DATE,
    adjudicated_date DATE,
    total_charges DECIMAL(10,2) NOT NULL,
    allowed_amount DECIMAL(10,2),
    paid_amount DECIMAL(10,2),
    coinsurance DECIMAL(10,2),
    copay DECIMAL(10,2),
    deductible DECIMAL(10,2),
    patient_responsibility DECIMAL(10,2),
    status VARCHAR(20) NOT NULL
        CHECK (status IN ('DRAFT', 'SUBMITTED', 'IN_REVIEW', 'ADJUDICATED', 'PAID', 'DENIED', 'APPEALED', 'VOIDED')),
    denial_reason_code VARCHAR(20),
    denial_reason VARCHAR(500),
    -- remittance_advice is the raw ERA/835 text, stored as-is
    remittance_advice TEXT
);

-- ============================================================
-- Indexes (added over time by various team members)
-- ============================================================
CREATE INDEX idx_encounters_patient ON encounters(patient_id);
CREATE INDEX idx_encounters_admission ON encounters(admission_date);
CREATE INDEX idx_encounters_status ON encounters(status);
CREATE INDEX idx_diagnoses_encounter ON diagnoses(encounter_id);
CREATE INDEX idx_diagnoses_icd10 ON diagnoses(icd10_code);
CREATE INDEX idx_procedures_encounter ON procedures(encounter_id);
CREATE INDEX idx_lab_results_patient ON lab_results(patient_id);
CREATE INDEX idx_lab_results_encounter ON lab_results(encounter_id);
CREATE INDEX idx_lab_results_collected ON lab_results(collected_date);
CREATE INDEX idx_medications_patient ON medications(patient_id);
CREATE INDEX idx_billing_encounter ON billing_items(encounter_id);
CREATE INDEX idx_billing_patient ON billing_items(patient_id);
CREATE INDEX idx_billing_status ON billing_items(payment_status);
CREATE INDEX idx_claims_encounter ON insurance_claims(encounter_id);
CREATE INDEX idx_claims_status ON insurance_claims(status);
