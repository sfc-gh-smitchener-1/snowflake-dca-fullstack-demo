-- ============================================================================
-- UNITED RENTALS DEMO - Semantic Layer: Semantic Views for Cortex Analyst
-- ============================================================================
--
-- Creates Native Semantic Views that power natural language queries:
--   - FLEET_FINDER: "What aerial lifts are available within 50 miles of Dallas?"
--   - RENTAL_ANALYTICS: "Show me revenue by region for Q1"
--
-- These semantic views use the TABLES/RELATIONSHIPS/DIMENSIONS/METRICS syntax
-- that Cortex Analyst understands for text-to-SQL generation.
--
-- Prerequisites: 03_ur_curated_layer.sql
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE SEM_DEV;
USE SCHEMA SEM_DEV.UNITED_RENTALS;
USE WAREHOUSE ANALYTICS_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- FLEET_FINDER — The primary demo semantic view
-- ═══════════════════════════════════════════════════════════════════════════
-- Supports questions like:
--   "Show available boom lifts within 50 miles of Houston"
--   "How many excavators are in the Southwest region?"
--   "What equipment is available at the Dallas branch?"
--   "List equipment with active fault codes"

CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.UNITED_RENTALS.FLEET_FINDER
  TABLES (
    equipment AS CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT
        PRIMARY KEY (EQUIPMENT_ID),
    branches AS CURATED_DEV.UNITED_RENTALS.DIM_BRANCH
        PRIMARY KEY (BRANCH_ID),
    telematics AS CURATED_DEV.UNITED_RENTALS.FACT_TELEMATICS_LATEST
        PRIMARY KEY (EQUIPMENT_ID)
  )
  RELATIONSHIPS (
    equipment(BRANCH_ID) REFERENCES branches(BRANCH_ID),
    telematics(EQUIPMENT_ID) REFERENCES equipment(EQUIPMENT_ID)
  )
  DIMENSIONS (
    equipment.EQUIPMENT_ID AS equipment_id,
    equipment.SERIAL_NUMBER AS serial_number,
    equipment.MAKE AS make,
    equipment.MODEL AS model,
    equipment.CATEGORY AS category
        COMMENT 'Equipment category: AERIAL, EARTHMOVING, MATERIAL_HANDLING, GENERAL_TOOLS, POWER_AND_HVAC, TRENCH_SAFETY',
    equipment.SUBCATEGORY AS subcategory,
    equipment.DESCRIPTION AS equipment_description,
    equipment.YEAR_MANUFACTURED AS year_manufactured,
    equipment.STATUS AS status
        COMMENT 'Equipment status: AVAILABLE, RENTED, MAINTENANCE, TRANSPORT, DECOMMISSIONED',
    equipment.STATUS_LABEL AS status_label,
    equipment.CONDITION AS condition
        COMMENT 'Equipment condition: EXCELLENT, GOOD, FAIR, POOR',
    equipment.LATITUDE AS equipment_latitude,
    equipment.LONGITUDE AS equipment_longitude,
    branches.BRANCH_ID AS branch_id,
    branches.BRANCH_NAME AS branch_name,
    branches.BRANCH_TYPE AS branch_type,
    branches.CITY AS branch_city,
    branches.STATE AS branch_state,
    branches.LATITUDE AS branch_latitude,
    branches.LONGITUDE AS branch_longitude,
    branches.REGION AS region
        COMMENT 'Geographic region: NORTHEAST, SOUTHEAST, MIDWEST, SOUTHWEST, WEST',
    branches.DISTRICT AS district,
    branches.MANAGER_NAME AS branch_manager,
    telematics.IS_RUNNING AS is_running,
    telematics.FUEL_LEVEL_PCT AS fuel_level_pct,
    telematics.FAULT_CODE AS fault_code,
    telematics.FAULT_DESCRIPTION AS fault_description,
    telematics.READING_TIMESTAMP AS last_telematics_reading
  )
  METRICS (
    equipment.equipment_count AS COUNT(equipment.EQUIPMENT_ID),
    equipment.available_count AS COUNT_IF(equipment.STATUS = 'AVAILABLE', equipment.EQUIPMENT_ID),
    equipment.rented_count AS COUNT_IF(equipment.STATUS = 'RENTED', equipment.EQUIPMENT_ID),
    equipment.avg_daily_rate AS AVG(equipment.DAILY_RATE),
    equipment.avg_weekly_rate AS AVG(equipment.WEEKLY_RATE),
    equipment.avg_monthly_rate AS AVG(equipment.MONTHLY_RATE),
    equipment.total_asset_value AS SUM(equipment.REPLACEMENT_COST),
    equipment.avg_age_years AS AVG(equipment.ASSET_AGE_YEARS),
    equipment.avg_hour_meter AS AVG(equipment.HOUR_METER_READING),
    telematics.avg_fuel_level AS AVG(telematics.FUEL_LEVEL_PCT),
    telematics.fault_count AS COUNT(telematics.FAULT_CODE)
  )
  COMMENT = 'Fleet Finder: Find available equipment by category, location, branch, and status. Supports geospatial proximity searches.'
;

-- ═══════════════════════════════════════════════════════════════════════════
-- RENTAL_ANALYTICS — Revenue and utilization analytics
-- ═══════════════════════════════════════════════════════════════════════════
-- Supports questions like:
--   "What is total revenue by region this year?"
--   "Show rental utilization rate by equipment category"
--   "Which customers have the highest rental spend?"
--   "Average rental duration by branch"

CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.UNITED_RENTALS.RENTAL_ANALYTICS
  TABLES (
    rentals AS CURATED_DEV.UNITED_RENTALS.FACT_RENTALS
        PRIMARY KEY (CONTRACT_ID),
    equipment AS CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT
        PRIMARY KEY (EQUIPMENT_ID),
    customers AS CURATED_DEV.UNITED_RENTALS.DIM_CUSTOMER
        PRIMARY KEY (CUSTOMER_ID),
    branches AS CURATED_DEV.UNITED_RENTALS.DIM_BRANCH
        PRIMARY KEY (BRANCH_ID)
  )
  RELATIONSHIPS (
    rentals(EQUIPMENT_ID) REFERENCES equipment(EQUIPMENT_ID),
    rentals(CUSTOMER_ID) REFERENCES customers(CUSTOMER_ID),
    rentals(BRANCH_ID) REFERENCES branches(BRANCH_ID)
  )
  DIMENSIONS (
    rentals.CONTRACT_ID AS contract_id,
    rentals.RENTAL_START_DATE AS rental_start_date,
    rentals.RENTAL_END_DATE AS rental_end_date,
    rentals.STATUS AS rental_status
        COMMENT 'Contract status: ACTIVE, COMPLETED, CANCELLED, OVERDUE',
    rentals.RENTAL_TERM AS rental_term
        COMMENT 'Billing term: DAILY, WEEKLY, MONTHLY',
    rentals.DELIVERY_CITY AS delivery_city,
    rentals.DELIVERY_STATE AS delivery_state,
    rentals.PO_NUMBER AS po_number,
    rentals.SALES_REP AS sales_rep,
    rentals.REGION AS region
        COMMENT 'Geographic region: NORTHEAST, SOUTHEAST, MIDWEST, SOUTHWEST, WEST',
    rentals.BRANCH_CITY AS branch_city,
    rentals.EQUIPMENT_CATEGORY AS equipment_category
        COMMENT 'Equipment category: AERIAL, EARTHMOVING, MATERIAL_HANDLING, GENERAL_TOOLS, POWER_AND_HVAC, TRENCH_SAFETY',
    rentals.EQUIPMENT_MAKE AS equipment_make,
    rentals.CUSTOMER_NAME AS customer_name,
    rentals.CUSTOMER_TYPE AS customer_type
        COMMENT 'Customer type: CONSTRUCTION, INDUSTRIAL, INFRASTRUCTURE, RESIDENTIAL, GOVERNMENT, UTILITY, OIL_AND_GAS, MINING, EVENTS',
    customers.CREDIT_RATING AS credit_rating,
    customers.REVENUE_SEGMENT AS revenue_segment
        COMMENT 'Revenue segment: ENTERPRISE, MID-MARKET, SMB',
    customers.CITY AS customer_city,
    customers.STATE AS customer_state
  )
  METRICS (
    rentals.total_revenue AS SUM(rentals.TOTAL_AMOUNT),
    rentals.contract_count AS COUNT(rentals.CONTRACT_ID),
    rentals.active_contracts AS COUNT_IF(rentals.STATUS = 'ACTIVE', rentals.CONTRACT_ID),
    rentals.avg_duration_days AS AVG(rentals.DURATION_DAYS),
    rentals.avg_daily_rate AS AVG(rentals.DAILY_RATE),
    rentals.avg_revenue_per_day AS AVG(rentals.REVENUE_PER_DAY),
    customers.unique_customers AS COUNT(DISTINCT rentals.CUSTOMER_ID)
  )
  COMMENT = 'Rental Analytics: Revenue, utilization, and customer metrics by region, category, and time period.'
;

-- Grant access to semantic views
GRANT SELECT ON ALL SEMANTIC VIEWS IN SCHEMA SEM_DEV.UNITED_RENTALS TO ROLE UR_FLEET_MANAGER;
GRANT SELECT ON ALL SEMANTIC VIEWS IN SCHEMA SEM_DEV.UNITED_RENTALS TO ROLE UR_EXTERNAL_PARTNER;

SELECT 'Semantic layer complete: FLEET_FINDER and RENTAL_ANALYTICS semantic views created.' AS STATUS;
