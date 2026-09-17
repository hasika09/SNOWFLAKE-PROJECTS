
CREATE OR REPLACE DATABASE ECOMMERCE_DB;

USE DATABASE ECOMMERCE_DB;

CREATE OR REPLACE SCHEMA WEB_ANALYTICS;

USE SCHEMA WEB_ANALYTICS;


CREATE OR REPLACE TABLE RAW_EVENT_SOURCE (
    RAW_RECORD_TEXT VARCHAR
);


INSERT INTO RAW_EVENT_SOURCE (RAW_RECORD_TEXT)
VALUES
('{"event_id":"EVT-8001","timestamp":"2026-07-01T08:15:00Z","user_id":1001,"page":"checkout","action":"purchase","order":{"total":12500.00,"shipping_cost":250.00,"tax":625.00,"items":2}}'),

('{"event_id":"EVT-8002","timestamp":"2026-07-01T08:20:00Z","user_id":1002,"page":"product_detail","action":"view","order":null}'),

('{"event_id":"EVT-8003","timestamp":"2026-07-01T08:35:00Z","user_id":1003,"page":"cart","action":"add_to_cart","order":null}'),

('{"event_id":"EVT-8004","timestamp":"2026-07-01T09:10:00Z","user_id":1004,"page":"checkout","action":"purchase","order":{"total":45000.00,"shipping_cost":500.00,"tax":2250.00,"items":5}}'),

('{"event_id":"EVT-8005","timestamp":"2026-07-01T09:45:00Z","user_id":1001,"page":"product_detail","action":"view","order":null}'),

('{"event_id":"EVT-8006","timestamp":"2026-07-02T10:00:00Z","user_id":1005,"page":"checkout","action":"purchase","order":{"total":18000.00,"shipping_cost":300.00,"tax":900.00,"items":3},"promo_code":"SUMMER20","discount_amount":3600.00}'),

('{"event_id":"EVT-8007","timestamp":"2026-07-02T10:15:00Z","user_id":1002,"page":"checkout","action":"purchase","order":{"total":8500.00,"shipping_cost":150.00,"tax":425.00,"items":1},"promo_code":"WELCOME10","discount_amount":850.00}'),

('{"event_id":"EVT-8008","timestamp":"2026-07-02T10:30:00Z","user_id":1006,"page":"cart","action":"add_to_cart","order":null,"promo_code":null,"discount_amount":0.00}'),

('{"event_id":"EVT-8009","timestamp":"2026-07-02T11:00:00Z","user_id":1003,"page":"checkout","action":"purchase","order":{"total":32000.00,"shipping_cost":400.00,"tax":1600.00,"items":4},"promo_code":"FESTIVE15","discount_amount":4800.00}'),

('{"event_id":"EVT-8010","timestamp":"2026-07-02T11:20:00Z","user_id":1007,"page":"product_detail","action":"view","order":null,"promo_code":null,"discount_amount":0.00}'),

('{"event_id":"EVT-8011","timestamp":"2026-07-03T12:00:00Z","user_id":1008,"page":"checkout","action":"purchase","order":{"total":0.00,"shipping_cost":0.00,"tax":0.00,"items":0},"promo_code":"FREEPASS","discount_amount":0.00}'),

('INVALID_JSON_PAYLOAD_MALFORMED_STRING');


CREATE OR REPLACE TABLE LAKE_RAW_EVENTS (
    RAW_DATA VARIANT
);

INSERT INTO LAKE_RAW_EVENTS (RAW_DATA)
SELECT TRY_PARSE_JSON(RAW_RECORD_TEXT)
FROM RAW_EVENT_SOURCE
WHERE TRY_PARSE_JSON(RAW_RECORD_TEXT) IS NOT NULL;


SELECT COUNT(*) AS TOTAL_RAW_RECORD_CT
FROM LAKE_RAW_EVENTS;



SELECT
    RAW_DATA:"event_id"::STRING AS EVENT_ID,
    TO_TIMESTAMP_NTZ(
        REPLACE(RAW_DATA:"timestamp"::STRING, 'Z', '')
    ) AS EVENT_TIME,
    RAW_DATA:"user_id"::INTEGER AS USER_ID,
    RAW_DATA:"action"::STRING AS ACTION,
    RAW_DATA:"order"."total"::NUMBER(12,2) AS ORDER_TOTAL,
    RAW_DATA:"promo_code"::STRING AS PROMO_CODE
FROM LAKE_RAW_EVENTS
ORDER BY EVENT_ID;



SELECT
    RAW_DATA:"event_id"::STRING AS EVENT_ID,
    RAW_DATA:"order"."total"::NUMBER(12,2) AS ORDER_TOTAL,
    RAW_DATA:"order"."shipping_cost"::NUMBER(12,2) AS SHIPPING_COST,
    RAW_DATA:"order"."tax"::NUMBER(12,2) AS TAX,
    COALESCE(
        RAW_DATA:"discount_amount"::NUMBER(12,2),
        0
    ) AS DISCOUNT_AMOUNT,
    (
        RAW_DATA:"order"."total"::NUMBER(12,2)
        - RAW_DATA:"order"."shipping_cost"::NUMBER(12,2)
        - RAW_DATA:"order"."tax"::NUMBER(12,2)
        - COALESCE(
            RAW_DATA:"discount_amount"::NUMBER(12,2),
            0
        )
    ) AS NET_REVENUE
FROM LAKE_RAW_EVENTS
WHERE RAW_DATA:"order"."total"::NUMBER(12,2) > 0
ORDER BY EVENT_ID;



SELECT
    COUNT(*) AS TOTAL_EVENTS,

    COUNT_IF(
        RAW_DATA:"action"::STRING = 'purchase'
    ) AS TOTAL_PURCHASES,

    ROUND(
        COUNT_IF(
            RAW_DATA:"action"::STRING = 'purchase'
        ) * 100.0 / COUNT(*),
        2
    ) AS CONVERSION_RATE_PCT,

    SUM(
        CASE
            WHEN RAW_DATA:"action"::STRING = 'purchase'
            THEN RAW_DATA:"order"."total"::NUMBER(12,2)
            ELSE 0
        END
    ) AS TOTAL_GROSS_REVENUE,

    ROUND(
        SUM(
            CASE
                WHEN RAW_DATA:"action"::STRING = 'purchase'
                THEN RAW_DATA:"order"."total"::NUMBER(12,2)
                ELSE 0
            END
        )
        /
        NULLIF(
            COUNT_IF(
                RAW_DATA:"action"::STRING = 'purchase'
            ),
            0
        ),
        2
    ) AS AVERAGE_ORDER_VALUE

FROM LAKE_RAW_EVENTS;



CREATE OR REPLACE TABLE DW_STRUCTURED_EVENTS (
    EVENT_ID VARCHAR(30),
    EVENT_TIME TIMESTAMP_NTZ,
    USER_ID INTEGER,
    PAGE VARCHAR(100),
    ACTION VARCHAR(50),
    ORDER_TOTAL NUMBER(12,2),
    SHIPPING_COST NUMBER(12,2),
    TAX NUMBER(12,2),
    ITEMS INTEGER,
    PROMO_CODE VARCHAR(50),
    DISCOUNT_AMOUNT NUMBER(12,2),
    NET_REVENUE NUMBER(12,2)
);


--------------------------------------------------------------------------------
-- INSERT VALID EVENTS INTO WAREHOUSE TABLE
--------------------------------------------------------------------------------

INSERT INTO DW_STRUCTURED_EVENTS
(
    EVENT_ID,
    EVENT_TIME,
    USER_ID,
    PAGE,
    ACTION,
    ORDER_TOTAL,
    SHIPPING_COST,
    TAX,
    ITEMS,
    PROMO_CODE,
    DISCOUNT_AMOUNT,
    NET_REVENUE
)
SELECT
    RAW_DATA:"event_id"::STRING,

    TO_TIMESTAMP_NTZ(
        REPLACE(RAW_DATA:"timestamp"::STRING, 'Z', '')
    ),

    RAW_DATA:"user_id"::INTEGER,

    RAW_DATA:"page"::STRING,

    RAW_DATA:"action"::STRING,

    COALESCE(
        RAW_DATA:"order"."total"::NUMBER(12,2),
        0
    ),

    COALESCE(
        RAW_DATA:"order"."shipping_cost"::NUMBER(12,2),
        0
    ),

    COALESCE(
        RAW_DATA:"order"."tax"::NUMBER(12,2),
        0
    ),

    COALESCE(
        RAW_DATA:"order"."items"::INTEGER,
        0
    ),

    RAW_DATA:"promo_code"::STRING,

    COALESCE(
        RAW_DATA:"discount_amount"::NUMBER(12,2),
        0
    ),

    CASE
        WHEN COALESCE(
            RAW_DATA:"order"."total"::NUMBER(12,2),
            0
        ) > 0
        THEN
            RAW_DATA:"order"."total"::NUMBER(12,2)
            - COALESCE(
                RAW_DATA:"order"."shipping_cost"::NUMBER(12,2),
                0
              )
            - COALESCE(
                RAW_DATA:"order"."tax"::NUMBER(12,2),
                0
              )
            - COALESCE(
                RAW_DATA:"discount_amount"::NUMBER(12,2),
                0
              )
        ELSE 0
    END AS NET_REVENUE

FROM LAKE_RAW_EVENTS;


--------------------------------------------------------------------------------
-- VERIFY TASK 5
--------------------------------------------------------------------------------

SELECT
    COUNT(*) AS STORED_RECORDS_QTY,
    SUM(NET_REVENUE) AS TOTAL_NET_REVENUE
FROM DW_STRUCTURED_EVENTS;


--------------------------------------------------------------------------------
-- TASK 6: DATA INTEGRITY & ERROR QUARANTINE
--------------------------------------------------------------------------------

CREATE OR REPLACE TABLE QUARANTINE_RAW_EVENTS (
    QUARANTINE_ID INTEGER AUTOINCREMENT,
    RAW_RECORD_TEXT VARCHAR,
    REASON VARCHAR
);


--------------------------------------------------------------------------------
-- MOVE CORRUPTED / INVALID JSON RECORDS TO QUARANTINE
--------------------------------------------------------------------------------

INSERT INTO QUARANTINE_RAW_EVENTS
(
    RAW_RECORD_TEXT,
    REASON
)
SELECT
    RAW_RECORD_TEXT,
    'MALFORMED_JSON_BODY'
FROM RAW_EVENT_SOURCE
WHERE TRY_PARSE_JSON(RAW_RECORD_TEXT) IS NULL;


--------------------------------------------------------------------------------
-- VERIFY TASK 6
--------------------------------------------------------------------------------

SELECT
    QUARANTINE_ID,
    RAW_RECORD_TEXT,
    REASON
FROM QUARANTINE_RAW_EVENTS
ORDER BY QUARANTINE_ID;


--------------------------------------------------------------------------------
-- FINAL VERIFICATION QUERIES
--------------------------------------------------------------------------------

-- Lake record count
SELECT COUNT(*) AS TOTAL_RAW_RECORD_CT
FROM LAKE_RAW_EVENTS;


-- Warehouse record count and total net revenue
SELECT
    COUNT(*) AS STORED_RECORDS_QTY,
    SUM(NET_REVENUE) AS TOTAL_NET_REVENUE
FROM DW_STRUCTURED_EVENTS;


-- Quarantine count
SELECT COUNT(*) AS QUARANTINED_RECORDS
FROM QUARANTINE_RAW_EVENTS;


-- Final warehouse data
SELECT *
FROM DW_STRUCTURED_EVENTS
ORDER BY EVENT_ID;