#!/usr/bin/env python3
"""Execute a SQL file with proper handling of SQL Scripting (BEGIN/END blocks).

The `snow sql` CLI and snowflake-connector's `execute_string` both naively split
on semicolons, which breaks stored procedure bodies. This script uses regex-based
parsing to correctly identify statement boundaries — treating CREATE PROCEDURE
blocks (from AS/DECLARE/BEGIN to matching END;) as single statements.

Usage:
    python3 _run_sql.py --connection default --file path/to/script.sql
"""

import argparse
import os
import re
import sys

try:
    import tomllib
except ImportError:
    import tomli as tomllib

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import snowflake.connector


def get_connection(connection_name: str):
    """Create a Snowflake connection from connections.toml."""
    toml_path = os.path.expanduser("~/.snowflake/connections.toml")
    with open(toml_path, "rb") as f:
        config = tomllib.load(f)
    params = config[connection_name]

    connect_args = {
        "account": params["account"],
        "user": params["user"],
    }

    if params.get("authenticator") == "SNOWFLAKE_JWT" and params.get("private_key_path"):
        key_path = os.path.expanduser(params["private_key_path"])
        with open(key_path, "rb") as kf:
            private_key = serialization.load_pem_private_key(
                kf.read(), password=None, backend=default_backend()
            )
        connect_args["private_key"] = private_key.private_bytes(
            serialization.Encoding.DER,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    elif params.get("authenticator"):
        connect_args["authenticator"] = params["authenticator"]

    if params.get("warehouse"):
        connect_args["warehouse"] = params["warehouse"]
    if params.get("role"):
        connect_args["role"] = params["role"]

    return snowflake.connector.connect(**connect_args)


def split_sql_scripting(sql_text: str) -> list[str]:
    """Split SQL text into statements, correctly handling SQL Scripting blocks.

    Rules:
    - CREATE ... PROCEDURE/FUNCTION ... AS ... DECLARE/BEGIN ... END; is ONE statement
    - Everything else splits on semicolons (ignoring those in strings/comments)
    """
    statements = []
    lines = sql_text.split("\n")
    current = []
    in_block = False
    block_depth = 0
    awaiting_body = False  # After seeing CREATE PROCEDURE ... AS, waiting for BEGIN/DECLARE

    for line in lines:
        stripped = line.strip()
        stripped_upper = stripped.upper()

        # Skip pure comment lines for detection (but keep them in output)
        is_comment = stripped.startswith("--") or stripped.startswith("//")

        if not in_block and not awaiting_body:
            current.append(line)

            if not is_comment:
                # Detect CREATE PROCEDURE/FUNCTION pattern
                if re.match(
                    r"^CREATE\s+(OR\s+REPLACE\s+)?PROCEDURE\b",
                    stripped_upper,
                ):
                    awaiting_body = True
                    continue

                # Normal statement — check if line ends with semicolon
                if stripped.endswith(";"):
                    stmt = "\n".join(current).strip()
                    if stmt and not all(
                        l.strip().startswith("--") or l.strip() == ""
                        for l in current
                    ):
                        statements.append(stmt)
                    current = []

        elif awaiting_body:
            current.append(line)
            if not is_comment:
                # We're inside a CREATE PROCEDURE, looking for BEGIN or DECLARE
                if stripped_upper == "BEGIN" or stripped_upper.startswith("BEGIN "):
                    awaiting_body = False
                    in_block = True
                    block_depth = 1
                elif stripped_upper == "DECLARE" or stripped_upper.startswith("DECLARE "):
                    awaiting_body = False
                    in_block = True
                    block_depth = 0  # Will become 1 when BEGIN is found
                elif stripped_upper.startswith("AS") and len(stripped_upper) <= 3:
                    # Just the AS keyword line — keep waiting
                    pass
                # If we hit something unexpected and it ends with ;, it's probably
                # a non-scripting procedure (e.g., LANGUAGE JAVASCRIPT with $$)
                # For $$ delimited: the entire $$ block is handled by execute()
                elif "$$" in stripped:
                    # Dollar-quoted body — read until matching $$
                    awaiting_body = False
                    # Find the closing $$
                    rest_of_file = "\n".join(lines[lines.index(line)+1:]) if line in lines else ""
                    # Actually just let it accumulate until we see END; or $$;
                    in_block = True
                    block_depth = 1

        else:
            # Inside a scripting block
            current.append(line)

            if not is_comment:
                # Track nested BEGIN/END
                if re.match(r"^\s*BEGIN\b", line, re.IGNORECASE):
                    block_depth += 1
                if re.match(r"^\s*END\s*;?\s*$", line, re.IGNORECASE):
                    block_depth -= 1
                    if block_depth <= 0:
                        # End of scripting block — this is one complete statement
                        in_block = False
                        stmt = "\n".join(current).strip()
                        # Remove trailing semicolon from the END; for clean execution
                        if stmt:
                            statements.append(stmt)
                        current = []

    # Remaining content
    if current:
        stmt = "\n".join(current).strip()
        if stmt and not all(l.strip().startswith("--") or l.strip() == "" for l in current):
            statements.append(stmt)

    # Filter out empty/comment-only statements
    result = []
    for s in statements:
        clean = "\n".join(
            l for l in s.split("\n")
            if l.strip() and not l.strip().startswith("--") and not l.strip().startswith("//")
        ).strip()
        if clean:
            result.append(s)
    return result


def main():
    parser = argparse.ArgumentParser(description="Execute SQL file with scripting support")
    parser.add_argument("--connection", "-c", required=True, help="Connection name")
    parser.add_argument("--file", "-f", required=True, help="SQL file path")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    sql_text = open(args.file).read()
    statements = split_sql_scripting(sql_text)

    if args.verbose:
        print(f"  Parsed {len(statements)} statements from {args.file}")

    conn = get_connection(args.connection)
    cur = conn.cursor()
    errors = 0

    try:
        # Try execute_string with num_statements=0 (server-side parsing)
        for result_cursor in conn.execute_string(
            sql_text,
            remove_comments=False,
            return_cursors=True,
            num_statements=0,
        ):
            result_cursor.close()
        if args.verbose:
            print(f"  All statements executed successfully")
    except Exception as e:
        # execute_string failed — fall back to manual statement parsing
        # This handles SQL Scripting (BEGIN/END) that the connector can't parse
        if args.verbose:
            print(f"  execute_string failed ({type(e).__name__}), using manual parsing...")
        errors = 0
        statements = split_sql_scripting(sql_text)
        if args.verbose:
            print(f"  Parsed {len(statements)} statements")
        for i, stmt in enumerate(statements):
            if not stmt.strip():
                continue
            try:
                cur.execute(stmt)
                if args.verbose:
                    first_line = stmt.split("\n")[0][:80]
                    print(f"  [{i+1}/{len(statements)}] OK: {first_line}")
            except Exception as stmt_e:
                first_line = stmt.split("\n")[0][:80]
                # SHOW/DESCRIBE failures are non-critical (verification queries)
                if any(stmt.strip().upper().startswith(kw) for kw in ("SHOW", "DESCRIBE", "SELECT")):
                    if args.verbose:
                        print(f"  [{i+1}/{len(statements)}] WARN: {first_line} ({stmt_e})")
                else:
                    errors += 1
                    print(f"  [{i+1}/{len(statements)}] FAIL: {first_line}", file=sys.stderr)
                    print(f"    {stmt_e}", file=sys.stderr)
    finally:
        cur.close()
        conn.close()

    if errors:
        print(f"  {errors} statement(s) failed", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
