-- ===========================================================================
-- 12_model_discovery.sql  —  Discover which Cortex COMPLETE models actually
--                           work in THIS account/region, and persist the list.
--
-- Why this exists
-- ---------------
-- Snowflake has no SQL command that enumerates the built-in Cortex LLMs
-- (SHOW MODELS only lists ML-registry models). Model availability is
-- region-specific and changes as models are added / deprecated (e.g.
-- snowflake-arctic was retired, and claude-3-5-sonnet is unavailable in
-- some regions). Hard-coding a list in the app therefore rots.
--
-- Instead we probe the full candidate universe (from the AI_COMPLETE docs)
-- with per-model exception handling, keep only the ones that return a
-- completion here, and store them in SILVER.AVAILABLE_MODELS. The Streamlit
-- console reads that table to build its model dropdown.
--
-- Re-run this script (or CALL SILVER.P_REFRESH_AVAILABLE_MODELS()) whenever
-- Snowflake changes its model line-up.
-- ===========================================================================

USE ROLE      ONT_DEMO_BUILDER_ROLE;
USE DATABASE  ONT_DEMO;
USE SCHEMA    SILVER;
USE WAREHOUSE ONT_DEMO_AGENT_WH;

-- ---------------------------------------------------------------------------
-- Persisted catalog of probe results (one row per candidate model).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS SILVER.AVAILABLE_MODELS (
    model_name   STRING      NOT NULL,
    is_available BOOLEAN     NOT NULL,
    note         STRING,                       -- error text when unavailable
    probed_at    TIMESTAMP_NTZ DEFAULT SYSDATE()
);

-- ---------------------------------------------------------------------------
-- Refresh procedure: probe every candidate, repopulate the table.
-- The candidate list is the union of text-completion models documented for
-- AI_COMPLETE / COMPLETE plus common legacy aliases. Unknown / unavailable
-- models are caught per-iteration so one bad model never aborts the sweep.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SILVER.P_REFRESH_AVAILABLE_MODELS()
    RETURNS STRING
    LANGUAGE SQL
    EXECUTE AS CALLER
AS
$$
DECLARE
    candidates ARRAY := ARRAY_CONSTRUCT(
        -- Anthropic Claude
        'claude-4-opus','claude-4-sonnet','claude-3-7-sonnet','claude-3-5-sonnet',
        'claude-3-5-haiku','claude-haiku-4-5','claude-opus-4-5',
        'claude-sonnet-4-5','claude-sonnet-4-6',
        -- Meta Llama
        'llama3-8b','llama3-70b','llama3.1-8b','llama3.1-70b','llama3.1-405b',
        'llama3.2-1b','llama3.2-3b','llama3.3-70b','llama4-maverick','llama4-scout',
        -- Snowflake-hosted
        'snowflake-arctic','snowflake-llama-3.1-405b','snowflake-llama-3.3-70b',
        -- Mistral
        'mistral-large','mistral-large2','mistral-7b','mixtral-8x7b',
        -- OpenAI (via Cortex)
        'openai-gpt-4.1','openai-gpt-5','openai-gpt-5-chat','openai-gpt-5-mini',
        'openai-gpt-5-nano','openai-gpt-5.1','openai-o4-mini',
        -- DeepSeek / Google / others
        'deepseek-r1','gemini-2.5-flash','gemini-2.5-flash-lite',
        'reka-flash','reka-core','jamba-instruct','jamba-1.5-mini',
        'jamba-1.5-large','gemma-7b'
    );
    n         INTEGER := ARRAY_SIZE(candidates);
    ok_count  INTEGER := 0;
    m         STRING;
    i         INTEGER;
BEGIN
    -- Start clean so retired models drop out of the catalog.
    DELETE FROM SILVER.AVAILABLE_MODELS;

    FOR i IN 0 TO n - 1 DO
        m := GET(:candidates, i)::STRING;
        BEGIN
            -- Tiny prompt keeps the probe cheap. (2-arg form: the 3-arg
            -- options form requires a message array, not a plain string.)
            LET probe STRING := SNOWFLAKE.CORTEX.COMPLETE(:m, 'ok');
            INSERT INTO SILVER.AVAILABLE_MODELS (model_name, is_available, note)
                VALUES (:m, TRUE, NULL);
            ok_count := ok_count + 1;
        EXCEPTION
            WHEN OTHER THEN
                LET emsg STRING := LEFT(SQLERRM, 300);
                INSERT INTO SILVER.AVAILABLE_MODELS (model_name, is_available, note)
                    VALUES (:m, FALSE, :emsg);
        END;
    END FOR;

    RETURN ok_count || ' of ' || n || ' candidate models available in '
        || CURRENT_REGION();
END;
$$;

-- Run the sweep now.
CALL SILVER.P_REFRESH_AVAILABLE_MODELS();

-- What the app will offer (ordered for a sensible default: small/cheap first).
SELECT model_name, probed_at
FROM   SILVER.AVAILABLE_MODELS
WHERE  is_available
ORDER BY
    CASE model_name
        WHEN 'llama3.1-8b'   THEN 0
        WHEN 'llama3.3-70b'  THEN 1
        WHEN 'llama3.1-70b'  THEN 2
        WHEN 'mistral-large2' THEN 3
        ELSE 9
    END,
    model_name;

-- For visibility: anything that failed and why.
SELECT model_name, note
FROM   SILVER.AVAILABLE_MODELS
WHERE  NOT is_available
ORDER BY model_name;
