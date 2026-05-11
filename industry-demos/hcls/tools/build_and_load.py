#!/usr/bin/env python3
"""
HCLS Data Build & Load Orchestrator

Generates all three HCLS datasets (FHIR, Workday HCM, Payer) and loads
them into a Snowflake account via PUT + LOAD_SOURCE_SYSTEM().

Usage:
    # Full pipeline: generate + upload + load
    python build_and_load.py --connection default

    # Quick mode (10% data)
    python build_and_load.py --connection default --quick

    # Generate only (no Snowflake connection needed)
    python build_and_load.py --generate-only

    # Load only (assumes CSVs already exist in --data-dir)
    python build_and_load.py --connection default --load-only

    # Custom scale
    python build_and_load.py --connection default --scale 2.0

    # Specify output directory
    python build_and_load.py --connection default --data-dir ./my_data
"""

import os
import sys
import glob
import time
import argparse
from pathlib import Path

# ---------------------------------------------------------------------------
# Resolve paths so sibling generators and the core data_generator are importable
# ---------------------------------------------------------------------------
TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
HCLS_ROOT = os.path.dirname(TOOLS_DIR)
REPO_ROOT = os.path.dirname(os.path.dirname(HCLS_ROOT))

# Core tools (for SourceSystemGenerator / save_to_csv)
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))
# HCLS generators live alongside this script
sys.path.insert(0, TOOLS_DIR)

# Generator imports (deferred to functions so --help works without faker)
from generate_hcls_data import (
    HCLSGenerator,
    save_to_csv as save_fhir_csv,
    DEFAULT_COUNTS as FHIR_COUNTS,
)
from generate_workday_hcm_data import (
    WorkdayHCMGenerator,
    save_to_csv as save_workday_csv,
    DEFAULT_COUNTS as WORKDAY_COUNTS,
)
from generate_payer_data import (
    PayerGenerator,
    save_to_csv as save_payer_csv,
    DEFAULT_COUNTS as PAYER_COUNTS,
)


# ---------------------------------------------------------------------------
# HCLS source systems: schema, stage folder, generator
# ---------------------------------------------------------------------------
HCLS_SYSTEMS = [
    {
        "name": "FHIR",
        "folder": "fhir",
        "schema": "FHIR",
        "generator_cls": HCLSGenerator,
        "save_fn": save_fhir_csv,
        "default_counts": FHIR_COUNTS,
    },
    {
        "name": "Workday HCM",
        "folder": "workday_hcm",
        "schema": "WORKDAY_HCM",
        "generator_cls": WorkdayHCMGenerator,
        "save_fn": save_workday_csv,
        "default_counts": WORKDAY_COUNTS,
    },
    {
        "name": "Payer",
        "folder": "payer",
        "schema": "PAYER",
        "generator_cls": PayerGenerator,
        "save_fn": save_payer_csv,
        "default_counts": PAYER_COUNTS,
    },
]


# ============================================================================
# DATA GENERATION
# ============================================================================

def generate_all_datasets(args):
    """Run all three HCLS generators and write CSVs to --data-dir."""
    print()
    print("=" * 70)
    print("  PHASE 1: DATA GENERATION")
    print("=" * 70)

    total_records = 0
    t0 = time.time()

    for sys_cfg in HCLS_SYSTEMS:
        counts = dict(sys_cfg["default_counts"])
        if args.quick:
            counts = {k: max(10, v // 10) for k, v in counts.items()}
        else:
            counts = {k: int(v * args.scale) for k, v in counts.items()}

        print(f"\n── {sys_cfg['name']} ──")
        print(f"   Counts: {counts}")

        gen = sys_cfg["generator_cls"](seed=args.seed)
        data = gen.generate(counts)

        for table, records in data.items():
            n = len(records)
            total_records += n
            if args.verbose:
                print(f"   {table}: {n:,} records")

        sys_cfg["save_fn"](data, args.data_dir)

    elapsed = time.time() - t0
    print(f"\n  Generation complete — {total_records:,} total records in {elapsed:.1f}s")


# ============================================================================
# SNOWFLAKE CONNECTION
# ============================================================================

def connect_snowflake(args):
    """Return an open snowflake.connector connection."""
    try:
        import snowflake.connector
    except ImportError:
        print("ERROR: snowflake-connector-python not installed.")
        print("       pip install snowflake-connector-python")
        sys.exit(1)

    print()
    print("=" * 70)
    print("  CONNECTING TO SNOWFLAKE")
    print("=" * 70)

    if args.connection:
        print(f"  Using connection name: {args.connection}")
        conn = snowflake.connector.connect(connection_name=args.connection)
    else:
        print(f"  Account:   {args.account}")
        print(f"  User:      {args.user}")
        conn = snowflake.connector.connect(
            account=args.account,
            user=args.user,
            password=args.password,
        )

    cur = conn.cursor()
    cur.execute(f"USE ROLE {args.role}")
    cur.execute(f"USE WAREHOUSE {args.warehouse}")
    cur.execute("USE DATABASE RAW_DEV")

    cur.execute("SELECT CURRENT_ACCOUNT(), CURRENT_ROLE(), CURRENT_WAREHOUSE()")
    row = cur.fetchone()
    print(f"  Account:   {row[0]}")
    print(f"  Role:      {row[1]}")
    print(f"  Warehouse: {row[2]}")
    cur.close()

    return conn


# ============================================================================
# UPLOAD TO STAGE
# ============================================================================

def upload_to_stage(conn, args):
    """PUT all generated CSVs into @RAW_DEV.STAGING.DATA_STAGE/<folder>/."""
    print()
    print("=" * 70)
    print("  PHASE 2: UPLOAD TO STAGE")
    print("=" * 70)

    cur = conn.cursor()
    total_files = 0
    total_errors = 0
    t0 = time.time()

    for sys_cfg in HCLS_SYSTEMS:
        folder = sys_cfg["folder"]
        local_dir = os.path.join(args.data_dir, folder)

        if not os.path.isdir(local_dir):
            print(f"\n  WARNING: {local_dir} not found — skipping {sys_cfg['name']}")
            continue

        csv_files = sorted(glob.glob(os.path.join(local_dir, "*.csv")))
        if not csv_files:
            print(f"\n  WARNING: No CSV files in {local_dir} — skipping {sys_cfg['name']}")
            continue

        print(f"\n── {sys_cfg['name']} ({len(csv_files)} files) ──")

        for filepath in csv_files:
            filename = os.path.basename(filepath)
            stage_target = f"@RAW_DEV.STAGING.DATA_STAGE/{folder}/"
            put_sql = (
                f"PUT 'file://{filepath}' '{stage_target}' "
                f"AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
            )

            try:
                if args.verbose:
                    print(f"   PUT {filename} → {stage_target}")
                cur.execute(put_sql)
                total_files += 1
            except Exception as e:
                print(f"   ERROR uploading {filename}: {e}")
                total_errors += 1

    elapsed = time.time() - t0
    cur.close()
    print(f"\n  Upload complete — {total_files} files in {elapsed:.1f}s", end="")
    if total_errors:
        print(f" ({total_errors} errors)")
    else:
        print()

    return total_errors


# ============================================================================
# LOAD INTO TABLES
# ============================================================================

def load_into_tables(conn, args):
    """
    For each HCLS system: ensure schema exists, then call SP_LOAD_HCLS_DATA()
    or fall back to per-file INFER_SCHEMA + COPY INTO.
    """
    print()
    print("=" * 70)
    print("  PHASE 3: LOAD INTO TABLES")
    print("=" * 70)

    cur = conn.cursor()
    total_tables = 0
    total_rows = 0
    total_errors = 0
    t0 = time.time()

    # Ensure schemas exist
    for sys_cfg in HCLS_SYSTEMS:
        cur.execute(f"CREATE SCHEMA IF NOT EXISTS RAW_DEV.{sys_cfg['schema']}")

    # Try the SP_LOAD_HCLS_DATA procedure first (created by 10_hcls_load_data.sql)
    try:
        print("\n  Calling SP_LOAD_HCLS_DATA() ...")
        cur.execute("CALL RAW_DEV.STAGING.SP_LOAD_HCLS_DATA()")
        result_row = cur.fetchone()
        if result_row:
            import json
            result = json.loads(result_row[0]) if isinstance(result_row[0], str) else result_row[0]

            total_tables = result.get("total_tables", 0)
            total_rows = result.get("total_rows", 0)
            total_errors = result.get("total_failed", 0)

            for sys_result in result.get("systems", []):
                status = sys_result.get("status", "UNKNOWN")
                schema = sys_result.get("schema", "?")
                tables = sys_result.get("tables", 0)
                rows = sys_result.get("rows", 0)
                print(f"   {schema}: {status} — {tables} tables, {rows:,} rows")

                if args.verbose and "details" in sys_result:
                    for d in sys_result["details"]:
                        flag = "OK" if d.get("status") == "SUCCESS" else "FAIL"
                        print(f"      [{flag}] {d['table']}: {d.get('rows', 0):,} rows")

    except Exception as sp_err:
        # SP doesn't exist yet — fall back to direct INFER + COPY per file
        print(f"  SP_LOAD_HCLS_DATA not available ({sp_err}), using direct load ...")
        total_tables, total_rows, total_errors = _direct_load(conn, args)

    elapsed = time.time() - t0
    cur.close()
    print(f"\n  Load complete — {total_tables} tables, {total_rows:,} rows in {elapsed:.1f}s", end="")
    if total_errors:
        print(f" ({total_errors} errors)")
    else:
        print()

    return total_errors


def _direct_load(conn, args):
    """Fallback: per-file INFER_SCHEMA → CREATE TABLE → COPY INTO."""
    cur = conn.cursor()
    total_tables = 0
    total_rows = 0
    total_errors = 0

    infer_format = "RAW_DEV.STAGING.CSV_INFER_FORMAT"

    for sys_cfg in HCLS_SYSTEMS:
        schema_name = f"RAW_DEV.{sys_cfg['schema']}"
        folder = sys_cfg["folder"]

        print(f"\n── {sys_cfg['name']} (direct load) ──")

        # List files on stage
        try:
            cur.execute(f"LIST @RAW_DEV.STAGING.DATA_STAGE/{folder}/")
            rows = cur.fetchall()
        except Exception:
            print(f"   No files on stage for {folder}/")
            continue

        csv_files = []
        for row in rows:
            path = row[0].lower()
            if path.endswith(".csv") or path.endswith(".csv.gz"):
                csv_files.append(row[0])

        for listed_path in csv_files:
            parts = listed_path.split("/")
            filename = parts[-1]
            table_name = (
                filename.replace(".gz", "").replace(".csv", "").upper()
            )
            stage_path = f"@RAW_DEV.STAGING.DATA_STAGE/{folder}/{filename}"
            full_table = f"{schema_name}.{table_name}"

            try:
                # INFER_SCHEMA
                cur.execute(f"""
                    SELECT LISTAGG('"' || COLUMN_NAME || '" ' || TYPE, ', ')
                           WITHIN GROUP (ORDER BY ORDER_ID)
                    FROM TABLE(INFER_SCHEMA(
                        LOCATION => '{stage_path}',
                        FILE_FORMAT => '{infer_format}',
                        MAX_RECORDS_PER_FILE => 1000
                    ))
                """)
                col_defs = cur.fetchone()[0]
                if not col_defs or not col_defs.strip():
                    raise ValueError("No columns inferred")

                # CREATE TABLE
                cur.execute(
                    f"CREATE OR REPLACE TABLE {full_table} ({col_defs}) "
                    f"COMMENT = 'HCLS auto-loaded from {filename}'"
                )

                # COPY INTO
                cur.execute(
                    f"COPY INTO {full_table} FROM {stage_path} "
                    f"FILE_FORMAT = {infer_format} "
                    f"MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE "
                    f"ON_ERROR = CONTINUE FORCE = TRUE"
                )

                # Row count
                cur.execute(f"SELECT COUNT(*) FROM {full_table}")
                row_count = cur.fetchone()[0]

                total_tables += 1
                total_rows += row_count
                if args.verbose:
                    print(f"   [OK] {table_name}: {row_count:,} rows")

            except Exception as e:
                total_errors += 1
                print(f"   [FAIL] {table_name}: {e}")

    cur.close()
    return total_tables, total_rows, total_errors


# ============================================================================
# VERIFY
# ============================================================================

def verify_load(conn):
    """Print a summary of all loaded HCLS tables."""
    print()
    print("=" * 70)
    print("  VERIFICATION")
    print("=" * 70)

    cur = conn.cursor()
    cur.execute("""
        SELECT TABLE_SCHEMA, TABLE_NAME, ROW_COUNT
        FROM RAW_DEV.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_CATALOG = 'RAW_DEV'
          AND TABLE_SCHEMA IN ('FHIR', 'WORKDAY_HCM', 'PAYER')
          AND TABLE_TYPE = 'BASE TABLE'
        ORDER BY TABLE_SCHEMA, TABLE_NAME
    """)

    rows = cur.fetchall()
    cur.close()

    if not rows:
        print("  WARNING: No tables found in FHIR / WORKDAY_HCM / PAYER schemas.")
        return

    print(f"\n  {'SCHEMA':<14} {'TABLE':<30} {'ROWS':>12}")
    print(f"  {'─' * 14} {'─' * 30} {'─' * 12}")

    warnings = []
    for schema, table, row_count in rows:
        rc = row_count or 0
        flag = " ⚠" if rc == 0 else ""
        print(f"  {schema:<14} {table:<30} {rc:>12,}{flag}")
        if rc == 0:
            warnings.append(f"{schema}.{table}")

    total_tables = len(rows)
    total_rows = sum((r[2] or 0) for r in rows)
    print(f"\n  TOTAL: {total_tables} tables, {total_rows:,} rows")

    if warnings:
        print(f"\n  WARNING: {len(warnings)} table(s) have 0 rows:")
        for w in warnings:
            print(f"    - {w}")


# ============================================================================
# CLI
# ============================================================================

def parse_args():
    parser = argparse.ArgumentParser(
        description="HCLS Data Build & Load Orchestrator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python build_and_load.py --connection default
  python build_and_load.py --connection default --quick
  python build_and_load.py --generate-only
  python build_and_load.py --connection default --load-only
  python build_and_load.py --connection default --scale 2.0
        """,
    )

    # Snowflake connection
    sf = parser.add_argument_group("Snowflake connection")
    sf.add_argument(
        "--connection", "-c", default=None,
        help="Connection name from connections.toml (recommended)",
    )
    sf.add_argument("--account", default=None, help="Snowflake account identifier")
    sf.add_argument("--user", default=None, help="Snowflake username")
    sf.add_argument("--password", default=None, help="Snowflake password (or set SNOWFLAKE_PASSWORD)")
    sf.add_argument("--role", default="DATA_ADMIN", help="Snowflake role (default: DATA_ADMIN)")
    sf.add_argument("--warehouse", default="INGEST_WH", help="Warehouse (default: INGEST_WH)")

    # Data options
    data = parser.add_argument_group("Data generation")
    data.add_argument(
        "--data-dir", "-d", default=os.path.join(HCLS_ROOT, "data"),
        help="Directory for generated CSVs (default: industry-demos/hcls/data)",
    )
    data.add_argument("--quick", action="store_true", help="Generate ~10%% of default row counts")
    data.add_argument("--scale", type=float, default=1.0, help="Scale factor (default: 1.0)")
    data.add_argument("--seed", type=int, default=42, help="Random seed (default: 42)")

    # Mode
    mode = parser.add_argument_group("Execution mode")
    mode.add_argument("--generate-only", action="store_true", help="Generate CSVs only; skip Snowflake")
    mode.add_argument("--load-only", action="store_true", help="Skip generation; load existing CSVs")

    # Output
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")

    args = parser.parse_args()

    # Validation
    if not args.generate_only and not args.connection and not args.account:
        parser.error("Provide --connection or --account/--user/--password (or use --generate-only)")

    if args.password is None and args.account and not args.connection:
        args.password = os.environ.get("SNOWFLAKE_PASSWORD")
        if not args.password:
            import getpass
            args.password = getpass.getpass("Snowflake password: ")

    return args


# ============================================================================
# MAIN
# ============================================================================

def main():
    args = parse_args()
    t_start = time.time()
    errors = 0

    print()
    print("╔══════════════════════════════════════════════════════════════════════╗")
    print("║           HCLS DATA BUILD & LOAD ORCHESTRATOR                      ║")
    print("╚══════════════════════════════════════════════════════════════════════╝")
    print(f"  Mode:     {'generate-only' if args.generate_only else 'load-only' if args.load_only else 'full pipeline'}")
    print(f"  Scale:    {'quick (10%)' if args.quick else f'{args.scale}x'}")
    print(f"  Data dir: {args.data_dir}")
    print(f"  Seed:     {args.seed}")

    # Phase 1: Generate
    if not args.load_only:
        generate_all_datasets(args)

    # Phases 2-4: Snowflake operations
    if not args.generate_only:
        conn = connect_snowflake(args)
        try:
            upload_errors = upload_to_stage(conn, args)
            errors += upload_errors

            load_errors = load_into_tables(conn, args)
            errors += load_errors

            verify_load(conn)
        finally:
            conn.close()

    # Summary
    elapsed = time.time() - t_start
    print()
    print("=" * 70)
    print(f"  DONE — Total time: {elapsed:.1f}s")
    if errors:
        print(f"  ⚠ {errors} error(s) encountered. Check output above.")
    else:
        print("  All operations completed successfully.")
    print("=" * 70)

    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
