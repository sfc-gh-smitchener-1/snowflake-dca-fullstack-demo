-- ============================================================================
-- UNITED RENTALS DEMO - Deploy Streamlit App
-- ============================================================================
--
-- Deploys the Fleet Finder Streamlit app in Snowflake (SiS).
-- The app provides an interactive map for finding equipment and
-- a Cortex Analyst chat interface for natural language fleet queries.
--
-- Prerequisites: 01-05_ur_*.sql scripts, app.py uploaded to stage
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE SEM_DEV;
USE SCHEMA SEM_DEV.UNITED_RENTALS;
USE WAREHOUSE ANALYTICS_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- STREAMLIT STAGE
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE STAGE SEM_DEV.UNITED_RENTALS.UR_STREAMLIT_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'United Rentals Fleet Finder Streamlit app';

-- Upload the app: PUT file:///path/to/demos/united-rentals/streamlit/app.py @UR_STREAMLIT_STAGE;

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER VIEWS (for Streamlit queries that need simplified access)
-- ═══════════════════════════════════════════════════════════════════════════

-- Equipment category summary for dashboard metrics
CREATE OR REPLACE VIEW SEM_DEV.UNITED_RENTALS.V_EQUIPMENT_CATEGORY_SUMMARY AS
SELECT
    CATEGORY,
    COUNT(*) AS TOTAL,
    COUNT_IF(STATUS = 'AVAILABLE') AS AVAILABLE,
    COUNT_IF(STATUS = 'RENTED') AS RENTED,
    COUNT_IF(STATUS = 'MAINTENANCE') AS IN_MAINTENANCE,
    ROUND(AVG(DAILY_RATE), 2) AS AVG_DAILY_RATE,
    ROUND(SUM(REPLACEMENT_COST), 2) AS TOTAL_ASSET_VALUE
FROM CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT
GROUP BY CATEGORY
ORDER BY TOTAL DESC;

-- Regional summary
CREATE OR REPLACE VIEW SEM_DEV.UNITED_RENTALS.V_REGIONAL_SUMMARY AS
SELECT
    b.REGION,
    COUNT(DISTINCT b.BRANCH_ID) AS BRANCHES,
    COUNT(e.EQUIPMENT_ID) AS EQUIPMENT,
    COUNT_IF(e.STATUS = 'AVAILABLE') AS AVAILABLE,
    ROUND(COUNT_IF(e.STATUS = 'RENTED') * 100.0 / NULLIF(COUNT(e.EQUIPMENT_ID), 0), 1) AS UTILIZATION_PCT
FROM CURATED_DEV.UNITED_RENTALS.DIM_BRANCH b
LEFT JOIN CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT e ON b.BRANCH_ID = e.BRANCH_ID
GROUP BY b.REGION
ORDER BY EQUIPMENT DESC;

-- ═══════════════════════════════════════════════════════════════════════════
-- DEPLOY STREAMLIT APP
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE STREAMLIT SEM_DEV.UNITED_RENTALS.UR_FLEET_FINDER
    ROOT_LOCATION = '@SEM_DEV.UNITED_RENTALS.UR_STREAMLIT_STAGE'
    MAIN_FILE = 'app.py'
    QUERY_WAREHOUSE = 'ANALYTICS_WH'
    TITLE = 'United Rentals Fleet Finder'
    COMMENT = 'Interactive fleet management demo: map-based equipment search, RBAC, and Cortex Analyst';

-- Grant access to all UR roles
GRANT USAGE ON STREAMLIT SEM_DEV.UNITED_RENTALS.UR_FLEET_FINDER TO ROLE UR_FLEET_MANAGER;
GRANT USAGE ON STREAMLIT SEM_DEV.UNITED_RENTALS.UR_FLEET_FINDER TO ROLE UR_REGIONAL_DIRECTOR;
GRANT USAGE ON STREAMLIT SEM_DEV.UNITED_RENTALS.UR_FLEET_FINDER TO ROLE UR_BRANCH_MANAGER;
GRANT USAGE ON STREAMLIT SEM_DEV.UNITED_RENTALS.UR_FLEET_FINDER TO ROLE UR_CORPORATE_ANALYST;
GRANT USAGE ON STREAMLIT SEM_DEV.UNITED_RENTALS.UR_FLEET_FINDER TO ROLE UR_EXTERNAL_PARTNER;

-- Grant helper view access
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.UNITED_RENTALS TO ROLE UR_FLEET_MANAGER;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.UNITED_RENTALS TO ROLE UR_EXTERNAL_PARTNER;

SELECT 'Streamlit deployment complete: UR_FLEET_FINDER app created.' AS STATUS;
