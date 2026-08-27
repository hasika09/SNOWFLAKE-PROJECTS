CREATE OR REPLACE WAREHOUSE RETAIL_WH
WITH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE RETAIL_WH;

CREATE OR REPLACE DATABASE RETAIL_SNOWFLAKE_DB;

CREATE OR REPLACE SCHEMA RETAIL_SNOWFLAKE_DB.RETAIL_SCHEMA;

USE DATABASE RETAIL_SNOWFLAKE_DB;
USE SCHEMA RETAIL_SCHEMA;

CREATE OR REPLACE FILE FORMAT RETAIL_CSV_FORMAT
TYPE = 'CSV'
FIELD_DELIMITER = ','
SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY = '"'
NULL_IF = ('NULL', 'null', '');

CREATE OR REPLACE STAGE RETAIL_STAGE
FILE_FORMAT = RETAIL_CSV_FORMAT;

LIST @RETAIL_STAGE;

CREATE OR REPLACE TABLE STG_CUSTOMERS (
    customer_id NUMBER,
    customer_name VARCHAR,
    city VARCHAR,
    state VARCHAR,
    membership VARCHAR
);

COPY INTO STG_CUSTOMERS
FROM @RETAIL_STAGE/customers.csv
FILE_FORMAT = RETAIL_CSV_FORMAT
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE STG_PRODUCTS (
    product_id NUMBER,
    product_name VARCHAR,
    category VARCHAR,
    brand VARCHAR,
    price NUMBER(12,2)
);

COPY INTO STG_PRODUCTS
FROM @RETAIL_STAGE/products.csv
FILE_FORMAT = RETAIL_CSV_FORMAT
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE STG_BRANCHES (
    branch_id NUMBER,
    branch_name VARCHAR,
    city VARCHAR,
    state VARCHAR,
    region VARCHAR,
    manager_name VARCHAR
);

COPY INTO STG_BRANCHES
FROM @RETAIL_STAGE/branches.csv
FILE_FORMAT = RETAIL_CSV_FORMAT
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE STG_CALENDAR (
    date_id NUMBER,
    date DATE,
    day NUMBER,
    day_name VARCHAR,
    week_no NUMBER,
    month VARCHAR,
    quarter VARCHAR,
    year NUMBER,
    is_weekend VARCHAR
);

COPY INTO STG_CALENDAR
FROM @RETAIL_STAGE/calendar.csv
FILE_FORMAT = RETAIL_CSV_FORMAT
ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE STG_SALES (
    sale_id NUMBER,
    customer_id NUMBER,
    product_id NUMBER,
    branch_id NUMBER,
    date_id NUMBER,
    quantity NUMBER,
    total_amount NUMBER(14,2)
);

COPY INTO STG_SALES
FROM @RETAIL_STAGE/sales.csv
FILE_FORMAT = RETAIL_CSV_FORMAT
ON_ERROR = 'CONTINUE';


-- REGION

CREATE OR REPLACE TABLE DIM_REGION (
    region_id NUMBER AUTOINCREMENT,
    region_name VARCHAR NOT NULL,

    CONSTRAINT PK_DIM_REGION
        PRIMARY KEY (region_id)
);

INSERT INTO DIM_REGION (region_name)
SELECT DISTINCT
    TRIM(region)
FROM STG_BRANCHES
WHERE region IS NOT NULL;


-- STATE
-- FIX: DIM_STATE must be populated before DIM_CITY.

CREATE OR REPLACE TABLE DIM_STATE (
    state_id NUMBER AUTOINCREMENT,
    state_name VARCHAR NOT NULL,
    region_id NUMBER NOT NULL,

    CONSTRAINT PK_DIM_STATE
        PRIMARY KEY (state_id),

    CONSTRAINT FK_STATE_REGION
        FOREIGN KEY (region_id)
        REFERENCES DIM_REGION(region_id)
);

INSERT INTO DIM_STATE (state_name, region_id)
SELECT DISTINCT
    TRIM(b.state),
    r.region_id
FROM STG_BRANCHES b
JOIN DIM_REGION r
    ON TRIM(LOWER(b.region)) = TRIM(LOWER(r.region_name))
WHERE b.state IS NOT NULL;


-- CITY

CREATE OR REPLACE TABLE DIM_CITY (
    city_id NUMBER AUTOINCREMENT,
    city_name VARCHAR NOT NULL,
    state_id NUMBER NOT NULL,

    CONSTRAINT PK_DIM_CITY
        PRIMARY KEY (city_id),

    CONSTRAINT FK_CITY_STATE
        FOREIGN KEY (state_id)
        REFERENCES DIM_STATE(state_id)
);

INSERT INTO DIM_CITY (city_name, state_id)
SELECT DISTINCT
    TRIM(x.city),
    s.state_id
FROM (
    SELECT city, state
    FROM STG_BRANCHES

    UNION

    SELECT city, state
    FROM STG_CUSTOMERS
) x
JOIN DIM_STATE s
    ON TRIM(LOWER(x.state)) = TRIM(LOWER(s.state_name))
WHERE x.city IS NOT NULL;


-- CATEGORY

CREATE OR REPLACE TABLE DIM_CATEGORY (
    category_id NUMBER AUTOINCREMENT,
    category_name VARCHAR NOT NULL,

    CONSTRAINT PK_DIM_CATEGORY
        PRIMARY KEY (category_id)
);

INSERT INTO DIM_CATEGORY (category_name)
SELECT DISTINCT
    TRIM(category)
FROM STG_PRODUCTS
WHERE category IS NOT NULL;


-- BRAND

CREATE OR REPLACE TABLE DIM_BRAND (
    brand_id NUMBER AUTOINCREMENT,
    brand_name VARCHAR NOT NULL,
    category_id NUMBER NOT NULL,

    CONSTRAINT PK_DIM_BRAND
        PRIMARY KEY (brand_id),

    CONSTRAINT FK_BRAND_CATEGORY
        FOREIGN KEY (category_id)
        REFERENCES DIM_CATEGORY(category_id)
);

INSERT INTO DIM_BRAND (brand_name, category_id)
SELECT DISTINCT
    TRIM(p.brand),
    c.category_id
FROM STG_PRODUCTS p
JOIN DIM_CATEGORY c
    ON TRIM(LOWER(p.category)) = TRIM(LOWER(c.category_name))
WHERE p.brand IS NOT NULL;


-- YEAR

CREATE OR REPLACE TABLE DIM_YEAR (
    year_id NUMBER AUTOINCREMENT,
    year_value NUMBER NOT NULL,

    CONSTRAINT PK_DIM_YEAR
        PRIMARY KEY (year_id)
);

INSERT INTO DIM_YEAR (year_value)
SELECT DISTINCT
    year
FROM STG_CALENDAR
WHERE year IS NOT NULL;


-- QUARTER

CREATE OR REPLACE TABLE DIM_QUARTER (
    quarter_id NUMBER AUTOINCREMENT,
    quarter_name VARCHAR NOT NULL,
    year_id NUMBER NOT NULL,

    CONSTRAINT PK_DIM_QUARTER
        PRIMARY KEY (quarter_id),

    CONSTRAINT FK_QUARTER_YEAR
        FOREIGN KEY (year_id)
        REFERENCES DIM_YEAR(year_id)
);

INSERT INTO DIM_QUARTER (quarter_name, year_id)
SELECT DISTINCT
    TRIM(c.quarter),
    y.year_id
FROM STG_CALENDAR c
JOIN DIM_YEAR y
    ON c.year = y.year_value
WHERE c.quarter IS NOT NULL;


-- MONTH

CREATE OR REPLACE TABLE DIM_MONTH (
    month_id NUMBER AUTOINCREMENT,
    month_name VARCHAR NOT NULL,
    quarter_id NUMBER NOT NULL,

    CONSTRAINT PK_DIM_MONTH
        PRIMARY KEY (month_id),

    CONSTRAINT FK_MONTH_QUARTER
        FOREIGN KEY (quarter_id)
        REFERENCES DIM_QUARTER(quarter_id)
);

INSERT INTO DIM_MONTH (month_name, quarter_id)
SELECT DISTINCT
    TRIM(c.month),
    q.quarter_id
FROM STG_CALENDAR c
JOIN DIM_YEAR y
    ON c.year = y.year_value
JOIN DIM_QUARTER q
    ON TRIM(LOWER(c.quarter)) = TRIM(LOWER(q.quarter_name))
   AND q.year_id = y.year_id
WHERE c.month IS NOT NULL;


-- DATE

CREATE OR REPLACE TABLE DIM_DATE (
    date_id NUMBER,
    date_value DATE,
    day_number NUMBER,
    day_name VARCHAR,
    week_no NUMBER,
    is_weekend VARCHAR,
    month_id NUMBER NOT NULL,

    CONSTRAINT PK_DIM_DATE
        PRIMARY KEY (date_id),

    CONSTRAINT FK_DATE_MONTH
        FOREIGN KEY (month_id)
        REFERENCES DIM_MONTH(month_id)
);

INSERT INTO DIM_DATE (
    date_id,
    date_value,
    day_number,
    day_name,
    week_no,
    is_weekend,
    month_id
)
SELECT
    c.date_id,
    c.date,
    c.day,
    c.day_name,
    c.week_no,
    c.is_weekend,
    m.month_id
FROM STG_CALENDAR c
JOIN DIM_YEAR y
    ON c.year = y.year_value
JOIN DIM_QUARTER q
    ON TRIM(LOWER(c.quarter)) = TRIM(LOWER(q.quarter_name))
   AND q.year_id = y.year_id
JOIN DIM_MONTH m
    ON TRIM(LOWER(c.month)) = TRIM(LOWER(m.month_name))
   AND m.quarter_id = q.quarter_id;


-- CUSTOMER

CREATE OR REPLACE TABLE DIM_CUSTOMER (
    customer_id NUMBER,
    customer_name VARCHAR,
    membership VARCHAR,
    city_id NUMBER NOT NULL,

    CONSTRAINT PK_DIM_CUSTOMER
        PRIMARY KEY (customer_id),

    CONSTRAINT FK_CUSTOMER_CITY
        FOREIGN KEY (city_id)
        REFERENCES DIM_CITY(city_id)
);

INSERT INTO DIM_CUSTOMER (
    customer_id,
    customer_name,
    membership,
    city_id
)
SELECT
    c.customer_id,
    c.customer_name,
    c.membership,
    ci.city_id
FROM STG_CUSTOMERS c
JOIN DIM_CITY ci
    ON TRIM(LOWER(c.city)) = TRIM(LOWER(ci.city_name))
JOIN DIM_STATE s
    ON ci.state_id = s.state_id
   AND TRIM(LOWER(c.state)) = TRIM(LOWER(s.state_name));

-- PRODUCT

CREATE OR REPLACE TABLE DIM_PRODUCT (
    product_id NUMBER,
    product_name VARCHAR,
    price NUMBER(12,2),
    brand_id NUMBER NOT NULL,

    CONSTRAINT PK_DIM_PRODUCT
        PRIMARY KEY (product_id),

    CONSTRAINT FK_PRODUCT_BRAND
        FOREIGN KEY (brand_id)
        REFERENCES DIM_BRAND(brand_id)
);

INSERT INTO DIM_PRODUCT (
    product_id,
    product_name,
    price,
    brand_id
)
SELECT
    p.product_id,
    p.product_name,
    p.price,
    b.brand_id
FROM STG_PRODUCTS p
JOIN DIM_BRAND b
    ON TRIM(LOWER(p.brand)) = TRIM(LOWER(b.brand_name))
JOIN DIM_CATEGORY c
    ON TRIM(LOWER(p.category)) = TRIM(LOWER(c.category_name))
   AND b.category_id = c.category_id;


-- BRANCH

CREATE OR REPLACE TABLE DIM_BRANCH (
    branch_id NUMBER,
    branch_name VARCHAR,
    manager_name VARCHAR,
    city_id NUMBER NOT NULL,

    CONSTRAINT PK_DIM_BRANCH
        PRIMARY KEY (branch_id),

    CONSTRAINT FK_BRANCH_CITY
        FOREIGN KEY (city_id)
        REFERENCES DIM_CITY(city_id)
);

INSERT INTO DIM_BRANCH (
    branch_id,
    branch_name,
    manager_name,
    city_id
)
SELECT
    b.branch_id,
    b.branch_name,
    b.manager_name,
    c.city_id
FROM STG_BRANCHES b
JOIN DIM_CITY c
    ON TRIM(LOWER(b.city)) = TRIM(LOWER(c.city_name))
JOIN DIM_STATE s
    ON c.state_id = s.state_id
   AND TRIM(LOWER(b.state)) = TRIM(LOWER(s.state_name));


-- FACT SALES

CREATE OR REPLACE TABLE FACT_SALES (
    sale_id NUMBER,
    customer_id NUMBER,
    product_id NUMBER,
    branch_id NUMBER,
    date_id NUMBER,
    quantity NUMBER,
    total_amount NUMBER(14,2),

    CONSTRAINT PK_FACT_SALES
        PRIMARY KEY (sale_id),

    CONSTRAINT FK_FACT_CUSTOMER
        FOREIGN KEY (customer_id)
        REFERENCES DIM_CUSTOMER(customer_id),

    CONSTRAINT FK_FACT_PRODUCT
        FOREIGN KEY (product_id)
        REFERENCES DIM_PRODUCT(product_id),

    CONSTRAINT FK_FACT_BRANCH
        FOREIGN KEY (branch_id)
        REFERENCES DIM_BRANCH(branch_id),

    CONSTRAINT FK_FACT_DATE
        FOREIGN KEY (date_id)
        REFERENCES DIM_DATE(date_id)
);

INSERT INTO FACT_SALES (
    sale_id,
    customer_id,
    product_id,
    branch_id,
    date_id,
    quantity,
    total_amount
)
SELECT
    sale_id,
    customer_id,
    product_id,
    branch_id,
    date_id,
    quantity,
    total_amount
FROM STG_SALES;


-- VALIDATION

SELECT COUNT(*) AS REGION_COUNT FROM DIM_REGION;
SELECT COUNT(*) AS STATE_COUNT FROM DIM_STATE;
SELECT COUNT(*) AS CITY_COUNT FROM DIM_CITY;
SELECT COUNT(*) AS CATEGORY_COUNT FROM DIM_CATEGORY;
SELECT COUNT(*) AS BRAND_COUNT FROM DIM_BRAND;
SELECT COUNT(*) AS YEAR_COUNT FROM DIM_YEAR;
SELECT COUNT(*) AS QUARTER_COUNT FROM DIM_QUARTER;
SELECT COUNT(*) AS MONTH_COUNT FROM DIM_MONTH;
SELECT COUNT(*) AS DATE_COUNT FROM DIM_DATE;
SELECT COUNT(*) AS CUSTOMER_COUNT FROM DIM_CUSTOMER;
SELECT COUNT(*) AS PRODUCT_COUNT FROM DIM_PRODUCT;
SELECT COUNT(*) AS BRANCH_COUNT FROM DIM_BRANCH;
SELECT COUNT(*) AS FACT_SALES_COUNT FROM FACT_SALES;


-- CUSTOMER REPORT

SELECT
    c.customer_id,
    c.customer_name,
    ci.city_name,
    s.state_name,
    r.region_name,
    c.membership
FROM DIM_CUSTOMER c
JOIN DIM_CITY ci
    ON c.city_id = ci.city_id
JOIN DIM_STATE s
    ON ci.state_id = s.state_id
JOIN DIM_REGION r
    ON s.region_id = r.region_id
ORDER BY c.customer_id;


-- PRODUCT REPORT

SELECT
    p.product_id,
    p.product_name,
    b.brand_name,
    c.category_name,
    p.price
FROM DIM_PRODUCT p
JOIN DIM_BRAND b
    ON p.brand_id = b.brand_id
JOIN DIM_CATEGORY c
    ON b.category_id = c.category_id
ORDER BY p.product_id;


-- BRANCH REPORT

SELECT
    b.branch_id,
    b.branch_name,
    ci.city_name,
    s.state_name,
    r.region_name,
    b.manager_name
FROM DIM_BRANCH b
JOIN DIM_CITY ci
    ON b.city_id = ci.city_id
JOIN DIM_STATE s
    ON ci.state_id = s.state_id
JOIN DIM_REGION r
    ON s.region_id = r.region_id
ORDER BY b.branch_id;


-- DATE REPORT

SELECT
    d.date_id,
    d.date_value,
    m.month_name,
    q.quarter_name,
    y.year_value
FROM DIM_DATE d
JOIN DIM_MONTH m
    ON d.month_id = m.month_id
JOIN DIM_QUARTER q
    ON m.quarter_id = q.quarter_id
JOIN DIM_YEAR y
    ON q.year_id = y.year_id
ORDER BY d.date_id;


-- CUSTOMER SALES

SELECT
    c.customer_id,
    c.customer_name,
    SUM(f.total_amount) AS total_sales
FROM FACT_SALES f
JOIN DIM_CUSTOMER c
    ON f.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.customer_name
ORDER BY total_sales DESC;


-- BRAND REVENUE

SELECT
    b.brand_name,
    SUM(f.total_amount) AS revenue
FROM FACT_SALES f
JOIN DIM_PRODUCT p
    ON f.product_id = p.product_id
JOIN DIM_BRAND b
    ON p.brand_id = b.brand_id
GROUP BY b.brand_name
ORDER BY revenue DESC;


-- CATEGORY REVENUE

SELECT
    c.category_name,
    SUM(f.total_amount) AS revenue
FROM FACT_SALES f
JOIN DIM_PRODUCT p
    ON f.product_id = p.product_id
JOIN DIM_BRAND b
    ON p.brand_id = b.brand_id
JOIN DIM_CATEGORY c
    ON b.category_id = c.category_id
GROUP BY c.category_name
ORDER BY revenue DESC;


-- CITY SALES

SELECT
    ci.city_name,
    SUM(f.total_amount) AS total_sales
FROM FACT_SALES f
JOIN DIM_BRANCH b
    ON f.branch_id = b.branch_id
JOIN DIM_CITY ci
    ON b.city_id = ci.city_id
GROUP BY ci.city_name
ORDER BY total_sales DESC;


-- STATE SALES

SELECT
    s.state_name,
    SUM(f.total_amount) AS total_sales
FROM FACT_SALES f
JOIN DIM_BRANCH b
    ON f.branch_id = b.branch_id
JOIN DIM_CITY ci
    ON b.city_id = ci.city_id
JOIN DIM_STATE s
    ON ci.state_id = s.state_id
GROUP BY s.state_name
ORDER BY total_sales DESC;


-- REGION SALES

SELECT
    r.region_name,
    SUM(f.total_amount) AS total_sales
FROM FACT_SALES f
JOIN DIM_BRANCH b
    ON f.branch_id = b.branch_id
JOIN DIM_CITY ci
    ON b.city_id = ci.city_id
JOIN DIM_STATE s
    ON ci.state_id = s.state_id
JOIN DIM_REGION r
    ON s.region_id = r.region_id
GROUP BY r.region_name
ORDER BY total_sales DESC;


-- MONTHLY REVENUE

SELECT
    y.year_value,
    m.month_name,
    SUM(f.total_amount) AS monthly_revenue
FROM FACT_SALES f
JOIN DIM_DATE d
    ON f.date_id = d.date_id
JOIN DIM_MONTH m
    ON d.month_id = m.month_id
JOIN DIM_QUARTER q
    ON m.quarter_id = q.quarter_id
JOIN DIM_YEAR y
    ON q.year_id = y.year_id
GROUP BY
    y.year_value,
    m.month_name
ORDER BY
    y.year_value,
    MIN(d.date_value);


-- QUARTERLY REVENUE

SELECT
    y.year_value,
    q.quarter_name,
    SUM(f.total_amount) AS quarterly_revenue
FROM FACT_SALES f
JOIN DIM_DATE d
    ON f.date_id = d.date_id
JOIN DIM_MONTH m
    ON d.month_id = m.month_id
JOIN DIM_QUARTER q
    ON m.quarter_id = q.quarter_id
JOIN DIM_YEAR y
    ON q.year_id = y.year_id
GROUP BY
    y.year_value,
    q.quarter_name
ORDER BY
    y.year_value,
    q.quarter_name;


-- TOP 10 CUSTOMERS

SELECT
    c.customer_id,
    c.customer_name,
    SUM(f.total_amount) AS revenue
FROM FACT_SALES f
JOIN DIM_CUSTOMER c
    ON f.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.customer_name
ORDER BY revenue DESC
LIMIT 10;


-- TOP 10 PRODUCTS

SELECT
    p.product_id,
    p.product_name,
    SUM(f.total_amount) AS revenue
FROM FACT_SALES f
JOIN DIM_PRODUCT p
    ON f.product_id = p.product_id
GROUP BY
    p.product_id,
    p.product_name
ORDER BY revenue DESC
LIMIT 10;


-- TOP 10 BRANCHES

SELECT
    b.branch_id,
    b.branch_name,
    SUM(f.total_amount) AS revenue
FROM FACT_SALES f
JOIN DIM_BRANCH b
    ON f.branch_id = b.branch_id
GROUP BY
    b.branch_id,
    b.branch_name
ORDER BY revenue DESC
LIMIT 10;


-- CUSTOMER DAILY PURCHASE

SELECT
    c.customer_name,
    d.date_value,
    SUM(f.total_amount) AS daily_purchase
FROM FACT_SALES f
JOIN DIM_CUSTOMER c
    ON f.customer_id = c.customer_id
JOIN DIM_DATE d
    ON f.date_id = d.date_id
GROUP BY
    c.customer_name,
    d.date_value
ORDER BY
    c.customer_name,
    d.date_value;


-- PRODUCT PERFORMANCE

SELECT
    p.product_name,
    b.brand_name,
    c.category_name,
    SUM(f.quantity) AS total_quantity,
    SUM(f.total_amount) AS total_revenue,
    AVG(f.total_amount) AS avg_sale
FROM FACT_SALES f
JOIN DIM_PRODUCT p
    ON f.product_id = p.product_id
JOIN DIM_BRAND b
    ON p.brand_id = b.brand_id
JOIN DIM_CATEGORY c
    ON b.category_id = c.category_id
GROUP BY
    p.product_name,
    b.brand_name,
    c.category_name
ORDER BY total_revenue DESC;


-- GEOGRAPHICAL SALES

SELECT
    r.region_name,
    s.state_name,
    ci.city_name,
    b.branch_name,
    SUM(f.quantity) AS total_quantity,
    SUM(f.total_amount) AS total_sales
FROM FACT_SALES f
JOIN DIM_BRANCH b
    ON f.branch_id = b.branch_id
JOIN DIM_CITY ci
    ON b.city_id = ci.city_id
JOIN DIM_STATE s
    ON ci.state_id = s.state_id
JOIN DIM_REGION r
    ON s.region_id = r.region_id
GROUP BY
    r.region_name,
    s.state_name,
    ci.city_name,
    b.branch_name
ORDER BY
    r.region_name,
    total_sales DESC;


-- FACT VALIDATION

SELECT COUNT(*) AS fact_count
FROM FACT_SALES;

SELECT SUM(quantity) AS total_quantity
FROM FACT_SALES;

SELECT SUM(total_amount) AS total_revenue
FROM FACT_SALES;

SELECT COUNT(*) AS missing_customers
FROM FACT_SALES f
LEFT JOIN DIM_CUSTOMER c
    ON f.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

SELECT COUNT(*) AS missing_products
FROM FACT_SALES f
LEFT JOIN DIM_PRODUCT p
    ON f.product_id = p.product_id
WHERE p.product_id IS NULL;

SELECT COUNT(*) AS missing_branches
FROM FACT_SALES f
LEFT JOIN DIM_BRANCH b
    ON f.branch_id = b.branch_id
WHERE b.branch_id IS NULL;

SELECT COUNT(*) AS missing_dates
FROM FACT_SALES f
LEFT JOIN DIM_DATE d
    ON f.date_id = d.date_id
WHERE d.date_id IS NULL;
