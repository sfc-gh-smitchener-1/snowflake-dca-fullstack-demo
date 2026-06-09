-- ============================================================================
-- HCLS NETWORK HARDENING — HIPAA-GRADE SECURITY
-- ============================================================================
-- Implements defense-in-depth network security for Business Critical accounts.
-- SEs: Replace placeholder CIDRs with actual customer network ranges.
--
-- SECURITY LAYERS IMPLEMENTED:
--   Layer 1: Network Policies (IP allowlisting)
--   Layer 2: Network Rules (PrivateLink/service endpoints)
--   Layer 3: Session Policies (timeout, MFA enforcement)
--   Layer 4: Account Parameters (security hardening)
--
-- TOPOLOGY (from sql/02_bcdr.sql):
--   Primary   : SNOW_BCDR_PRIMARY   (OAB74379)  AWS us-west-2
--   Secondary : SNOW_BCDR_SECONDARY (OZC55031)  AWS us-east-1
--   Org       : SFSENORTHAMERICA
--
-- RUN AS: ACCOUNTADMIN (network policies require ACCOUNTADMIN or SECURITYADMIN)
-- CAUTION: Applying network policy to account will lock out users not on the
--          allowed list. TEST with user-level policy first before account-level.
-- ============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1 — NETWORK RULES
-- ═══════════════════════════════════════════════════════════════════════════
-- Network Rules (introduced 2024) are the preferred approach over legacy
-- IP-based network policies. They support CIDR ranges, host/port, and
-- can be composed into network policies.

USE ROLE ACCOUNTADMIN;

-- Network Rule for corporate VPN / office IP ranges.
-- !! REPLACE these CIDRs with the customer's actual IP ranges !!
-- Common patterns:
--   Corporate VPN:    e.g., 203.0.113.0/24
--   Office network:   e.g., 198.51.100.0/24
--   Cloud egress NAT: e.g., 100.64.0.0/10
CREATE OR REPLACE NETWORK RULE SEM_DEV.HCLS_ANALYTICS.HCLS_CORPORATE_ACCESS
    TYPE = IPV4
    VALUE_LIST = ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')  -- PLACEHOLDER: Replace with customer CIDRs
    MODE = INGRESS
    COMMENT = 'Corporate network access — replace CIDRs with actual customer ranges before deploying';

-- Network Rule for Snowflake internal services (required for tasks,
-- Dynamic Tables, replication, and other platform services).
CREATE OR REPLACE NETWORK RULE SEM_DEV.HCLS_ANALYTICS.HCLS_SNOWFLAKE_INTERNAL
    TYPE = HOST_PORT
    VALUE_LIST = ('*.snowflakecomputing.com:443', '*.amazonaws.com:443')
    MODE = EGRESS
    COMMENT = 'Required egress for Snowflake internal platform services';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2 — NETWORK POLICY
-- ═══════════════════════════════════════════════════════════════════════════
-- Combines network rules into an enforceable policy. The policy restricts
-- inbound access to authorized corporate networks only.

CREATE OR REPLACE NETWORK POLICY HCLS_RESTRICTED_ACCESS
    ALLOWED_NETWORK_RULE_LIST = ('SEM_DEV.HCLS_ANALYTICS.HCLS_CORPORATE_ACCESS')
    BLOCKED_NETWORK_RULE_LIST = ()
    COMMENT = 'HIPAA-grade network restriction — only authorized corporate networks allowed';

-- !! SAFETY PROTOCOL — Test before applying account-wide !!
--
-- Step 1: Apply to a single test user first. Verify you can still
--         connect from your current IP before going account-wide.
--
-- ALTER USER <YOUR_TEST_USER> SET NETWORK_POLICY = 'HCLS_RESTRICTED_ACCESS';
--
-- Step 2: Test — confirm login succeeds from an allowed IP:
--   snowsql -a <account> -u <YOUR_TEST_USER>
--
-- Step 3: Test — confirm login FAILS from an unauthorized IP.
--
-- Step 4: After validation, apply account-wide (uncomment when ready):
-- ALTER ACCOUNT SET NETWORK_POLICY = 'HCLS_RESTRICTED_ACCESS';
--
-- ROLLBACK: If locked out, contact Snowflake Support or use an exempt
-- service account to remove the policy:
-- ALTER ACCOUNT UNSET NETWORK_POLICY;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3 — SESSION POLICY
-- ═══════════════════════════════════════════════════════════════════════════
-- Session policies enforce automatic logoff after inactivity, required by
-- HIPAA §164.312(a)(2)(iii) — "Automatic Logoff" safeguard.

CREATE OR REPLACE SESSION POLICY SEM_DEV.HCLS_ANALYTICS.HCLS_SESSION_POLICY
    SESSION_IDLE_TIMEOUT_MINS = 30           -- 30 min idle timeout (HIPAA §164.312(a)(2)(iii))
    SESSION_UI_IDLE_TIMEOUT_MINS = 15        -- 15 min UI idle timeout (Snowsight/Streamlit)
    COMMENT = 'HIPAA-compliant session management — auto-lock after inactivity';

-- Apply to specific sensitive roles first, then account-wide.
--
-- Per-user (test first):
-- ALTER USER <ADMIN_USER> SET SESSION_POLICY = 'SEM_DEV.HCLS_ANALYTICS.HCLS_SESSION_POLICY';
--
-- Account-wide (uncomment when ready):
-- ALTER ACCOUNT SET SESSION_POLICY = 'SEM_DEV.HCLS_ANALYTICS.HCLS_SESSION_POLICY';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4 — ACCOUNT SECURITY PARAMETERS
-- ═══════════════════════════════════════════════════════════════════════════
-- Hardens account-level parameters to prevent data exfiltration and
-- enforce security best practices.

-- Prevent data exfiltration via uncontrolled stages.
-- This blocks COPY INTO @~/ and COPY INTO 's3://...' without an integration.
ALTER ACCOUNT SET PREVENT_UNLOAD_TO_INLINE_URL = TRUE;

-- Require storage integrations for stage creation (prevents ad-hoc external stages).
-- Uncomment after verifying no legitimate workflows use inline stage URLs.
-- ALTER ACCOUNT SET REQUIRE_STORAGE_INTEGRATION_FOR_STAGE_CREATION = TRUE;
-- ALTER ACCOUNT SET REQUIRE_STORAGE_INTEGRATION_FOR_STAGE_OPERATION = TRUE;

-- Disable password-based user provisioning in production (SSO/SCIM only).
-- Uncomment only after SSO is configured and tested.
-- ALTER ACCOUNT SET DISABLE_USER_PASSWORD_CHANGE = TRUE;

-- Verify periodic data rekeying is active (auto-enabled on BC).
-- AES-256 encryption with automatic annual key rotation.
SHOW PARAMETERS LIKE 'PERIODIC_DATA_REKEYING' IN ACCOUNT;

-- Verify encryption key lifecycle parameters.
SHOW PARAMETERS LIKE '%KEY%' IN ACCOUNT;

-- Verify Tri-Secret Secure status (if customer requires CMK).
-- TSS combines Snowflake's key + customer's KMS key = composite encryption.
-- SHOW PARAMETERS LIKE 'CUSTOMER_KEY' IN ACCOUNT;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5 — PRIVATELINK CONFIGURATION (Documentation / Template)
-- ═══════════════════════════════════════════════════════════════════════════
-- PrivateLink eliminates public internet exposure entirely. All traffic
-- between the customer's VPC and Snowflake traverses AWS PrivateLink
-- (or Azure Private Link / GCP Private Service Connect).
--
-- ARCHITECTURE:
--   Customer VPC → VPC Endpoint → AWS PrivateLink → Snowflake Service
--   (No public internet traversal at any point)
--
-- SETUP STEPS:
--
-- Step 1: Customer creates VPC Endpoint in their AWS account targeting
--         Snowflake's PrivateLink service.
--
-- Step 2: Snowflake authorizes the PrivateLink connection:
--
--   SELECT SYSTEM$AUTHORIZE_PRIVATELINK(
--     '<customer_aws_account_id>',
--     'com.amazonaws.vpce.<region>.<vpce-id>'
--   );
--
-- Step 3: Customer configures DNS to route *.privatelink.snowflakecomputing.com
--         to the VPC Endpoint.
--
-- Step 4: After PrivateLink is active and tested, block public access:
--
--   -- Create a PrivateLink-only network policy
--   CREATE OR REPLACE NETWORK POLICY HCLS_PRIVATE_ONLY
--       ALLOWED_IP_LIST = ()     -- No public IPs allowed
--       COMMENT = 'PrivateLink-only access — all public internet blocked';
--
--   ALTER ACCOUNT SET
--       ALLOW_CLIENT_MFA_CACHING = TRUE,
--       NETWORK_POLICY = 'HCLS_PRIVATE_ONLY';
--
-- Step 5: Verify PrivateLink connectivity:
--
--   SELECT SYSTEM$GET_PRIVATELINK_CONFIG();
--
-- Reference: https://docs.snowflake.com/en/user-guide/admin-security-privatelink


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6 — VALIDATION QUERIES
-- ═══════════════════════════════════════════════════════════════════════════
-- Run these to verify what's been deployed and what's active.

-- List all network policies in the account.
SHOW NETWORK POLICIES;

-- List all network rules.
SHOW NETWORK RULES IN DATABASE DCA_DEMO;

-- Check what network policy is currently applied at account level.
SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN ACCOUNT;

-- List session policies.
SHOW SESSION POLICIES IN DATABASE DCA_DEMO;

-- Verify account security features.
SELECT
    SYSTEM$IS_APPLICATION_ROLE_ENABLED('SNOWFLAKE.SECURITY') AS SECURITY_FEATURES,
    CURRENT_REGION() AS REGION,
    CURRENT_ACCOUNT() AS ACCOUNT;

-- Show all entities with the network policy applied.
-- This returns users, roles, or the account with HCLS_RESTRICTED_ACCESS.
-- Note: This query only works if the policy has been applied to at least one entity.
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(POLICY_NAME => 'HCLS_RESTRICTED_ACCESS'));


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 7 — MONITORING QUERIES (Ongoing Operations)
-- ═══════════════════════════════════════════════════════════════════════════
-- Run these regularly (or configure as Snowflake Alerts) to detect
-- suspicious access patterns.

-- Failed login attempts in the last 24 hours (potential brute force).
SELECT
    USER_NAME,
    CLIENT_IP,
    ERROR_CODE,
    ERROR_MESSAGE,
    EVENT_TIMESTAMP
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE IS_SUCCESS = 'NO'
  AND EVENT_TIMESTAMP > DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY EVENT_TIMESTAMP DESC
LIMIT 50;

-- Successful logins from unexpected IPs in the last 24 hours.
-- These should be investigated — any access from non-corporate IPs
-- when a network policy is active indicates a policy gap.
SELECT
    USER_NAME,
    CLIENT_IP,
    REPORTED_CLIENT_TYPE,
    FIRST_AUTHENTICATION_FACTOR,
    EVENT_TIMESTAMP
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE IS_SUCCESS = 'YES'
  AND CLIENT_IP NOT LIKE '10.%'
  AND CLIENT_IP NOT LIKE '172.16.%'
  AND CLIENT_IP NOT LIKE '192.168.%'
  AND EVENT_TIMESTAMP > DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY EVENT_TIMESTAMP DESC
LIMIT 50;

-- Users without MFA enabled (HIPAA requires strong authentication).
SELECT
    NAME AS USER_NAME,
    LOGIN_NAME,
    HAS_MFA,
    LAST_SUCCESS_LOGIN,
    CREATED_ON
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE DELETED_ON IS NULL
  AND HAS_MFA = 'false'
ORDER BY LAST_SUCCESS_LOGIN DESC;

-- Large data exports in the last 24 hours (potential exfiltration).
SELECT
    USER_NAME,
    QUERY_TEXT,
    ROWS_PRODUCED,
    BYTES_SCANNED,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TYPE = 'UNLOAD'
  AND START_TIME > DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY BYTES_SCANNED DESC
LIMIT 20;


-- ═══════════════════════════════════════════════════════════════════════════
-- SUMMARY
-- ═══════════════════════════════════════════════════════════════════════════
-- What was configured:
--   - HCLS_CORPORATE_ACCESS network rule (ingress CIDR allowlist)
--   - HCLS_SNOWFLAKE_INTERNAL network rule (egress for platform services)
--   - HCLS_RESTRICTED_ACCESS network policy (combines rules)
--   - HCLS_SESSION_POLICY (30-min idle, 15-min UI timeout)
--   - PREVENT_UNLOAD_TO_INLINE_URL = TRUE (anti-exfiltration)
--
-- What requires SE action:
--   1. Replace placeholder CIDRs in HCLS_CORPORATE_ACCESS with customer IPs
--   2. Test network policy on a single user before account-wide deployment
--   3. Apply session policy account-wide after testing
--   4. Configure PrivateLink if customer requires (Part 5 template)
--   5. Set up ongoing monitoring alerts (Part 7 queries)
--
-- Production hardening checklist:
--   [ ] CIDRs replaced with actual customer ranges
--   [ ] Network policy tested on test user
--   [ ] Network policy applied account-wide
--   [ ] Session policy applied account-wide
--   [ ] PrivateLink configured (if required)
--   [ ] MFA enforced for all users
--   [ ] Monitoring alerts configured
--   [ ] SSO/SCIM integration active
--   [ ] Storage integration requirements enforced
