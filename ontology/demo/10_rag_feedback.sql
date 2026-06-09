-- ============================================================================
-- Snowflake Ontology Reference — 10_rag_feedback.sql
-- ============================================================================
-- The product + governance feedback loop.
--
-- What it adds
--   1. silver.rag_feedback                 — append-only log of every chat
--                                            round-trip + thumbs feedback
--   2. silver.p_log_rag                    — convenience proc the Streamlit
--                                            app calls after every answer
--   3. gold.v_rag_feedback_summary         — KPIs the PM and CDO want:
--                                            volume, satisfaction, avg
--                                            latency, model mix, blocked
--   4. gold.v_rag_feedback_for_finetune    — JSONL view shaped for
--                                            SNOWFLAKE.CORTEX.FINETUNE on
--                                            llama3.1-8b
--   5. silver.t_rag_finetune_weekly        — commented-out scheduled task
--                                            that kicks off a fine-tune from
--                                            accepted answers (production
--                                            opt-in)
--
-- Idempotent. Re-runnable.
-- ============================================================================

USE ROLE      ONT_DEMO_BUILDER_ROLE;
USE DATABASE  ONT_DEMO;
USE SCHEMA    SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

-- ---------------------------------------------------------------------------
-- 1. rag_feedback — the only "AI ops" table the demo needs
-- ---------------------------------------------------------------------------
-- Append-only. Hybrid Table would be ideal for the hot insert pattern at
-- scale; standard table is fine for the demo.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS rag_feedback (
    feedback_id      STRING       PRIMARY KEY,
    asked_at         TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    user_name        STRING       NOT NULL DEFAULT CURRENT_USER(),
    role_name        STRING       NOT NULL DEFAULT CURRENT_ROLE(),
    question         STRING       NOT NULL,
    model            STRING,
    answer           STRING,
    citations        ARRAY,            -- [node_uid, …] returned by p_graph_rag
    subgraph         VARIANT,          -- full nodes+edges payload
    latency_ms       INTEGER,
    guarded          BOOLEAN  DEFAULT FALSE,
    guard_verdict    VARIANT,
    thumbs           STRING,           -- 'up' | 'down' | NULL
    thumbs_at        TIMESTAMP_TZ,
    thumbs_comment   STRING
)
CLUSTER BY (asked_at);

-- ---------------------------------------------------------------------------
-- 2. p_log_rag — Streamlit calls this once per answer
-- ---------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE p_log_rag(
    QUESTION       STRING,
    MODEL          STRING,
    ANSWER         STRING,
    CITATIONS      ARRAY,
    SUBGRAPH       VARIANT,
    LATENCY_MS     INTEGER,
    GUARDED        BOOLEAN,
    GUARD_VERDICT  VARIANT
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    fid STRING DEFAULT UUID_STRING();
BEGIN
    -- CURRENT_USER()/CURRENT_ROLE() can be NULL inside an owner's-rights
    -- procedure called from Streamlit-in-Snowflake; COALESCE so the
    -- NOT NULL columns always get a value.
    INSERT INTO rag_feedback
        (feedback_id, user_name, role_name, question, model, answer,
         citations, subgraph, latency_ms, guarded, guard_verdict)
    SELECT
        :fid,
        COALESCE(CURRENT_USER(), 'STREAMLIT_APP'),
        COALESCE(CURRENT_ROLE(), 'STREAMLIT_APP'),
        :QUESTION, :MODEL, :ANSWER, :CITATIONS, :SUBGRAPH,
        :LATENCY_MS, :GUARDED, :GUARD_VERDICT;
    RETURN :fid;
END;
$$;

CREATE OR REPLACE PROCEDURE p_log_thumbs(
    FEEDBACK_ID STRING,
    THUMBS      STRING,
    COMMENT     STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    UPDATE rag_feedback
       SET thumbs         = :THUMBS,
           thumbs_at      = CURRENT_TIMESTAMP(),
           thumbs_comment = :COMMENT
     WHERE feedback_id   = :FEEDBACK_ID;
    RETURN 'ok';
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. gold.v_rag_feedback_summary — PM/CDO/governance dashboard
-- ---------------------------------------------------------------------------

USE SCHEMA GOLD;

CREATE OR REPLACE VIEW v_rag_feedback_summary AS
SELECT
    DATE_TRUNC('day', asked_at)                                   AS day,
    model,
    COUNT(*)                                                      AS questions,
    AVG(latency_ms)                                               AS avg_latency_ms,
    SUM(IFF(thumbs = 'up',   1, 0))                               AS thumbs_up,
    SUM(IFF(thumbs = 'down', 1, 0))                               AS thumbs_down,
    SUM(IFF(guarded AND guard_verdict:label::STRING <> 'safe', 1, 0)) AS blocked_by_guard,
    SUM(ARRAY_SIZE(citations))                                    AS total_citations,
    SUM(IFF(citations IS NULL OR ARRAY_SIZE(citations) = 0, 1, 0)) AS uncited_answers
FROM SILVER.rag_feedback
GROUP BY 1, 2
ORDER BY 1 DESC, 2;

CREATE OR REPLACE VIEW v_rag_feedback_top_questions AS
SELECT
    question,
    COUNT(*) AS asked_n,
    SUM(IFF(thumbs = 'up',   1, 0)) AS up_n,
    SUM(IFF(thumbs = 'down', 1, 0)) AS down_n,
    AVG(latency_ms) AS avg_latency_ms
FROM SILVER.rag_feedback
GROUP BY question
ORDER BY asked_n DESC
LIMIT 50;

-- ---------------------------------------------------------------------------
-- 4. v_rag_feedback_for_finetune — JSONL-shaped training set
-- ---------------------------------------------------------------------------
-- One row per accepted answer; the SQL formatter can write this straight
-- out to an internal stage as JSONL with COPY INTO @stage FROM (...).
-- Citations are folded into the prompt so the fine-tune learns to ground.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_rag_feedback_for_finetune AS
SELECT
    feedback_id,
    OBJECT_CONSTRUCT(
        'prompt',
            '# QUESTION' || CHR(10) || question || CHR(10) ||
            '# GRAPH CONTEXT' || CHR(10) ||
            COALESCE(
                (SELECT LISTAGG('- [' || value:node_uid::STRING || '] '
                                 || value:label::STRING || ' ('
                                 || value:class_iri::STRING || ')',
                                '\n')
                       WITHIN GROUP (ORDER BY value:depth::INTEGER)
                   FROM TABLE(FLATTEN(input => subgraph:nodes))),
                ''),
        'completion', answer
    ) AS training_example
FROM SILVER.rag_feedback
WHERE thumbs = 'up'
  AND answer IS NOT NULL
  AND ARRAY_SIZE(citations) > 0;

-- ---------------------------------------------------------------------------
-- 5. Scheduled fine-tune (production opt-in)
-- ---------------------------------------------------------------------------
-- Cortex Fine-Tuning currently supports llama3-8b, mistral-7b and a few
-- others. The task below is COMMENTED OUT so the demo doesn't kick off
-- unexpected billable jobs. Uncomment in a non-demo environment.
-- ---------------------------------------------------------------------------

-- CREATE OR REPLACE TASK SILVER.t_rag_finetune_weekly
--     WAREHOUSE = ONT_DEMO_AGENT_WH
--     SCHEDULE  = 'USING CRON 0 6 * * 1 America/Chicago'   -- Mondays 06:00 CT
-- AS
-- BEGIN
--     -- 1. Dump accepted examples to a stage.
--     COPY INTO @ONT_DEMO.CONFIG.CORTEX_ANALYST_MODELS/finetune/training.jsonl
--          FROM (SELECT TO_JSON(training_example)
--                  FROM GOLD.v_rag_feedback_for_finetune)
--          FILE_FORMAT = (TYPE = JSON COMPRESSION = NONE)
--          SINGLE = TRUE OVERWRITE = TRUE;
--
--     -- 2. Kick off Cortex Fine-Tune (Snowflake ML).
--     SELECT SNOWFLAKE.CORTEX.FINETUNE(
--         'CREATE',
--         'ONT_DEMO.SILVER.LLAMA3_8B_ONTGUIDE_V1',     -- target model name
--         'llama3-8b',                                  -- base model
--         'SELECT training_example AS row_data
--            FROM GOLD.v_rag_feedback_for_finetune',
--         OBJECT_CONSTRUCT('warehouse', 'ONT_DEMO_AGENT_WH')
--     );
-- END;
--
-- ALTER TASK SILVER.t_rag_finetune_weekly RESUME;

SELECT 'rag_feedback + p_log_rag + summary views created.' AS status;
