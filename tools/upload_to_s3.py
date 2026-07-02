#!/usr/bin/env python3
"""
S3 Upload Tool for DCA Raw Layer Demo

Uploads generated data files from the local data/ directory to the S3 bucket
that backs the Snowflake external stage. Preserves the directory structure so
Snowflake external table LOCATION paths match exactly.

S3 layout mirroring local data/:
    s3://<bucket>/sap_s4hana/          ← Parquet  (SAP S/4HANA)
    s3://<bucket>/salesforce/          ← CSV      (Salesforce)
    s3://<bucket>/oracle_ebs/          ← CSV      (Oracle EBS)
    s3://<bucket>/fhir_r4/             ← XML      (FHIR R4)
    s3://<bucket>/workday/             ← JSON     (Workday)
    s3://<bucket>/servicenow/          ← CSV      (ServiceNow core)
    s3://<bucket>/dcim/servicenow/     ← CSV      (DCIM ServiceNow)
    s3://<bucket>/dcim/siemens_dcim/   ← XML      (DCIM Siemens)
    s3://<bucket>/dcim/telemetry/      ← Parquet  (DCIM Telemetry)
    s3://<bucket>/dcim/workday_dcim/   ← JSON     (DCIM Workday)

Usage:
    python upload_to_s3.py --bucket dca-raw-demo-123456789 --data-dir ../data
    python upload_to_s3.py --bucket dca-raw-demo-123456789 --data-dir ../data --aws-profile my-profile
    python upload_to_s3.py --bucket dca-raw-demo-123456789 --data-dir ../data --system sap_s4hana
    python upload_to_s3.py --bucket dca-raw-demo-123456789 --data-dir ../data --dry-run
"""

import os
import sys
import argparse
import mimetypes
from pathlib import Path

try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError
except ImportError:
    print("ERROR: boto3 not installed. Run: pip install boto3")
    sys.exit(1)

# ---------------------------------------------------------------------------
# S3 prefix mapping: local folder name → S3 prefix
# DCIM sub-generators land in dcim/<subfolder>/ in S3
# ---------------------------------------------------------------------------
DCIM_SYSTEMS = {'servicenow', 'siemens_dcim', 'telemetry', 'workday_dcim'}

CONTENT_TYPE_MAP = {
    '.parquet': 'application/octet-stream',
    '.csv':     'text/csv',
    '.json':    'application/json',
    '.xml':     'application/xml',
}


def s3_prefix_for(local_folder: str) -> str:
    """
    Return the S3 key prefix for a given local folder name.
    DCIM sub-system folders are nested under dcim/.
    """
    folder = local_folder.rstrip('/')
    if folder in DCIM_SYSTEMS:
        return f"dcim/{folder}/"
    return f"{folder}/"


def upload_directory(s3_client, bucket: str, local_dir: Path, s3_prefix: str,
                     dry_run: bool = False) -> tuple[int, int, int]:
    """
    Upload all files in local_dir to s3://bucket/s3_prefix.
    Returns (uploaded, skipped, failed) counts.
    """
    uploaded = skipped = failed = 0

    files = sorted(local_dir.rglob('*'))
    data_files = [f for f in files if f.is_file()]

    if not data_files:
        print(f"  [SKIP] No files found in {local_dir}")
        return 0, 0, 0

    for file_path in data_files:
        rel = file_path.relative_to(local_dir)
        s3_key = s3_prefix + str(rel).replace(os.sep, '/')
        ext = file_path.suffix.lower()
        content_type = CONTENT_TYPE_MAP.get(ext, 'application/octet-stream')

        if dry_run:
            print(f"  [DRY-RUN] {file_path} → s3://{bucket}/{s3_key}")
            uploaded += 1
            continue

        try:
            s3_client.upload_file(
                str(file_path),
                bucket,
                s3_key,
                ExtraArgs={'ContentType': content_type},
            )
            size_kb = file_path.stat().st_size / 1024
            print(f"  ✓ {file_path.name} → s3://{bucket}/{s3_key} ({size_kb:.1f} KB)")
            uploaded += 1
        except ClientError as exc:
            print(f"  ✗ FAILED {file_path.name}: {exc}")
            failed += 1
        except FileNotFoundError:
            print(f"  ✗ MISSING {file_path}")
            skipped += 1

    return uploaded, skipped, failed


def main():
    parser = argparse.ArgumentParser(
        description="Upload DCA demo data files to S3 for Snowflake external tables",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Upload all generated data
  python upload_to_s3.py --bucket dca-raw-demo-123456789 --data-dir ../data

  # Upload only SAP data (Parquet)
  python upload_to_s3.py --bucket dca-raw-demo-123456789 --data-dir ../data --system sap_s4hana

  # Preview without uploading
  python upload_to_s3.py --bucket dca-raw-demo-123456789 --data-dir ../data --dry-run

  # Use a named AWS profile
  python upload_to_s3.py --bucket dca-raw-demo-123456789 --data-dir ../data --aws-profile prod
        """,
    )
    parser.add_argument('--bucket', required=True,
                        help='S3 bucket name (from Terraform output: s3_bucket_name)')
    parser.add_argument('--data-dir', default='../data',
                        help='Local data directory produced by data_generator.py (default: ../data)')
    parser.add_argument('--aws-profile', default=None,
                        help='AWS named profile (default: uses default credential chain)')
    parser.add_argument('--aws-region', default=None,
                        help='AWS region (default: inferred from profile / environment)')
    parser.add_argument('--system', default=None,
                        help='Upload only a specific system folder (e.g. sap_s4hana, fhir_r4)')
    parser.add_argument('--dry-run', action='store_true',
                        help='Print what would be uploaded without actually uploading')
    args = parser.parse_args()

    data_root = Path(args.data_dir).resolve()
    if not data_root.exists():
        print(f"ERROR: data directory not found: {data_root}")
        print("Run the data generators first: python data_generator.py --system <name> ...")
        sys.exit(1)

    # Build S3 client
    session_kwargs: dict = {}
    if args.aws_profile:
        session_kwargs['profile_name'] = args.aws_profile
    if args.aws_region:
        session_kwargs['region_name'] = args.aws_region

    try:
        session = boto3.Session(**session_kwargs)
        s3 = session.client('s3')
        # Validate credentials early
        s3.head_bucket(Bucket=args.bucket)
    except NoCredentialsError:
        print("ERROR: AWS credentials not found. Configure via:")
        print("  aws configure  (or set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars)")
        sys.exit(1)
    except ClientError as exc:
        code = exc.response['Error']['Code']
        if code in ('404', 'NoSuchBucket'):
            print(f"ERROR: Bucket '{args.bucket}' not found. Run: terraform apply")
        elif code == '403':
            print(f"ERROR: Access denied to bucket '{args.bucket}'. Check IAM permissions.")
        else:
            print(f"ERROR accessing bucket: {exc}")
        sys.exit(1)

    # Discover system folders to upload
    if args.system:
        folders = [args.system]
    else:
        folders = sorted(
            d.name for d in data_root.iterdir()
            if d.is_dir() and not d.name.startswith('.')
        )

    if not folders:
        print(f"No data folders found under {data_root}. Generate data first.")
        sys.exit(1)

    print("=" * 65)
    print(f"DCA S3 UPLOAD  {'(DRY RUN) ' if args.dry_run else ''}")
    print(f"Bucket  : s3://{args.bucket}/")
    print(f"Source  : {data_root}")
    print(f"Systems : {', '.join(folders)}")
    print("=" * 65)

    total_uploaded = total_skipped = total_failed = 0

    for folder in folders:
        local_dir = data_root / folder
        if not local_dir.is_dir():
            print(f"\n[WARN] Folder not found, skipping: {local_dir}")
            continue

        prefix = s3_prefix_for(folder)
        print(f"\n→ {folder}/ → s3://{args.bucket}/{prefix}")

        u, s, f = upload_directory(s3, args.bucket, local_dir, prefix, dry_run=args.dry_run)
        total_uploaded += u
        total_skipped += s
        total_failed += f

    print()
    print("=" * 65)
    print(f"UPLOAD COMPLETE")
    print(f"  Uploaded : {total_uploaded}")
    print(f"  Skipped  : {total_skipped}")
    print(f"  Failed   : {total_failed}")
    print("=" * 65)

    if total_failed:
        sys.exit(1)

    if not args.dry_run:
        print()
        print("Next steps:")
        print("  1. Run sql/03b_s3_external_raw_layer.sql in Snowflake")
        print("  2. DESCRIBE INTEGRATION S3_RAW_INTEGRATION;")
        print("  3. Update terraform/variables.tf with snowflake_external_id + aws_account_id")
        print("  4. terraform apply  (lock trust policy)")
        print("  5. ALTER EXTERNAL TABLE ... REFRESH; for each table")


if __name__ == '__main__':
    main()
