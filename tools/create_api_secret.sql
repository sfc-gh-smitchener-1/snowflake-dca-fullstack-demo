-- =============================================================================
-- Create API Secret in UTIL.API Schema
-- =============================================================================
-- This script creates a secret in the UTIL.API schema with DATA_ADMIN
-- owning all objects. ACCOUNTADMIN only grants necessary permissions.
-- =============================================================================

-- Use ACCOUNTADMIN to set up permissions
USE ROLE ACCOUNTADMIN;

-- =============================================================================
-- Step 1: Create Database and transfer ownership to DATA_ADMIN
-- =============================================================================

-- Create the database and immediately transfer ownership to DATA_ADMIN
CREATE DATABASE IF NOT EXISTS UTIL;
GRANT OWNERSHIP ON DATABASE UTIL TO ROLE DATA_ADMIN COPY CURRENT GRANTS;

-- =============================================================================
-- Step 2: Switch to DATA_ADMIN to create all objects (DATA_ADMIN will own them)
-- =============================================================================

USE ROLE DATA_ADMIN;

-- Create schema (DATA_ADMIN owns this since they own the database)
CREATE SCHEMA IF NOT EXISTS UTIL.API;

USE DATABASE UTIL;
USE SCHEMA API;

-- =============================================================================
-- Step 3: Create the PAT secret (owned by DATA_ADMIN)
-- =============================================================================

-- Create a password-type secret for Personal Access Token (PAT) authentication
CREATE OR REPLACE SECRET PAT_SECRET
    TYPE = PASSWORD
    USERNAME = '<YOUR_USERNAME_HERE>'
    PASSWORD = '<YOUR_PAT_TOKEN_HERE>'
    COMMENT = 'Personal Access Token (PAT) for API authentication';

-- =============================================================================
-- Step 4: Create/Update Git API Integration to use this secret
-- =============================================================================

-- Switch back to ACCOUNTADMIN to manage the integration
USE ROLE ACCOUNTADMIN;

-- Create or replace the Git API integration with the secret
-- This allows the integration to use the PAT_SECRET for authentication
CREATE OR REPLACE API INTEGRATION GIT_API
    API_PROVIDER = GIT_HTTPS_API
    API_ALLOWED_PREFIXES = ('https://github.com/')  -- Adjust to your Git provider
    ALLOWED_AUTHENTICATION_SECRETS = (UTIL.API.PAT_SECRET)
    ENABLED = TRUE
    COMMENT = 'Git API integration for repository access';

-- Grant usage on the integration to DATA_ADMIN
GRANT USAGE ON INTEGRATION GIT_API TO ROLE DATA_ADMIN;

-- =============================================================================
-- Step 5: Verify the secret and integration were created
-- =============================================================================

SHOW SECRETS IN SCHEMA UTIL.API;

-- Describe the secret (note: actual secret value is never shown)
DESCRIBE SECRET UTIL.API.PAT_SECRET;

-- Show the integration
SHOW INTEGRATIONS LIKE 'GIT_API';

-- =============================================================================
-- Cleanup (uncomment to remove)
-- =============================================================================
-- DROP SECRET IF EXISTS UTIL.API.PAT_SECRET;
-- DROP SCHEMA IF EXISTS UTIL.API;
-- DROP DATABASE IF EXISTS UTIL;
