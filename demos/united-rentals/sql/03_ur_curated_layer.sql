-- ============================================================================
-- UNITED RENTALS DEMO - Curated Layer: Dynamic Tables with Geospatial
-- ============================================================================
--
-- Creates curated dimensions and facts using Dynamic Tables with TARGET_LAG.
-- Key feature: GEOGRAPHY columns via ST_MAKEPOINT for distance queries.
--
-- This powers the "find equipment within 50 miles" use case:
--   SELECT * FROM FLEET_AVAILABILITY
--   WHERE ST_DISTANCE(EQUIPMENT_LOCATION, ST_MAKEPOINT(-96.7970, 32.7767)) < 80467
--   -- 80467 meters = 50 miles
--
-- Prerequisites: 01_ur_setup.sql, 02_ur_load_data.sql
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE CURATED_DEV;
USE SCHEMA CURATED_DEV.UNITED_RENTALS;
USE WAREHOUSE TRANSFORM_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- DIM_BRANCH — Branch dimension with GEOGRAPHY point
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.UNITED_RENTALS.DIM_BRANCH
    TARGET_LAG = '1 hour'
    WAREHOUSE = TRANSFORM_WH
    COMMENT = 'Branch dimension with geospatial location'
AS
SELECT
    BRANCH_ID,
    BRANCH_NAME,
    BRANCH_TYPE,
    ADDRESS,
    CITY,
    STATE,
    ZIP_CODE,
    LATITUDE,
    LONGITUDE,
    ST_MAKEPOINT(LONGITUDE, LATITUDE) AS BRANCH_LOCATION,
    REGION,
    DISTRICT,
    PHONE,
    MANAGER_NAME,
    OPEN_DATE,
    EMPLOYEE_COUNT,
    IS_ACTIVE
FROM RAW_DEV.UNITED_RENTALS.BRANCHES
WHERE _IS_CURRENT = TRUE;

-- ═══════════════════════════════════════════════════════════════════════════
-- DIM_EQUIPMENT — Equipment dimension with current status and location
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT
    TARGET_LAG = '1 hour'
    WAREHOUSE = TRANSFORM_WH
    COMMENT = 'Equipment dimension with geospatial location and pricing'
AS
SELECT
    EQUIPMENT_ID,
    SERIAL_NUMBER,
    MAKE,
    MODEL,
    CATEGORY,
    SUBCATEGORY,
    DESCRIPTION,
    YEAR_MANUFACTURED,
    ACQUISITION_DATE,
    ACQUISITION_COST,
    REPLACEMENT_COST,
    BRANCH_ID,
    STATUS,
    CONDITION,
    LATITUDE,
    LONGITUDE,
    ST_MAKEPOINT(LONGITUDE, LATITUDE) AS EQUIPMENT_LOCATION,
    LAST_SERVICE_DATE,
    NEXT_SERVICE_DUE,
    HOUR_METER_READING,
    DAILY_RATE,
    WEEKLY_RATE,
    MONTHLY_RATE,
    -- Derived fields
    DATEDIFF('year', ACQUISITION_DATE, CURRENT_DATE()) AS ASSET_AGE_YEARS,
    CASE
        WHEN STATUS = 'AVAILABLE' THEN 'Ready for Rental'
        WHEN STATUS = 'RENTED' THEN 'On Rent'
        WHEN STATUS = 'MAINTENANCE' THEN 'In Service'
        WHEN STATUS = 'TRANSPORT' THEN 'In Transit'
        WHEN STATUS = 'DECOMMISSIONED' THEN 'Retired'
    END AS STATUS_LABEL
FROM RAW_DEV.UNITED_RENTALS.EQUIPMENT
WHERE _IS_CURRENT = TRUE;

-- ═══════════════════════════════════════════════════════════════════════════
-- DIM_CUSTOMER — Customer dimension with segmentation
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.UNITED_RENTALS.DIM_CUSTOMER
    TARGET_LAG = '1 hour'
    WAREHOUSE = TRANSFORM_WH
    COMMENT = 'Customer dimension with credit and revenue segmentation'
AS
SELECT
    CUSTOMER_ID,
    COMPANY_NAME,
    CONTACT_FIRST_NAME,
    CONTACT_LAST_NAME,
    CONTACT_FIRST_NAME || ' ' || CONTACT_LAST_NAME AS CONTACT_FULL_NAME,
    EMAIL,
    PHONE,
    ADDRESS,
    CITY,
    STATE,
    ZIP_CODE,
    LATITUDE,
    LONGITUDE,
    ST_MAKEPOINT(LONGITUDE, LATITUDE) AS CUSTOMER_LOCATION,
    CUSTOMER_TYPE,
    CREDIT_RATING,
    ACCOUNT_STATUS,
    CREDIT_LIMIT,
    YTD_REVENUE,
    -- Segmentation
    CASE
        WHEN YTD_REVENUE >= 200000 THEN 'ENTERPRISE'
        WHEN YTD_REVENUE >= 50000 THEN 'MID-MARKET'
        ELSE 'SMB'
    END AS REVENUE_SEGMENT
FROM RAW_DEV.UNITED_RENTALS.CUSTOMERS
WHERE _IS_CURRENT = TRUE;

-- ═══════════════════════════════════════════════════════════════════════════
-- FACT_RENTALS — Rental transactions with computed metrics
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.UNITED_RENTALS.FACT_RENTALS
    TARGET_LAG = '1 hour'
    WAREHOUSE = TRANSFORM_WH
    COMMENT = 'Rental contract facts with duration and revenue metrics'
AS
SELECT
    r.CONTRACT_ID,
    r.CUSTOMER_ID,
    r.EQUIPMENT_ID,
    r.BRANCH_ID,
    r.RENTAL_START_DATE,
    r.RENTAL_END_DATE,
    r.DURATION_DAYS,
    r.DAILY_RATE,
    r.WEEKLY_RATE,
    r.MONTHLY_RATE,
    r.TOTAL_AMOUNT,
    r.STATUS,
    r.DELIVERY_CITY,
    r.DELIVERY_STATE,
    r.DELIVERY_LATITUDE,
    r.DELIVERY_LONGITUDE,
    ST_MAKEPOINT(r.DELIVERY_LONGITUDE, r.DELIVERY_LATITUDE) AS DELIVERY_LOCATION,
    r.PO_NUMBER,
    r.SALES_REP,
    -- Join to get context
    b.REGION,
    b.CITY AS BRANCH_CITY,
    e.CATEGORY AS EQUIPMENT_CATEGORY,
    e.MAKE AS EQUIPMENT_MAKE,
    e.MODEL AS EQUIPMENT_MODEL,
    c.COMPANY_NAME AS CUSTOMER_NAME,
    c.CUSTOMER_TYPE,
    -- Computed metrics
    CASE
        WHEN r.DURATION_DAYS <= 7 THEN 'DAILY'
        WHEN r.DURATION_DAYS <= 30 THEN 'WEEKLY'
        ELSE 'MONTHLY'
    END AS RENTAL_TERM,
    ROUND(r.TOTAL_AMOUNT / NULLIF(r.DURATION_DAYS, 0), 2) AS REVENUE_PER_DAY
FROM RAW_DEV.UNITED_RENTALS.RENTAL_CONTRACTS r
LEFT JOIN RAW_DEV.UNITED_RENTALS.BRANCHES b ON r.BRANCH_ID = b.BRANCH_ID AND b._IS_CURRENT = TRUE
LEFT JOIN RAW_DEV.UNITED_RENTALS.EQUIPMENT e ON r.EQUIPMENT_ID = e.EQUIPMENT_ID AND e._IS_CURRENT = TRUE
LEFT JOIN RAW_DEV.UNITED_RENTALS.CUSTOMERS c ON r.CUSTOMER_ID = c.CUSTOMER_ID AND c._IS_CURRENT = TRUE
WHERE r._IS_CURRENT = TRUE;

-- ═══════════════════════════════════════════════════════════════════════════
-- FACT_MAINTENANCE — Maintenance events with cost metrics
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.UNITED_RENTALS.FACT_MAINTENANCE
    TARGET_LAG = '1 hour'
    WAREHOUSE = TRANSFORM_WH
    COMMENT = 'Maintenance facts with cost and duration metrics'
AS
SELECT
    m.RECORD_ID,
    m.EQUIPMENT_ID,
    m.BRANCH_ID,
    m.MAINTENANCE_TYPE,
    m.DESCRIPTION,
    m.SCHEDULED_DATE,
    m.START_DATE,
    m.COMPLETION_DATE,
    m.LABOR_HOURS,
    m.PARTS_COST,
    m.LABOR_COST,
    m.TOTAL_COST,
    m.TECHNICIAN_NAME,
    m.STATUS,
    -- Join context
    b.REGION,
    b.CITY AS BRANCH_CITY,
    e.CATEGORY AS EQUIPMENT_CATEGORY,
    e.MAKE AS EQUIPMENT_MAKE,
    e.MODEL AS EQUIPMENT_MODEL,
    -- Derived
    DATEDIFF('day', m.START_DATE, m.COMPLETION_DATE) AS TURNAROUND_DAYS,
    CASE
        WHEN m.TOTAL_COST > 3000 THEN 'HIGH'
        WHEN m.TOTAL_COST > 1000 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS COST_TIER
FROM RAW_DEV.UNITED_RENTALS.MAINTENANCE_RECORDS m
LEFT JOIN RAW_DEV.UNITED_RENTALS.BRANCHES b ON m.BRANCH_ID = b.BRANCH_ID AND b._IS_CURRENT = TRUE
LEFT JOIN RAW_DEV.UNITED_RENTALS.EQUIPMENT e ON m.EQUIPMENT_ID = e.EQUIPMENT_ID AND e._IS_CURRENT = TRUE
WHERE m._IS_CURRENT = TRUE;

-- ═══════════════════════════════════════════════════════════════════════════
-- FACT_TELEMATICS_LATEST — Latest reading per equipment (for map display)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.UNITED_RENTALS.FACT_TELEMATICS_LATEST
    TARGET_LAG = '15 minutes'
    WAREHOUSE = TRANSFORM_WH
    COMMENT = 'Latest telematics reading per equipment for real-time fleet map'
AS
SELECT * FROM (
    SELECT
        t.READING_ID,
        t.EQUIPMENT_ID,
        t.READING_TIMESTAMP,
        t.LATITUDE,
        t.LONGITUDE,
        ST_MAKEPOINT(t.LONGITUDE, t.LATITUDE) AS TELEMATICS_LOCATION,
        t.ENGINE_HOURS,
        t.FUEL_LEVEL_PCT,
        t.BATTERY_VOLTAGE,
        t.IS_RUNNING,
        t.SPEED_MPH,
        t.AMBIENT_TEMP_F,
        t.FAULT_CODE,
        t.FAULT_DESCRIPTION,
        e.CATEGORY AS EQUIPMENT_CATEGORY,
        e.MAKE AS EQUIPMENT_MAKE,
        e.MODEL AS EQUIPMENT_MODEL,
        e.STATUS AS EQUIPMENT_STATUS,
        e.BRANCH_ID,
        b.REGION,
        ROW_NUMBER() OVER (PARTITION BY t.EQUIPMENT_ID ORDER BY t.READING_TIMESTAMP DESC) AS RN
    FROM RAW_DEV.UNITED_RENTALS.TELEMATICS t
    LEFT JOIN RAW_DEV.UNITED_RENTALS.EQUIPMENT e ON t.EQUIPMENT_ID = e.EQUIPMENT_ID AND e._IS_CURRENT = TRUE
    LEFT JOIN RAW_DEV.UNITED_RENTALS.BRANCHES b ON e.BRANCH_ID = b.BRANCH_ID AND b._IS_CURRENT = TRUE
    WHERE t._IS_CURRENT = TRUE
) WHERE RN = 1;

-- ═══════════════════════════════════════════════════════════════════════════
-- FLEET_AVAILABILITY — The key demo view: available equipment for rental
-- ═══════════════════════════════════════════════════════════════════════════
-- This pre-joined view powers the Fleet Finder map and Cortex Analyst queries.
-- It includes GEOGRAPHY columns for ST_DISTANCE proximity searches.

CREATE OR REPLACE VIEW CURATED_DEV.UNITED_RENTALS.FLEET_AVAILABILITY AS
SELECT
    e.EQUIPMENT_ID,
    e.SERIAL_NUMBER,
    e.MAKE,
    e.MODEL,
    e.CATEGORY,
    e.SUBCATEGORY,
    e.DESCRIPTION,
    e.YEAR_MANUFACTURED,
    e.STATUS,
    e.STATUS_LABEL,
    e.CONDITION,
    e.LATITUDE AS EQUIPMENT_LAT,
    e.LONGITUDE AS EQUIPMENT_LON,
    e.EQUIPMENT_LOCATION,
    e.DAILY_RATE,
    e.WEEKLY_RATE,
    e.MONTHLY_RATE,
    e.HOUR_METER_READING,
    e.ASSET_AGE_YEARS,
    -- Branch info
    b.BRANCH_ID,
    b.BRANCH_NAME,
    b.BRANCH_TYPE,
    b.CITY AS BRANCH_CITY,
    b.STATE AS BRANCH_STATE,
    b.LATITUDE AS BRANCH_LAT,
    b.LONGITUDE AS BRANCH_LON,
    b.BRANCH_LOCATION,
    b.REGION,
    b.DISTRICT,
    b.MANAGER_NAME AS BRANCH_MANAGER,
    -- Latest telematics
    t.READING_TIMESTAMP AS LAST_TELEMATICS_AT,
    t.FUEL_LEVEL_PCT,
    t.IS_RUNNING,
    t.FAULT_CODE,
    t.FAULT_DESCRIPTION
FROM CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT e
JOIN CURATED_DEV.UNITED_RENTALS.DIM_BRANCH b ON e.BRANCH_ID = b.BRANCH_ID
LEFT JOIN CURATED_DEV.UNITED_RENTALS.FACT_TELEMATICS_LATEST t ON e.EQUIPMENT_ID = t.EQUIPMENT_ID;

-- Grant select on curated tables to UR roles
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.UNITED_RENTALS TO ROLE UR_FLEET_MANAGER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.UNITED_RENTALS TO ROLE UR_EXTERNAL_PARTNER;
GRANT SELECT ON ALL VIEWS IN SCHEMA CURATED_DEV.UNITED_RENTALS TO ROLE UR_FLEET_MANAGER;
GRANT SELECT ON ALL VIEWS IN SCHEMA CURATED_DEV.UNITED_RENTALS TO ROLE UR_EXTERNAL_PARTNER;
GRANT SELECT ON ALL TABLES IN SCHEMA CURATED_DEV.UNITED_RENTALS TO ROLE UR_FLEET_MANAGER;

SELECT 'Curated layer complete: 5 Dynamic Tables + FLEET_AVAILABILITY view created.' AS STATUS;
