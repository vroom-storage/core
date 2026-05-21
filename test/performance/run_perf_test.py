#!/usr/bin/env python3
"""Storage performance benchmark — before/after comparison tool.

Usage:
    run_perf_test.py [--url URL] [--corpus PATH] [--save FILE] [--compare FILE] [--warn-pct N]

Workflow:
    # Capture baseline
    runtime/cluster.sh start --bin-dir build/bin
    python test/performance/run_perf_test.py --save baseline.json
    runtime/cluster.sh stop

    # After your change, rebuild, then:
    runtime/cluster.sh start --bin-dir build/bin
    python test/performance/run_perf_test.py --compare baseline.json
    runtime/cluster.sh stop
"""

import argparse
import json
import os
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import boto3
from botocore.config import Config

ACCESS_KEY = "0555b35654ad1656d804"
SECRET_KEY = "h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q=="
REGION = "us-east-1"
DEFAULT_URL = "http://localhost:8080"

# Synthetic corpus: (label, size_bytes, iterations)
SYNTHETIC_SIZES = [("64k", 64 << 10, 50), ("4m", 4 << 20, 20)]
THROUGHPUT_SIZE = 128 << 20

COL = 34  # width of metric name column
SEP = "─" * (COL + 34)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def label_for_size(n):
    if n < 256 << 10:
        return "64k"
    if n <= 16 << 20:
        return "4m"
    return "128m"


def percentile(data, p):
    s = sorted(data)
    k = (len(s) - 1) * p / 100
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def pstats(data):
    return {
        "p50": percentile(data, 50),
        "p95": percentile(data, 95),
        "p99": percentile(data, 99),
        "n": len(data),
    }


def put_timed(client, bucket, key, data):
    t = time.perf_counter()
    client.put_object(Bucket=bucket, Key=key, Body=data)
    return (time.perf_counter() - t) * 1000


def get_timed(client, bucket, key):
    t = time.perf_counter()
    client.get_object(Bucket=bucket, Key=key)["Body"].read()
    return (time.perf_counter() - t) * 1000


def mbps(size_bytes, total_ms):
    return (size_bytes / (1 << 20)) / (total_ms / 1000)


# ---------------------------------------------------------------------------
# Benchmark runs
# ---------------------------------------------------------------------------

def run_synthetic(client, bucket):
    write_lat, read_lat = {}, {}

    for label, size, n in SYNTHETIC_SIZES:
        data = os.urandom(size)
        keys = [f"perf/{label}/{i}" for i in range(n)]
        print(f"  {label}: {n} writes", end="", flush=True)
        wlats = [put_timed(client, bucket, k, data) for k in keys]
        print(f", {n} reads", end="", flush=True)
        rlats = [get_timed(client, bucket, k) for k in keys]
        print(" ✓")
        write_lat[label] = pstats(wlats)
        read_lat[label] = pstats(rlats)

    data = os.urandom(THROUGHPUT_SIZE)
    key = "perf/128m/0"
    print("  128m: write", end="", flush=True)
    wms = put_timed(client, bucket, key, data)
    print(", read", end="", flush=True)
    rms = get_timed(client, bucket, key)
    print(" ✓")

    return write_lat, read_lat, {"128m": mbps(THROUGHPUT_SIZE, wms)}, {"128m": mbps(THROUGHPUT_SIZE, rms)}


def run_corpus(client, bucket, corpus_path):
    all_files = sorted(Path(corpus_path).rglob("*"))
    all_files = [f for f in all_files if f.is_file()]
    if not all_files:
        sys.exit(f"error: no files found in {corpus_path}")

    groups = {"64k": [], "4m": [], "128m": []}
    for f in all_files:
        groups[label_for_size(f.stat().st_size)].append(f)

    write_lat, read_lat, write_tp, read_tp = {}, {}, {}, {}

    for label, file_list in groups.items():
        if not file_list:
            continue
        n = len(file_list)

        print(f"  {label}: {n} writes", end="", flush=True)
        wlats, keys = [], []
        for f in file_list:
            key = f"perf/{f.relative_to(corpus_path)}"
            keys.append(key)
            wlats.append(put_timed(client, bucket, key, f.read_bytes()))

        print(f", {n} reads", end="", flush=True)
        rlats = [get_timed(client, bucket, k) for k in keys]
        print(" ✓")

        write_lat[label] = pstats(wlats)
        read_lat[label] = pstats(rlats)
        if label == "128m":
            total = sum(f.stat().st_size for f in file_list)
            write_tp["128m"] = mbps(total, sum(wlats))
            read_tp["128m"] = mbps(total, sum(rlats))

    return write_lat, read_lat, write_tp, read_tp


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def _metric_rows(wlat, rlat, wtp, rtp):
    """Ordered list of (name, value, higher_is_better, is_throughput)."""
    rows = []
    for op, lat in (("write", wlat), ("read ", rlat)):
        for label in ("64k", "4m"):
            if label not in lat:
                continue
            for stat in ("p50", "p95", "p99"):
                rows.append((
                    f"{op} {stat.upper()}  {label.upper():<4} (ms)",
                    lat[label][stat], False, False,
                ))
    for op, tp in (("write", wtp), ("read ", rtp)):
        if "128m" in tp:
            rows.append((f"{op}      128M  (MB/s)", tp["128m"], True, True))
    return rows


def _corpus_header(corpus_info):
    if corpus_info["type"] == "files":
        mib = corpus_info["total_bytes"] >> 20
        print(f"corpus: {corpus_info['path']}  ({corpus_info['file_count']} files, {mib} MiB)")
    else:
        print("corpus: synthetic")


def print_results(url, corpus_info, wlat, rlat, wtp, rtp):
    print(f"\nBenchmark results  ({url})")
    _corpus_header(corpus_info)
    print(SEP)
    print(f"{'metric':<{COL}} {'value':>10}")
    print(SEP)
    for name, val, _, is_tp in _metric_rows(wlat, rlat, wtp, rtp):
        fmt = f"{val:10.1f}" if is_tp else f"{val:10.2f}"
        print(f"{name:<{COL}} {fmt}")
    print(SEP)


def print_comparison(baseline_path, corpus_info, wlat, rlat, wtp, rtp,
                     b_wlat, b_rlat, b_wtp, b_rtp, warn_pct):
    print(f"\nBenchmark comparison  {baseline_path} → current run")
    _corpus_header(corpus_info)
    print(SEP)
    print(f"{'metric':<{COL}} {'baseline':>10} {'current':>10} {'delta':>9}")
    print(SEP)

    baseline_vals = {n: v for n, v, _, _ in _metric_rows(b_wlat, b_rlat, b_wtp, b_rtp)}
    warned = False

    for name, val, higher, is_tp in _metric_rows(wlat, rlat, wtp, rtp):
        b_val = baseline_vals.get(name)
        if b_val is None:
            continue
        delta = (val - b_val) / b_val * 100 if b_val != 0 else 0.0
        flag = ""
        if (higher and delta < -warn_pct) or (not higher and delta > warn_pct):
            flag = " ⚠"
            warned = True
        sign = "+" if delta >= 0 else ""
        bfmt = f"{b_val:10.1f}" if is_tp else f"{b_val:10.2f}"
        cfmt = f"{val:10.1f}" if is_tp else f"{val:10.2f}"
        print(f"{name:<{COL}} {bfmt} {cfmt} {sign}{delta:7.0f}%{flag}")

    print(SEP)
    if warned:
        print(f"⚠  delta exceeds {warn_pct}%")


# ---------------------------------------------------------------------------
# Corpus metadata
# ---------------------------------------------------------------------------

def build_corpus_info(corpus_arg):
    if not corpus_arg:
        return {"type": "synthetic"}
    p = Path(corpus_arg).resolve()
    if not p.is_dir():
        sys.exit(f"error: corpus path is not a directory: {p}")
    files = [f for f in sorted(p.rglob("*")) if f.is_file()]
    return {
        "type": "files",
        "path": str(p),
        "file_count": len(files),
        "total_bytes": sum(f.stat().st_size for f in files),
    }


def check_corpus_compat(current, baseline, baseline_path):
    if current["type"] != baseline["type"]:
        sys.exit(
            f"error: corpus type mismatch — baseline uses '{baseline['type']}' "
            f"but current run uses '{current['type']}'"
        )
    if current["type"] == "files" and (
        current["file_count"] != baseline["file_count"]
        or current["total_bytes"] != baseline["total_bytes"]
    ):
        print(
            f"warning: corpus changed since {baseline_path} "
            f"(was {baseline['file_count']} files / {baseline['total_bytes']} B, "
            f"now {current['file_count']} files / {current['total_bytes']} B)",
            file=sys.stderr,
        )


# ---------------------------------------------------------------------------
# Bucket lifecycle
# ---------------------------------------------------------------------------

def delete_bucket(client, bucket):
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket):
        if "Contents" not in page:
            continue
        client.delete_objects(
            Bucket=bucket,
            Delete={"Objects": [{"Key": o["Key"]} for o in page["Contents"]]},
        )
    client.delete_bucket(Bucket=bucket)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Storage performance benchmark")
    parser.add_argument("--url", default=DEFAULT_URL, metavar="URL",
                        help=f"S3 endpoint URL (default: {DEFAULT_URL})")
    parser.add_argument("--corpus", metavar="PATH",
                        help="directory of files to use as test objects; "
                             "omit to use synthetic random data")
    parser.add_argument("--save", metavar="FILE",
                        help="save results to FILE as JSON")
    parser.add_argument("--compare", metavar="FILE",
                        help="compare current run against baseline FILE")
    parser.add_argument("--warn-pct", type=float, default=10.0, metavar="N",
                        help="mark deltas exceeding N%% with ⚠ (default: 10)")
    args = parser.parse_args()

    corpus_info = build_corpus_info(args.corpus)

    baseline = None
    if args.compare:
        with open(args.compare) as f:
            baseline = json.load(f)
        check_corpus_compat(corpus_info, baseline["corpus"], args.compare)

    client = boto3.client(
        "s3",
        endpoint_url=args.url,
        aws_access_key_id=ACCESS_KEY,
        aws_secret_access_key=SECRET_KEY,
        region_name=REGION,
        config=Config(signature_version="s3v4"),
    )

    bucket = f"perf-test-{uuid.uuid4().hex[:8]}"
    client.create_bucket(Bucket=bucket)
    print(f"Running benchmark against {args.url} (bucket: {bucket})")

    try:
        if args.corpus:
            wlat, rlat, wtp, rtp = run_corpus(client, bucket, args.corpus)
        else:
            wlat, rlat, wtp, rtp = run_synthetic(client, bucket)
    finally:
        delete_bucket(client, bucket)

    result = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "url": args.url,
        "corpus": corpus_info,
        "write_latency_ms": wlat,
        "read_latency_ms": rlat,
        "write_throughput_mbps": wtp,
        "read_throughput_mbps": rtp,
    }

    print_results(args.url, corpus_info, wlat, rlat, wtp, rtp)

    if args.save:
        with open(args.save, "w") as f:
            json.dump(result, f, indent=2)
        print(f"Saved to {args.save}")

    if baseline:
        print_comparison(
            args.compare, corpus_info,
            wlat, rlat, wtp, rtp,
            baseline["write_latency_ms"], baseline["read_latency_ms"],
            baseline["write_throughput_mbps"], baseline["read_throughput_mbps"],
            args.warn_pct,
        )


if __name__ == "__main__":
    main()
