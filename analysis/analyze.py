#!/usr/bin/env python3
"""
Analysis script for the Istio vs Resilience4j experiment.
Consolidates results, runs statistical tests, and generates plots.
"""

import json
import os
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
from scipy import stats

RESULTS_DIR = Path(__file__).parent.parent / "results"
OUTPUT_DIR = Path(__file__).parent / "output"
ALPHA = 0.05


def load_results() -> pd.DataFrame:
    """Load all k6 result JSON files into a consolidated DataFrame."""
    rows = []
    for results_json in RESULTS_DIR.rglob("results.json"):
        parts = results_json.parts
        # path: results/<timestamp>/<scenario>/<variant>/rep<N>/results.json
        try:
            idx = parts.index("results")
            timestamp = parts[idx + 1]
            scenario = parts[idx + 2]
            variant = parts[idx + 3]
            rep = parts[idx + 4]
        except (ValueError, IndexError):
            continue

        with open(results_json) as f:
            data = json.load(f)

        metrics = data.get("metrics", {})
        duration = metrics.get("http_req_duration", {}).get("values", {})
        reqs = metrics.get("http_reqs", {}).get("values", {})
        success = metrics.get("success_rate", {}).get("values", {})

        rows.append({
            "timestamp": timestamp,
            "scenario": scenario,
            "variant": variant,
            "rep": rep,
            "p50": duration.get("med"),
            "p90": duration.get("p(90)"),
            "p95": duration.get("p(95)"),
            "p99": duration.get("p(99)"),
            "max": duration.get("max"),
            "avg": duration.get("avg"),
            "total_requests": reqs.get("count"),
            "rps": reqs.get("rate"),
            "success_rate": success.get("rate"),
        })

    df = pd.DataFrame(rows)
    if df.empty:
        print("No results found. Run experiments first.")
        sys.exit(1)

    # Use only the latest timestamp per scenario/variant
    latest = df.groupby(["scenario", "variant"])["timestamp"].max().reset_index()
    df = df.merge(latest, on=["scenario", "variant", "timestamp"])

    return df


def cliffs_delta(x, y):
    """Compute Cliff's delta effect size."""
    n_x, n_y = len(x), len(y)
    if n_x == 0 or n_y == 0:
        return 0.0
    count = 0
    for xi in x:
        for yi in y:
            if xi > yi:
                count += 1
            elif xi < yi:
                count -= 1
    return count / (n_x * n_y)


def interpret_cliffs_delta(d):
    """Interpret Cliff's delta magnitude."""
    d = abs(d)
    if d < 0.147:
        return "negligible"
    elif d < 0.33:
        return "small"
    elif d < 0.474:
        return "medium"
    else:
        return "large"


def test_hypothesis_h1(df):
    """H1: Istio p95 > R4J p95 and Istio p95 > baseline p95 in S1."""
    print("\n=== H1: Performance overhead (S1) ===")
    s1 = df[df["scenario"] == "S1"]

    for pair in [("istio", "baseline"), ("istio", "r4j"), ("r4j", "baseline")]:
        a = s1[s1["variant"] == pair[0]]["p95"].dropna().values
        b = s1[s1["variant"] == pair[1]]["p95"].dropna().values

        if len(a) < 2 or len(b) < 2:
            print(f"  {pair[0]} vs {pair[1]}: insufficient data")
            continue

        stat, p = stats.mannwhitneyu(a, b, alternative="two-sided")
        d = cliffs_delta(a, b)
        print(f"  {pair[0]} vs {pair[1]}:")
        print(f"    median p95: {np.median(a):.2f} vs {np.median(b):.2f} ms")
        print(f"    Mann-Whitney U={stat:.1f}, p={p:.4f}, Cliff's d={d:.3f} ({interpret_cliffs_delta(d)})")
        print(f"    {'SIGNIFICANT' if p < ALPHA else 'not significant'}")


def test_hypothesis_h2(df):
    """H2: Success rate does not differ between Istio and R4J in S3, S4."""
    print("\n=== H2: Effectiveness (S3, S4) ===")
    for scenario in ["S3", "S4"]:
        sx = df[df["scenario"] == scenario]
        a = sx[sx["variant"] == "istio"]["success_rate"].dropna().values
        b = sx[sx["variant"] == "r4j"]["success_rate"].dropna().values

        if len(a) < 2 or len(b) < 2:
            print(f"  {scenario}: insufficient data")
            continue

        stat, p = stats.mannwhitneyu(a, b, alternative="two-sided")
        d = cliffs_delta(a, b)
        print(f"  {scenario}: istio vs r4j")
        print(f"    median success: {np.median(a)*100:.2f}% vs {np.median(b)*100:.2f}%")
        print(f"    Mann-Whitney U={stat:.1f}, p={p:.4f}, Cliff's d={d:.3f} ({interpret_cliffs_delta(d)})")
        print(f"    {'SIGNIFICANT difference' if p < ALPHA else 'no significant difference'}")


def test_hypothesis_h3(df):
    """H3: Recovery time differs between Istio and R4J in S5."""
    print("\n=== H3: Recovery time (S5) ===")
    print("  (Requires time-series data — placeholder for full implementation)")


def test_hypothesis_h4(df):
    """H4: Retry multiplication in S6 (both > istio, both > r4j)."""
    print("\n=== H4: Retry multiplication (S6) ===")
    print("  (Requires service-c request counter from Prometheus — placeholder)")


def plot_latency_cdf(df):
    """CDF of latency for S1 across variants."""
    s1 = df[df["scenario"] == "S1"]
    if s1.empty:
        return

    fig, ax = plt.subplots(figsize=(8, 5))
    for variant in sorted(s1["variant"].unique()):
        data = s1[s1["variant"] == variant]
        values = sorted(data["p95"].dropna().values)
        cdf = np.arange(1, len(values) + 1) / len(values)
        ax.step(values, cdf, label=variant, where="post")

    ax.set_xlabel("Latency p95 (ms)")
    ax.set_ylabel("CDF")
    ax.set_title("S1 — Latency CDF (no faults)")
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / "s1_latency_cdf.png", dpi=150)
    plt.close(fig)
    print("  Saved: s1_latency_cdf.png")


def plot_success_rate(df):
    """Bar chart of success rate by scenario and variant."""
    scenarios = ["S1", "S2", "S3", "S4", "S5"]
    data = df[df["scenario"].isin(scenarios)]
    if data.empty:
        return

    summary = data.groupby(["scenario", "variant"])["success_rate"].agg(
        ["mean", "std"]
    ).reset_index()

    fig, ax = plt.subplots(figsize=(10, 5))
    variants = sorted(summary["variant"].unique())
    x = np.arange(len(scenarios))
    width = 0.8 / len(variants)

    for i, variant in enumerate(variants):
        vdata = summary[summary["variant"] == variant]
        vdata = vdata.set_index("scenario").reindex(scenarios)
        ax.bar(
            x + i * width - 0.4 + width / 2,
            vdata["mean"] * 100,
            width,
            yerr=vdata["std"] * 100,
            label=variant,
            alpha=0.8,
        )

    ax.set_xlabel("Scenario")
    ax.set_ylabel("Success Rate (%)")
    ax.set_title("Success Rate by Scenario and Variant")
    ax.set_xticks(x)
    ax.set_xticklabels(scenarios)
    ax.legend()
    ax.set_ylim(0, 105)
    ax.grid(True, alpha=0.3, axis="y")
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / "success_rate.png", dpi=150)
    plt.close(fig)
    print("  Saved: success_rate.png")


def generate_summary_table(df):
    """Generate summary table with mean, std, and 95% CI."""
    summary = df.groupby(["scenario", "variant"]).agg(
        p95_mean=("p95", "mean"),
        p95_std=("p95", "std"),
        p95_count=("p95", "count"),
        success_mean=("success_rate", "mean"),
        success_std=("success_rate", "std"),
        rps_mean=("rps", "mean"),
    ).reset_index()

    # 95% CI for p95
    summary["p95_ci95"] = summary.apply(
        lambda r: stats.t.ppf(0.975, r["p95_count"] - 1) * r["p95_std"] / np.sqrt(r["p95_count"])
        if r["p95_count"] > 1 else np.nan,
        axis=1,
    )

    summary.to_csv(OUTPUT_DIR / "summary.csv", index=False)
    print(f"\n  Summary table saved: summary.csv")
    print(summary.to_string(index=False))


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print("=== Loading results ===")
    df = load_results()
    print(f"  Loaded {len(df)} result records")
    print(f"  Scenarios: {sorted(df['scenario'].unique())}")
    print(f"  Variants: {sorted(df['variant'].unique())}")

    # Save consolidated data
    df.to_csv(OUTPUT_DIR / "consolidated.csv", index=False)
    print(f"  Consolidated data saved: consolidated.csv")

    # Summary table
    generate_summary_table(df)

    # Hypothesis tests
    test_hypothesis_h1(df)
    test_hypothesis_h2(df)
    test_hypothesis_h3(df)
    test_hypothesis_h4(df)

    # Plots
    print("\n=== Generating plots ===")
    plot_latency_cdf(df)
    plot_success_rate(df)

    print("\n=== Analysis complete ===")
    print(f"  All outputs in: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
