#!/usr/bin/env python3
"""Generate ontology-ready triple CSVs from the repo's main data generator.

This is the productionized replacement for the old, CPG-only
``synthetic_cpg/generate_cpg_data.py``. Instead of hand-rolling fake CPG data,
it drives the repository's canonical source-system generator
(``tools/data_generator.py`` at the repo root) for any of the six supported
systems and maps the result into the demo's triple-store load format via the
curated mapping specs under ``mappings/``.

Usage
-----
    # one system
    python tools/generate_ontology_data.py --system sap --domain all
    python tools/generate_ontology_data.py --system salesforce --quick

    # all six systems at once
    python tools/generate_ontology_data.py --system all

Output lands in ``data/<system>/{individuals,statements_object,statements_literal}.csv``
and is loaded by ``02b_load_source_ontology.sql``.
"""
from __future__ import annotations

import argparse
import importlib
import json
import sys
from pathlib import Path
from typing import Any, Dict

from ontology_adapter import MappingSpec, emit_triples

SUPPORTED = ["sap", "salesforce", "oracle", "fhir", "workday", "servicenow"]


def _find_repo_root(start: Path) -> Path:
    """Walk upward until we find the repo's main generator (tools/data_generator.py)."""
    for parent in [start, *start.parents]:
        if (parent / "tools" / "data_generator.py").exists():
            return parent
    raise FileNotFoundError(
        "Could not locate tools/data_generator.py by walking up from "
        f"{start}. Set DCA_REPO_ROOT or run from inside the repo."
    )


def _import_main_generator():
    here = Path(__file__).resolve()
    import os

    env_root = os.environ.get("DCA_REPO_ROOT")
    repo_root = Path(env_root) if env_root else _find_repo_root(here.parent)
    gen_dir = repo_root / "tools"
    if str(gen_dir) not in sys.path:
        sys.path.insert(0, str(gen_dir))
    return importlib.import_module("data_generator")


def _load_spec(system: str) -> MappingSpec:
    mod = importlib.import_module(f"mappings.{system}")
    spec = getattr(mod, "SPEC", None)
    if not isinstance(spec, MappingSpec):
        raise TypeError(f"mappings/{system}.py must define SPEC: MappingSpec")
    return spec


def _counts_for(dg, system: str, domain: str, quick: bool, scale: float) -> Dict[str, int]:
    domains = dg.SYSTEM_DOMAINS.get(system, {})
    counts = domains.get(domain, domains.get("all", {}))
    if not counts:
        raise SystemExit(
            f"Unknown domain '{domain}' for system '{system}'. "
            f"Available: {list(domains.keys())}"
        )
    if quick:
        return {k: max(10, v // 10) for k, v in counts.items()}
    return {k: int(v * scale) for k, v in counts.items()}


def run_system(dg, system: str, args) -> Dict[str, Any]:
    print("=" * 70)
    print(f"ONTOLOGY ADAPTER — {system.upper()}")
    print("=" * 70)

    spec = _load_spec(system)
    generator = dg.SYSTEM_GENERATORS[system](seed=args.seed)
    counts = _counts_for(dg, system, args.domain, args.quick, args.scale)
    print(f"Record counts: {counts}")

    data = generator.generate(counts)
    print("Generated tables: " + ", ".join(f"{t}={len(r):,}" for t, r in data.items()))

    # Key output directory by the namespace PREFIX (sap, sfdc, ora, fhir, wd,
    # snow) so it lines up with the TBox / semantic-model files and the SQL
    # `SYSTEM` variable used by 02b_load_source_ontology.sql.
    out_dir = Path(args.out) / spec.namespace_prefix
    manifest = emit_triples(spec, data, out_dir)
    c = manifest["counts"]
    print(
        f"-> {c['individuals']:,} individuals, "
        f"{c['statements_object']:,} object statements, "
        f"{c['statements_literal']:,} literal statements"
    )
    print(f"   CSVs written to {out_dir}/  (load with -D \"SYSTEM={spec.namespace_prefix}\")")
    manifest["prefix"] = spec.namespace_prefix
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--system", "-s", required=True, choices=[*SUPPORTED, "all"],
                    help="Source system to map into the ontology (or 'all').")
    ap.add_argument("--domain", "-d", default="all", help="Data domain (system-specific; default: all).")
    ap.add_argument("--out", "-o", default=str(Path(__file__).resolve().parent.parent / "data"),
                    help="Output base directory (default: demo/data).")
    ap.add_argument("--seed", type=int, default=42, help="Random seed for reproducibility.")
    ap.add_argument("--quick", action="store_true", help="Generate a small (1/10th) dataset.")
    ap.add_argument("--scale", type=float, default=1.0, help="Scale factor for record counts.")
    args = ap.parse_args()

    dg = _import_main_generator()

    systems = SUPPORTED if args.system == "all" else [args.system]
    manifests = [run_system(dg, s, args) for s in systems]

    summary_path = Path(args.out) / "manifest.json"
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(manifests, f, indent=2)
    print(f"\nManifest: {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
