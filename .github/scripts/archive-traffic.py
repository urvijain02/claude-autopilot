#!/usr/bin/env python3
"""
Perpetual Repository Telemetry & Traffic Archiver
Ingests GitHub Traffic REST API metrics (views, clones, referrers, paths),
deduplicates time-series records, renders responsive SVG charts, and persists
the permanent archive to an isolated orphan branch ('traffic-data').
"""

import csv
import datetime
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request


def log(msg: str):
    print(f"[traffic-archiver] {msg}", flush=True)


def check_auth_or_exit() -> str:
    token = os.environ.get("TRAFFIC_ACTION_TOKEN", "").strip()
    if not token:
        log("TRAFFIC_ACTION_TOKEN secret is not configured; skipping archiver cleanly (code 0).")
        sys.exit(0)
    return token


def fetch_api(endpoint: str, repo: str, token: str):
    url = f"https://api.github.com/repos/{repo}/traffic/{endpoint}"
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Claude-Autopilot-Traffic-Archiver",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 403:
            log(f"WARNING: GitHub API returned 403 Forbidden for '{endpoint}'. Verify token scopes. Skipping.")
            sys.exit(0)
        log(f"API Error ({e.code}) fetching '{endpoint}': {e.reason}")
        sys.exit(1)
    except Exception as e:
        log(f"Network error fetching '{endpoint}': {e}")
        sys.exit(1)


def setup_data_branch(repo: str, token: str, work_dir: str, branch: str = "traffic-data"):
    auth_url = f"https://x-access-token:{token}@github.com/{repo}.git"
    os.makedirs(work_dir, exist_ok=True)

    ls_remote = subprocess.run(
        ["git", "ls-remote", "--heads", auth_url, branch],
        capture_output=True,
        text=True,
    )

    if branch in ls_remote.stdout:
        log(f"Branch '{branch}' exists on remote. Performing shallow clone...")
        subprocess.run(
            ["git", "clone", "--depth", "1", "--branch", branch, auth_url, work_dir],
            check=True,
        )
    else:
        log(f"Branch '{branch}' not found on remote. Initializing clean orphan branch...")
        subprocess.run(["git", "init"], cwd=work_dir, check=True)
        subprocess.run(["git", "checkout", "--orphan", branch], cwd=work_dir, check=True)
        subprocess.run(["git", "remote", "add", "origin", auth_url], cwd=work_dir, check=True)


def load_csv(path: str, key_col: str) -> dict:
    records = {}
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get(key_col):
                    records[row[key_col]] = row
    return records


def write_csv(path: str, fieldnames: list, rows: list):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def merge_views(api_data: dict, work_dir: str) -> list:
    csv_path = os.path.join(work_dir, "traffic", "views.csv")
    json_path = os.path.join(work_dir, "traffic", "views.json")
    records = load_csv(csv_path, "date")

    for item in api_data.get("views", []):
        ts = item.get("timestamp", "")[:10]  # YYYY-MM-DD
        if ts:
            records[ts] = {
                "date": ts,
                "views": str(item.get("count", 0)),
                "uniques": str(item.get("uniques", 0)),
            }

    sorted_rows = [records[k] for k in sorted(records.keys())]
    write_csv(csv_path, ["date", "views", "uniques"], sorted_rows)

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({"views": sorted_rows}, f, indent=2)

    return sorted_rows


def merge_clones(api_data: dict, work_dir: str) -> list:
    csv_path = os.path.join(work_dir, "traffic", "clones.csv")
    json_path = os.path.join(work_dir, "traffic", "clones.json")
    records = load_csv(csv_path, "date")

    for item in api_data.get("clones", []):
        ts = item.get("timestamp", "")[:10]  # YYYY-MM-DD
        if ts:
            records[ts] = {
                "date": ts,
                "clones": str(item.get("count", 0)),
                "uniques": str(item.get("uniques", 0)),
            }

    sorted_rows = [records[k] for k in sorted(records.keys())]
    write_csv(csv_path, ["date", "clones", "uniques"], sorted_rows)

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({"clones": sorted_rows}, f, indent=2)

    return sorted_rows


def merge_referrers(api_data: list, work_dir: str, today: str) -> list:
    csv_path = os.path.join(work_dir, "traffic", "referrers.csv")
    existing_rows = []
    if os.path.exists(csv_path):
        with open(csv_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            existing_rows = [r for r in reader if r.get("date") != today]

    for item in api_data:
        referrer = item.get("referrer", "").strip()
        if referrer:
            existing_rows.append(
                {
                    "date": today,
                    "referrer": referrer,
                    "views": str(item.get("count", 0)),
                    "uniques": str(item.get("uniques", 0)),
                }
            )

    existing_rows.sort(key=lambda r: (r["date"], r["referrer"]))
    write_csv(csv_path, ["date", "referrer", "views", "uniques"], existing_rows)
    return existing_rows


def merge_paths(api_data: list, work_dir: str, today: str) -> list:
    csv_path = os.path.join(work_dir, "traffic", "paths.csv")
    existing_rows = []
    if os.path.exists(csv_path):
        with open(csv_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            existing_rows = [r for r in reader if r.get("date") != today]

    for item in api_data:
        path = item.get("path", "").strip()
        if path:
            existing_rows.append(
                {
                    "date": today,
                    "path": path,
                    "title": item.get("title", "").strip() or path,
                    "views": str(item.get("count", 0)),
                    "uniques": str(item.get("uniques", 0)),
                }
            )

    existing_rows.sort(key=lambda r: (r["date"], r["path"]))
    write_csv(csv_path, ["date", "path", "title", "views", "uniques"], existing_rows)
    return existing_rows


def generate_svg_chart(
    data: list,
    val_key: str,
    unq_key: str,
    title: str,
    val_label: str,
    unq_label: str,
    val_color: str = "#2f81f7",
    unq_color: str = "#3fb950",
) -> str:
    """Renders a responsive, modern dark-themed SVG line chart."""
    width = 820
    height = 340
    margin_left = 65
    margin_right = 40
    margin_top = 55
    margin_bottom = 50
    plot_width = width - margin_left - margin_right
    plot_height = height - margin_top - margin_bottom

    if not data:
        # Graceful empty state
        return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="100%" height="100%">
  <rect width="{width}" height="{height}" fill="#0d1117" rx="8" stroke="#30363d" stroke-width="1"/>
  <text x="{width // 2}" y="{height // 2}" fill="#8b949e" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif" font-size="14" text-anchor="middle">No traffic data recorded yet.</text>
</svg>
"""

    dates = [d["date"] for d in data]
    val_series = [int(d[val_key]) for d in data]
    unq_series = [int(d[unq_key]) for d in data]

    max_val = max(max(val_series, default=0), max(unq_series, default=0), 5)
    # Round max_val up to nice interval
    if max_val <= 10:
        y_max = 10
    elif max_val <= 50:
        y_max = ((max_val + 9) // 10) * 10
    elif max_val <= 200:
        y_max = ((max_val + 24) // 25) * 25
    else:
        y_max = ((max_val + 49) // 50) * 50

    n_points = len(dates)

    def x_coord(idx: int) -> float:
        if n_points == 1:
            return margin_left + plot_width / 2
        return margin_left + (idx / (n_points - 1)) * plot_width

    def y_coord(val: int) -> float:
        ratio = val / y_max
        return margin_top + plot_height - (ratio * plot_height)

    # Build Y grid lines
    y_grid_lines = []
    y_ticks = 4
    for i in range(y_ticks + 1):
        tick_val = int((y_max / y_ticks) * i)
        y_pos = y_coord(tick_val)
        y_grid_lines.append(
            f'  <line x1="{margin_left}" y1="{y_pos:.1f}" x2="{margin_left + plot_width}" y2="{y_pos:.1f}" stroke="#21262d" stroke-width="1" stroke-dasharray="3 3"/>'
        )
        y_grid_lines.append(
            f'  <text x="{margin_left - 12}" y="{y_pos + 4:.1f}" fill="#8b949e" font-family="-apple-system,sans-serif" font-size="11" text-anchor="end">{tick_val:,}</text>'
        )

    # Build X labels with adaptive spacing
    x_labels = []
    step = 1
    if n_points > 30:
        step = max(1, n_points // 6)
    elif n_points > 14:
        step = 2

    for idx, dt in enumerate(dates):
        if idx % step == 0 or idx == n_points - 1:
            xc = x_coord(idx)
            # Format display label (e.g. "Oct 19")
            try:
                dt_obj = datetime.date.fromisoformat(dt)
                lbl = dt_obj.strftime("%b %d")
            except Exception:
                lbl = dt
            x_labels.append(
                f'  <text x="{xc:.1f}" y="{margin_top + plot_height + 22}" fill="#8b949e" font-family="-apple-system,sans-serif" font-size="11" text-anchor="middle">{lbl}</text>'
            )

    # Build Polylines and Area paths
    val_points = [f"{x_coord(i):.1f},{y_coord(v):.1f}" for i, v in enumerate(val_series)]
    unq_points = [f"{x_coord(i):.1f},{y_coord(u):.1f}" for i, u in enumerate(unq_series)]

    val_line_str = " ".join(val_points)
    unq_line_str = " ".join(unq_points)

    base_y = margin_top + plot_height
    val_area_str = f"{margin_left:.1f},{base_y:.1f} " + val_line_str + f" {x_coord(n_points-1):.1f},{base_y:.1f}"
    unq_area_str = f"{margin_left:.1f},{base_y:.1f} " + unq_line_str + f" {x_coord(n_points-1):.1f},{base_y:.1f}"

    # Dot markers
    dots = []
    for i in range(n_points):
        xc = x_coord(i)
        dots.append(f'  <circle cx="{xc:.1f}" cy="{y_coord(val_series[i]):.1f}" r="3" fill="{val_color}"/>')
        dots.append(f'  <circle cx="{xc:.1f}" cy="{y_coord(unq_series[i]):.1f}" r="3" fill="{unq_color}"/>')
    safe_title = title.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    safe_val_label = val_label.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    safe_unq_label = unq_label.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">
  <defs>
    <linearGradient id="valGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{val_color}" stop-opacity="0.30"/>
      <stop offset="100%" stop-color="{val_color}" stop-opacity="0.0"/>
    </linearGradient>
    <linearGradient id="unqGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{unq_color}" stop-opacity="0.25"/>
      <stop offset="100%" stop-color="{unq_color}" stop-opacity="0.0"/>
    </linearGradient>
  </defs>

  <!-- Container Box -->
  <rect width="{width}" height="{height}" fill="#0d1117" rx="8" stroke="#30363d" stroke-width="1"/>

  <!-- Chart Title -->
  <text x="{margin_left}" y="32" fill="#f0f6fc" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif" font-size="14" font-weight="600">{safe_title}</text>

  <!-- Legend -->
  <circle cx="{width - 240}" cy="28" r="4.5" fill="{val_color}"/>
  <text x="{width - 230}" y="32" fill="#c9d1d9" font-family="-apple-system,sans-serif" font-size="12">{safe_val_label}</text>
  <circle cx="{width - 120}" cy="28" r="4.5" fill="{unq_color}"/>
  <text x="{width - 110}" y="32" fill="#c9d1d9" font-family="-apple-system,sans-serif" font-size="12">{safe_unq_label}</text>

  <!-- Grid Lines -->
{chr(10).join(y_grid_lines)}

  <!-- Area Fills -->
  <polygon points="{val_area_str}" fill="url(#valGrad)"/>
  <polygon points="{unq_area_str}" fill="url(#unqGrad)"/>

  <!-- Line Curves -->
  <polyline points="{val_line_str}" fill="none" stroke="{val_color}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
  <polyline points="{unq_line_str}" fill="none" stroke="{unq_color}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>

  <!-- Point Dots -->
{chr(10).join(dots)}

  <!-- X Axis Labels -->
{chr(10).join(x_labels)}
</svg>
"""


def render_dashboard(views_rows: list, clones_rows: list, referrers_rows: list, paths_rows: list, work_dir: str):
    now_utc = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    # Cumulative calculations
    total_views = sum(int(r.get("views", 0)) for r in views_rows)
    total_view_uniques = sum(int(r.get("uniques", 0)) for r in views_rows)
    total_clones = sum(int(r.get("clones", 0)) for r in clones_rows)
    total_clone_uniques = sum(int(r.get("uniques", 0)) for r in clones_rows)

    # Aggregate referrers (cumulative all-time)
    ref_agg = {}
    for r in referrers_rows:
        domain = r.get("referrer", "unknown")
        if domain not in ref_agg:
            ref_agg[domain] = {"views": 0, "uniques": 0}
        ref_agg[domain]["views"] += int(r.get("views", 0))
        ref_agg[domain]["uniques"] += int(r.get("uniques", 0))

    sorted_refs = sorted(ref_agg.items(), key=lambda x: x[1]["views"], reverse=True)
    all_ref_views = sum(v["views"] for v in ref_agg.values()) or 1

    ref_table_lines = [
        "| Domain | Total Hits | Unique Visitors | % of Total Traffic |",
        "| :--- | :--- | :--- | :--- |",
    ]
    if sorted_refs:
        for dom, stats in sorted_refs[:15]:
            pct = (stats["views"] / all_ref_views) * 100
            ref_table_lines.append(f"| `{dom}` | {stats['views']:,} | {stats['uniques']:,} | {pct:.1f}% |")
    else:
        ref_table_lines.append("| *No referral data recorded yet* | — | — | — |")

    # Aggregate paths (cumulative all-time)
    path_agg = {}
    for r in paths_rows:
        pth = r.get("path", "")
        title = r.get("title", "") or pth
        if pth not in path_agg:
            path_agg[pth] = {"title": title, "views": 0, "uniques": 0}
        path_agg[pth]["views"] += int(r.get("views", 0))
        path_agg[pth]["uniques"] += int(r.get("uniques", 0))

    sorted_paths = sorted(path_agg.items(), key=lambda x: x[1]["views"], reverse=True)
    path_table_lines = [
        "| Document / Path | Page Views | Unique Readers |",
        "| :--- | :--- | :--- |",
    ]
    if sorted_paths:
        for pth, stats in sorted_paths[:15]:
            label = f"`{pth}`"
            if stats["title"] and stats["title"] != pth:
                label = f"**{stats['title']}** (`{pth}`)"
            path_table_lines.append(f"| {label} | {stats['views']:,} | {stats['uniques']:,} |")
    else:
        path_table_lines.append("| *No path data recorded yet* | — | — |")

    dashboard_content = f"""# 📊 Claude Autopilot — Traffic & Adoption Dashboard

*Last updated: {now_utc}*

This branch (`traffic-data`) permanently archives repository telemetry, overcoming GitHub's 14-day rolling window deletion policy. All time-series data is persisted exclusively to this orphan branch, keeping `main` 100% clean.

```mermaid
flowchart LR
    subgraph Main_Branch["1. Main Branch (main)"]
        WF[".github/workflows/traffic-archive.yml\\n• Cron (00:15 UTC)\\n• workflow_dispatch"]
    end

    subgraph Actions_Runner["2. Ephemeral Runner"]
        API["Query Traffic API"] --> Process["Merge CSVs\\n& Render SVGs"]
    end

    subgraph Orphan_Branch["3. Orphan Branch (traffic-data)"]
        Data["traffic-data\\n• *.csv & *.json\\n• *.svg charts\\n• README.md\\n• 0 commits on main"]
    end

    WF -->|1. Spawns| API
    Process -->|2. Pushes ONLY to| Data
```

---

## 📈 Lifetime Key Performance Indicators (KPIs)

| Metric | All-Time Total |
| :--- | :--- |
| **Total Page Views** | {total_views:,} |
| **Cumulative Daily Uniques** | {total_view_uniques:,} |
| **Total Git Clones** | {total_clones:,} |
| **Unique Git Cloners** | {total_clone_uniques:,} |

---

## 📉 Views & Visitor Trends

![Views Trend](views-chart.svg)

---

## 📦 Git Clones Trend

![Clones Trend](clones-chart.svg)

---

## 🌐 Top Referring Domains (All-Time)

{chr(10).join(ref_table_lines)}

---

## 📄 Top Documentation Paths (Document Heatmap)

{chr(10).join(path_table_lines)}

---

*Automated repository telemetry archived nightly at 00:15 UTC via Claude Autopilot Traffic Archiver.*
"""

    readme_path = os.path.join(work_dir, "README.md")
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(dashboard_content)


def commit_and_push(work_dir: str, branch: str = "traffic-data"):
    subprocess.run(["git", "config", "user.name", "github-actions[bot]"], cwd=work_dir, check=True)
    subprocess.run(
        ["git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"],
        cwd=work_dir,
        check=True,
    )
    subprocess.run(["git", "add", "-A"], cwd=work_dir, check=True)

    status = subprocess.run(["git", "status", "--porcelain"], cwd=work_dir, capture_output=True, text=True)
    if not status.stdout.strip():
        log("No changes detected in traffic analytics; working tree is already up to date.")
        return

    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    commit_msg = f"chore(telemetry): update traffic analytics [{today}]"
    subprocess.run(["git", "commit", "-m", commit_msg], cwd=work_dir, check=True)
    log(f"Committed changes on {branch}: {commit_msg}")

    subprocess.run(["git", "push", "-u", "origin", branch], cwd=work_dir, check=True)
    log(f"Successfully pushed traffic archive to branch '{branch}'.")


def main():
    token = check_auth_or_exit()
    repo = os.environ.get("GITHUB_REPOSITORY", "").strip() or "urvijain02/claude-autopilot"
    work_dir = os.path.join(os.getcwd(), ".traffic-work")

    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    log(f"Starting traffic ingestion for repository '{repo}' [{today}]...")

    # 1. Fetch API data
    views_data = fetch_api("views", repo, token)
    clones_data = fetch_api("clones", repo, token)
    referrers_data = fetch_api("popular/referrers", repo, token)
    paths_data = fetch_api("popular/paths", repo, token)

    # 2. Setup isolated orphan branch workspace
    setup_data_branch(repo, token, work_dir, "traffic-data")

    # 3. Merge data
    views_rows = merge_views(views_data, work_dir)
    clones_rows = merge_clones(clones_data, work_dir)
    referrers_rows = merge_referrers(referrers_data, work_dir, today)
    paths_rows = merge_paths(paths_data, work_dir, today)

    # 4. Generate SVG charts
    views_svg = generate_svg_chart(
        views_rows,
        "views",
        "uniques",
        "Repository Page Views & Unique Visitors (Daily)",
        "Total Views",
        "Unique Visitors",
        "#2f81f7",
        "#3fb950",
    )
    with open(os.path.join(work_dir, "views-chart.svg"), "w", encoding="utf-8") as f:
        f.write(views_svg)

    clones_svg = generate_svg_chart(
        clones_rows,
        "clones",
        "uniques",
        "Repository Git Clones & Unique Cloners (Daily)",
        "Total Clones",
        "Unique Cloners",
        "#a371f7",
        "#3fb950",
    )
    with open(os.path.join(work_dir, "clones-chart.svg"), "w", encoding="utf-8") as f:
        f.write(clones_svg)

    # 5. Render dashboard README
    render_dashboard(views_rows, clones_rows, referrers_rows, paths_rows, work_dir)

    # 6. Commit and push strictly to orphan branch
    commit_and_push(work_dir, "traffic-data")
    log("Traffic archiver execution finished successfully.")


if __name__ == "__main__":
    main()
