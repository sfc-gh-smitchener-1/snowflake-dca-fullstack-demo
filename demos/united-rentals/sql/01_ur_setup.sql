-- ============================================================================
-- UNITED RENTALS DEMO - Setup: Databases, Schemas, Roles, Tags
-- ============================================================================
--
-- Creates the UR-specific infrastructure within the existing DCA framework:
--   - Schemas under existing RAW_DEV, CURATED_DEV, SEM_DEV databases
--   - 5 UR-specific roles demonstrating graduated RBAC
--   - Governance tags for equipment rental domain
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- SCHEMAS (Container-by-DB pattern: one schema per domain)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS RAW_DEV.UNITED_RENTALS
    COMMENT = 'United Rentals raw equipment rental data';

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.UNITED_RENTALS
    COMMENT = 'United Rentals curated dimensions and facts';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.UNITED_RENTALS
    COMMENT = 'United Rentals semantic views for Cortex Analyst';

-- ═══════════════════════════════════════════════════════════════════════════
-- UR-SPECIFIC ROLES (graduated access for equipment rental)
-- ═══════════════════════════════════════════════════════════════════════════

-- Role hierarchy:
--   DATA_ADMIN
--     ├── UR_FLEET_MANAGER       — full fleet visibility, all branches, all pricing
--     │     ├── UR_REGIONAL_DIRECTOR  — region-scoped, full pricing
--     │     │     └── UR_BRANCH_MANAGER    — branch-scoped, limited pricing
--     │     └── UR_CORPORATE_ANALYST  — all branches, PII masked, pricing visible
--     └── UR_EXTERNAL_PARTNER    — minimal access, no pricing, no PII

CREATE ROLE IF NOT EXISTS UR_FLEET_MANAGER
    COMMENT = 'United Rentals: Full fleet visibility across all branches and regions';

CREATE ROLE IF NOT EXISTS UR_REGIONAL_DIRECTOR
    COMMENT = 'United Rentals: Region-scoped fleet access with full pricing';

CREATE ROLE IF NOT EXISTS UR_BRANCH_MANAGER
    COMMENT = 'United Rentals: Branch-scoped fleet access with limited pricing';

CREATE ROLE IF NOT EXISTS UR_CORPORATE_ANALYST
    COMMENT = 'United Rentals: Cross-branch analytics with PII masking';

CREATE ROLE IF NOT EXISTS UR_EXTERNAL_PARTNER
    COMMENT = 'United Rentals: Minimal access for external partners - no pricing or PII';

-- Role hierarchy grants
GRANT ROLE UR_FLEET_MANAGER TO ROLE DATA_ADMIN;
GRANT ROLE UR_REGIONAL_DIRECTOR TO ROLE UR_FLEET_MANAGER;
GRANT ROLE UR_BRANCH_MANAGER TO ROLE UR_REGIONAL_DIRECTOR;
GRANT ROLE UR_CORPORATE_ANALYST TO ROLE UR_FLEET_MANAGER;
GRANT ROLE UR_EXTERNAL_PARTNER TO ROLE DATA_ADMIN;

-- Warehouse access
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE UR_FLEET_MANAGER;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE UR_REGIONAL_DIRECTOR;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE UR_BRANCH_MANAGER;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE UR_CORPORATE_ANALYST;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE UR_EXTERNAL_PARTNER;

-- Database and schema access for all UR roles
GRANT USAGE ON DATABASE RAW_DEV TO ROLE UR_FLEET_MANAGER;
GRANT USAGE ON DATABASE RAW_DEV TO ROLE UR_EXTERNAL_PARTNER;
GRANT USAGE ON SCHEMA RAW_DEV.UNITED_RENTALS TO ROLE UR_FLEET_MANAGER;
GRANT USAGE ON SCHEMA RAW_DEV.UNITED_RENTALS TO ROLE UR_EXTERNAL_PARTNER;

GRANT USAGE ON DATABASE CURATED_DEV TO ROLE UR_FLEET_MANAGER;
GRANT USAGE ON DATABASE CURATED_DEV TO ROLE UR_EXTERNAL_PARTNER;
GRANT USAGE ON SCHEMA CURATED_DEV.UNITED_RENTALS TO ROLE UR_FLEET_MANAGER;
GRANT USAGE ON SCHEMA CURATED_DEV.UNITED_RENTALS TO ROLE UR_EXTERNAL_PARTNER;

GRANT USAGE ON DATABASE SEM_DEV TO ROLE UR_FLEET_MANAGER;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE UR_EXTERNAL_PARTNER;
GRANT USAGE ON SCHEMA SEM_DEV.UNITED_RENTALS TO ROLE UR_FLEET_MANAGER;
GRANT USAGE ON SCHEMA SEM_DEV.UNITED_RENTALS TO ROLE UR_EXTERNAL_PARTNER;

-- ═══════════════════════════════════════════════════════════════════════════
-- GOVERNANCE TAGS (equipment rental domain)
-- ═══════════════════════════════════════════════════════════════════════════

USE DATABASE GOVERNANCE;
USE SCHEMA GOVERNANCE.TAGS;

CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.UR_DATA_DOMAIN
    ALLOWED_VALUES = 'FLEET', 'CUSTOMER', 'RENTAL', 'MAINTENANCE', 'TELEMATICS'
    COMMENT = 'United Rentals data domain classification';

CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.UR_SENSITIVITY
    ALLOWED_VALUES = 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED'
    COMMENT = 'United Rentals data sensitivity level';

CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.UR_REGION
    ALLOWED_VALUES = 'NORTHEAST', 'SOUTHEAST', 'MIDWEST', 'SOUTHWEST', 'WEST'
    COMMENT = 'United Rentals regional assignment for row access';

-- ═══════════════════════════════════════════════════════════════════════════
-- ROLE-REGION MAPPING TABLE (for row access policies)
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA CURATED_DEV.UNITED_RENTALS;

CREATE OR REPLACE TABLE CURATED_DEV.UNITED_RENTALS.ROLE_REGION_MAPPING (
    ROLE_NAME VARCHAR(50) NOT NULL,
    REGION VARCHAR(20) NOT NULL,
    BRANCH_ID VARCHAR(10),
    CONSTRAINT UK_ROLE_REGION UNIQUE (ROLE_NAME, REGION, BRANCH_ID)
)
COMMENT = 'Maps UR roles to their authorized regions/branches for row access policies';

-- Fleet Manager sees all regions
INSERT INTO CURATED_DEV.UNITED_RENTALS.ROLE_REGION_MAPPING (ROLE_NAME, REGION)
SELECT 'UR_FLEET_MANAGER', VALUE
FROM TABLE(FLATTEN(SPLIT('NORTHEAST,SOUTHEAST,MIDWEST,SOUTHWEST,WEST', ',')));

-- Corporate Analyst sees all regions
INSERT INTO CURATED_DEV.UNITED_RENTALS.ROLE_REGION_MAPPING (ROLE_NAME, REGION)
SELECT 'UR_CORPORATE_ANALYST', VALUE
FROM TABLE(FLATTEN(SPLIT('NORTHEAST,SOUTHEAST,MIDWEST,SOUTHWEST,WEST', ',')));

-- Regional Director demo: assigned to SOUTHWEST
INSERT INTO CURATED_DEV.UNITED_RENTALS.ROLE_REGION_MAPPING (ROLE_NAME, REGION)
VALUES ('UR_REGIONAL_DIRECTOR', 'SOUTHWEST');

-- Branch Manager demo: assigned to SOUTHWEST + specific branch
INSERT INTO CURATED_DEV.UNITED_RENTALS.ROLE_REGION_MAPPING (ROLE_NAME, REGION, BRANCH_ID)
VALUES ('UR_BRANCH_MANAGER', 'SOUTHWEST', 'BR-01024');

-- External Partner: limited to SOUTHWEST
INSERT INTO CURATED_DEV.UNITED_RENTALS.ROLE_REGION_MAPPING (ROLE_NAME, REGION)
VALUES ('UR_EXTERNAL_PARTNER', 'SOUTHWEST');

SELECT 'UR Setup complete: schemas, roles, tags, and role-region mapping created.' AS STATUS;
