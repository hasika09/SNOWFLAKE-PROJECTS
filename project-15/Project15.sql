-- ================================================================================
-- PROJECT 15: Cross-Border Logistics & Fleet Telematics Lakehouse Platform
-- ================================================================================

-- ================================================================================
-- TASK 1: BRONZE DATA LAKE INGESTION & SCHEMA-ON-READ
-- ================================================================================

CREATE OR REPLACE DATABASE LOGISTICS_LAKEHOUSE_DB;

USE DATABASE LOGISTICS_LAKEHOUSE_DB;

CREATE OR REPLACE SCHEMA FLEET_CORE;

USE SCHEMA FLEET_CORE;


-- Bronze Layer
CREATE OR REPLACE TABLE BRONZE_IOT_STREAMS (
    INGEST_ID INTEGER AUTOINCREMENT,
    RAW_PAYLOAD VARIANT,
    RECORDED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);


-- Temporary raw landing table
CREATE OR REPLACE TABLE RAW_IOT_QUEUE (
    RAW_RECORD_TEXT VARCHAR
);


-- Insert Batch 1
INSERT INTO RAW_IOT_QUEUE (RAW_RECORD_TEXT)
VALUES
('{"payload_id":"PL-801","payload_type":"TELEMATICS","timestamp":"2026-08-01T06:00:00Z","data":{"trip_id":"TRP-101","vehicle_id":"TRK-9001","driver_name":"John Doe","distance_km":450.0,"fuel_consumed_liters":120.0,"speed_avg":75.0}}'),
('{"payload_id":"PL-802","payload_type":"CUSTOMS","timestamp":"2026-08-01T06:30:00Z","data":{"shipment_id":"SHP-5001","vehicle_id":"TRK-9001","destination_country":"CAN","declared_value":85000.00,"duty_pct":5.0,"clearance_status":"CLEARED"}}'),
('{"payload_id":"PL-803","payload_type":"TELEMATICS","timestamp":"2026-08-01T07:00:00Z","data":{"trip_id":"TRP-102","vehicle_id":"TRK-9002","driver_name":"Jane Smith","distance_km":620.0,"fuel_consumed_liters":180.0,"speed_avg":82.0}}'),
('{"payload_id":"PL-804","payload_type":"CUSTOMS","timestamp":"2026-08-01T07:45:00Z","data":{"shipment_id":"SHP-5002","vehicle_id":"TRK-9002","destination_country":"MEX","declared_value":42000.00,"duty_pct":7.5,"clearance_status":"CLEARED"}}');


-- Insert Batch 2
INSERT INTO RAW_IOT_QUEUE (RAW_RECORD_TEXT)
VALUES
('{"payload_id":"PL-805","payload_type":"TELEMATICS","timestamp":"2026-08-01T08:15:00Z","data":{"trip_id":"TRP-103","vehicle_id":"TRK-9003","driver_name":"Robert Brown","distance_km":310.0,"fuel_consumed_liters":95.0,"speed_avg":68.0,"driver_fatigue_score":1.2}}'),
('{"payload_id":"PL-806","payload_type":"CUSTOMS","timestamp":"2026-08-01T08:30:00Z","data":{"shipment_id":"SHP-5003","vehicle_id":"TRK-9003","destination_country":"CAN","declared_value":120000.00,"duty_pct":4.0,"clearance_status":"CLEARED","border_clearance_code":"FAST_PASS_01"}}'),
('{"payload_id":"PL-807","payload_type":"CUSTOMS","timestamp":"2026-08-01T09:00:00Z","data":{"shipment_id":"SHP-5004","vehicle_id":"TRK-9001","destination_country":"MEX","declared_value":15000.00,"duty_pct":7.5,"clearance_status":"HELD_INSPECTION","border_clearance_code":null}}');


-- Insert Batch 3 valid JSON record
INSERT INTO RAW_IOT_QUEUE (RAW_RECORD_TEXT)
VALUES
('{"payload_id":"PL-808","payload_type":"TELEMATICS","timestamp":"2026-08-01T09:30:00Z","data":{"trip_id":"TRP-104","vehicle_id":"TRK-9004","driver_name":"Alice Green","distance_km":0.0,"fuel_consumed_liters":0.0,"speed_avg":0.0,"driver_fatigue_score":0.0}}');


-- Insert malformed record
INSERT INTO RAW_IOT_QUEUE (RAW_RECORD_TEXT)
VALUES
('MALFORMED_IOT_SENSOR_BINARY_BURST_DATA_ERR');


-- ================================================================================
-- TASK 2: DEAD-LETTER QUEUE / QUARANTINE
-- ================================================================================

CREATE OR REPLACE TABLE QUARANTINE_IOT_PAYLOADS (
    QUARANTINE_ID INTEGER AUTOINCREMENT,
    RAW_RECORD_TEXT VARCHAR,
    REASON VARCHAR
);


-- Valid JSON records -> Bronze
INSERT INTO BRONZE_IOT_STREAMS (
    RAW_PAYLOAD
)
SELECT
    TRY_PARSE_JSON(RAW_RECORD_TEXT)
FROM RAW_IOT_QUEUE
WHERE TRY_PARSE_JSON(RAW_RECORD_TEXT) IS NOT NULL;


-- Malformed records -> Quarantine
INSERT INTO QUARANTINE_IOT_PAYLOADS (
    RAW_RECORD_TEXT,
    REASON
)
SELECT
    RAW_RECORD_TEXT,
    'MALFORMED_JSON_BODY'
FROM RAW_IOT_QUEUE
WHERE TRY_PARSE_JSON(RAW_RECORD_TEXT) IS NULL;


-- Check Bronze count
SELECT COUNT(*) AS TOTAL_BRONZE_RECORDS
FROM BRONZE_IOT_STREAMS;


-- Check quarantine
SELECT
    QUARANTINE_ID,
    RAW_RECORD_TEXT,
    REASON
FROM QUARANTINE_IOT_PAYLOADS
ORDER BY QUARANTINE_ID;


-- ================================================================================
-- TASK 1: SCHEMA-ON-READ EXPLORATION
-- ================================================================================

SELECT
    RAW_PAYLOAD:payload_id::VARCHAR AS PAYLOAD_ID,
    RAW_PAYLOAD:payload_type::VARCHAR AS PAYLOAD_TYPE,
    RAW_PAYLOAD:timestamp::TIMESTAMP_TZ AS EVENT_TIMESTAMP,
    RAW_PAYLOAD:data:vehicle_id::VARCHAR AS VEHICLE_ID,
    RAW_PAYLOAD:data:shipment_id::VARCHAR AS SHIPMENT_ID,
    RAW_PAYLOAD:data:declared_value::NUMBER(18,2) AS DECLARED_VALUE
FROM BRONZE_IOT_STREAMS
ORDER BY EVENT_TIMESTAMP;


-- ================================================================================
-- TASK 3: SILVER LAYER
-- SCHEMA-ON-WRITE MODELING & COMPUTATIONS
-- ================================================================================

CREATE OR REPLACE TABLE SILVER_CUSTOMS_CLEARANCE (
    SHIPMENT_ID VARCHAR(50),
    PAYLOAD_ID VARCHAR(50),
    VEHICLE_ID VARCHAR(50),
    DESTINATION_COUNTRY VARCHAR(10),
    DECLARED_VALUE NUMBER(18,2),
    DUTY_PCT NUMBER(10,2),
    DUTY_AMOUNT_DUE NUMBER(18,2),
    BORDER_CODE VARCHAR(100),
    CLEARANCE_STATUS VARCHAR(50)
);


-- ETL from Bronze -> Silver
INSERT INTO SILVER_CUSTOMS_CLEARANCE (
    SHIPMENT_ID,
    PAYLOAD_ID,
    VEHICLE_ID,
    DESTINATION_COUNTRY,
    DECLARED_VALUE,
    DUTY_PCT,
    DUTY_AMOUNT_DUE,
    BORDER_CODE,
    CLEARANCE_STATUS
)
SELECT
    RAW_PAYLOAD:data:shipment_id::VARCHAR AS SHIPMENT_ID,
    RAW_PAYLOAD:payload_id::VARCHAR AS PAYLOAD_ID,
    RAW_PAYLOAD:data:vehicle_id::VARCHAR AS VEHICLE_ID,
    RAW_PAYLOAD:data:destination_country::VARCHAR AS DESTINATION_COUNTRY,
    RAW_PAYLOAD:data:declared_value::NUMBER(18,2) AS DECLARED_VALUE,
    RAW_PAYLOAD:data:duty_pct::NUMBER(10,2) AS DUTY_PCT,

    ROUND(
        RAW_PAYLOAD:data:declared_value::NUMBER(18,2)
        *
        (RAW_PAYLOAD:data:duty_pct::NUMBER(10,2) / 100),
        2
    ) AS DUTY_AMOUNT_DUE,

    RAW_PAYLOAD:data:border_clearance_code::VARCHAR AS BORDER_CODE,

    RAW_PAYLOAD:data:clearance_status::VARCHAR AS CLEARANCE_STATUS

FROM BRONZE_IOT_STREAMS
WHERE RAW_PAYLOAD:payload_type::VARCHAR = 'CUSTOMS';


-- Verify Silver data
SELECT *
FROM SILVER_CUSTOMS_CLEARANCE
ORDER BY SHIPMENT_ID;


-- ================================================================================
-- TASK 4: GOLD LAYER
-- STRATEGIC COUNTRY DUTY SUMMARY
-- ================================================================================

CREATE OR REPLACE TABLE GOLD_COUNTRY_DUTY_SUMMARY (
    DEST_COUNTRY VARCHAR(10),
    TOTAL_CLEARED_VAL NUMBER(18,2),
    TOTAL_DUTIES_COLLECTED NUMBER(18,2),
    AVG_DUTY_RATE_PCT NUMBER(10,2),
    CLEARED_SHIPMENTS INTEGER
);


INSERT INTO GOLD_COUNTRY_DUTY_SUMMARY (
    DEST_COUNTRY,
    TOTAL_CLEARED_VAL,
    TOTAL_DUTIES_COLLECTED,
    AVG_DUTY_RATE_PCT,
    CLEARED_SHIPMENTS
)
SELECT
    DESTINATION_COUNTRY AS DEST_COUNTRY,
    SUM(DECLARED_VALUE) AS TOTAL_CLEARED_VAL,
    SUM(DUTY_AMOUNT_DUE) AS TOTAL_DUTIES_COLLECTED,
    ROUND(
        SUM(DUTY_AMOUNT_DUE) / NULLIF(SUM(DECLARED_VALUE), 0) * 100,
        2
    ) AS AVG_DUTY_RATE_PCT,
    COUNT(*) AS CLEARED_SHIPMENTS
FROM SILVER_CUSTOMS_CLEARANCE
WHERE CLEARANCE_STATUS = 'CLEARED'
GROUP BY DESTINATION_COUNTRY
ORDER BY DESTINATION_COUNTRY;


-- Verify Gold data
SELECT *
FROM GOLD_COUNTRY_DUTY_SUMMARY
ORDER BY DEST_COUNTRY;


-- ================================================================================
-- TASK 5: DISASTER RECOVERY USING SNOWFLAKE TIME TRAVEL
-- ================================================================================

-- IMPORTANT:
-- First capture the current Silver table state.
-- This timestamp is useful for the recovery step.

SELECT CURRENT_TIMESTAMP() AS BEFORE_CORRUPTION_TIME;


-- Simulate unauthorized corruption
UPDATE SILVER_CUSTOMS_CLEARANCE
SET CLEARANCE_STATUS = 'REJECTED'
WHERE DESTINATION_COUNTRY = 'CAN';


-- Verify corruption
SELECT
    DESTINATION_COUNTRY,
    CLEARANCE_STATUS,
    COUNT(*) AS RECORD_COUNT
FROM SILVER_CUSTOMS_CLEARANCE
GROUP BY
    DESTINATION_COUNTRY,
    CLEARANCE_STATUS
ORDER BY
    DESTINATION_COUNTRY,
    CLEARANCE_STATUS;


-- ================================================================================
-- TIME-TRAVEL AUDIT
-- ================================================================================

-- Replace the timestamp below with the timestamp captured
-- BEFORE_CORRUPTION_TIME from the previous query.

-- Example:
-- SELECT *
-- FROM SILVER_CUSTOMS_CLEARANCE
-- AT (TIMESTAMP => '2026-09-12 09:45:00');


-- Alternative using OFFSET:
-- The UPDATE creates a new table version.
-- OFFSET => -60 means approximately 60 seconds before the query execution time.

SELECT *
FROM SILVER_CUSTOMS_CLEARANCE
AT (OFFSET => -10)
ORDER BY SHIPMENT_ID;


-- ================================================================================
-- RECOVERY
-- ================================================================================
-- Rebuild the current Silver table from the Time-Travel version.
-- This restores the table to the state before the unauthorized UPDATE.

CREATE OR REPLACE TEMPORARY TABLE SILVER_RECOVERY AS
SELECT *
FROM SILVER_CUSTOMS_CLEARANCE
AT (OFFSET => -10);


CREATE OR REPLACE TABLE SILVER_CUSTOMS_CLEARANCE AS
SELECT *
FROM SILVER_RECOVERY;


-- Verify recovery
SELECT
    DESTINATION_COUNTRY,
    COUNT_IF(CLEARANCE_STATUS = 'CLEARED') AS CLEARED_COUNT,
    COUNT_IF(CLEARANCE_STATUS = 'REJECTED') AS REJECTED_COUNT
FROM SILVER_CUSTOMS_CLEARANCE
GROUP BY DESTINATION_COUNTRY
ORDER BY DESTINATION_COUNTRY;


-- ================================================================================
-- TASK 6: END-TO-END PIPELINE LINEAGE & RECONCILIATION AUDIT
-- ================================================================================

WITH BRONZE_TOTAL AS (
    SELECT
        SUM(
            CASE
                WHEN RAW_PAYLOAD:payload_type::VARCHAR = 'CUSTOMS'
                THEN RAW_PAYLOAD:data:declared_value::NUMBER(18,2)
                ELSE 0
            END
        ) AS BRONZE_GROSS_TOTAL
    FROM BRONZE_IOT_STREAMS
),

SILVER_TOTAL AS (
    SELECT
        SUM(DECLARED_VALUE) AS SILVER_GROSS_TOTAL
    FROM SILVER_CUSTOMS_CLEARANCE
),

GOLD_TOTAL AS (
    SELECT
        SUM(TOTAL_CLEARED_VAL) AS GOLD_GROSS_TOTAL
    FROM GOLD_COUNTRY_DUTY_SUMMARY
)

SELECT
    B.BRONZE_GROSS_TOTAL,
    S.SILVER_GROSS_TOTAL,
    G.GOLD_GROSS_TOTAL,

    CASE
        WHEN B.BRONZE_GROSS_TOTAL = S.SILVER_GROSS_TOTAL
        AND G.GOLD_GROSS_TOTAL <= S.SILVER_GROSS_TOTAL
        THEN TRUE
        ELSE FALSE
    END AS RECONCILED_FLAG

FROM BRONZE_TOTAL B
CROSS JOIN SILVER_TOTAL S
CROSS JOIN GOLD_TOTAL G;


-- ================================================================================
-- FINAL EXPECTED RESULTS
-- ================================================================================

-- Bronze:
-- TOTAL_BRONZE_RECORDS = 8

-- Quarantine:
-- 1 | MALFORMED_IOT_SENSOR_BINARY_BURST_DATA_ERR | MALFORMED_JSON_BODY

-- Silver:
-- SHP-5001 | TRK-9001 | CAN | 85000.00  | 5.0 | 4250.00 | NULL         | CLEARED
-- SHP-5002 | TRK-9002 | MEX | 42000.00  | 7.5 | 3150.00 | NULL         | CLEARED
-- SHP-5003 | TRK-9003 | CAN | 120000.00 | 4.0 | 4800.00 | FAST_PASS_01 | CLEARED
-- SHP-5004 | TRK-9001 | MEX | 15000.00  | 7.5 | 1125.00 | NULL         | HELD_INSPECTION

-- Gold:
-- CAN | 205000.00 | 9050.00 | 4.41 | 2
-- MEX | 42000.00  | 3150.00 | 7.50 | 1

-- Final reconciliation:
-- BRONZE_GROSS_TOTAL = 262000.00
-- SILVER_GROSS_TOTAL = 262000.00
-- GOLD_GROSS_TOTAL   = 247000.00
-- RECONCILED_FLAG    = TRUE