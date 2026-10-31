# 📊 Claude Autopilot — Traffic & Adoption Dashboard

*Last updated: 2026-10-31 05:30 UTC*

This branch (`traffic-data`) permanently archives repository telemetry, overcoming GitHub's 14-day rolling window deletion policy. All time-series data is persisted exclusively to this orphan branch, keeping `main` 100% clean.

```mermaid
flowchart LR
    subgraph Main_Branch["1. Main Branch (main)"]
        WF[".github/workflows/traffic-archive.yml\n• Cron (00:15 UTC)\n• workflow_dispatch"]
    end

    subgraph Actions_Runner["2. Ephemeral Runner"]
        API["Query Traffic API"] --> Process["Merge CSVs\n& Render SVGs"]
    end

    subgraph Orphan_Branch["3. Orphan Branch (traffic-data)"]
        Data["traffic-data\n• *.csv & *.json\n• *.svg charts\n• README.md\n• 0 commits on main"]
    end

    WF -->|1. Spawns| API
    Process -->|2. Pushes ONLY to| Data
```

---

## 📈 Lifetime Key Performance Indicators (KPIs)

| Metric | All-Time Total |
| :--- | :--- |
| **Total Page Views** | 100 |
| **Cumulative Daily Uniques** | 9 |
| **Total Git Clones** | 220 |
| **Unique Git Cloners** | 120 |

---

## 📉 Views & Visitor Trends

![Views Trend](views-chart.svg)

---

## 📦 Git Clones Trend

![Clones Trend](clones-chart.svg)

---

## 🌐 Top Referring Domains (All-Time)

| Domain | Total Hits | Unique Visitors | % of Total Traffic |
| :--- | :--- | :--- | :--- |
| `github.com` | 12 | 6 | 100.0% |

---

## 📄 Top Documentation Paths (Document Heatmap)

| Document / Path | Page Views | Unique Readers |
| :--- | :--- | :--- |
| **/pulls** (`/urvijain02/claude-autopilot/pulls`) | 86 | 12 |
| **/actions** (`/urvijain02/claude-autopilot/actions`) | 50 | 10 |
| **/pull/4** (`/urvijain02/claude-autopilot/pull/4`) | 50 | 10 |
| **/pull/2** (`/urvijain02/claude-autopilot/pull/2`) | 36 | 12 |
| **/actions/workflows/traffic-archive.yml** (`/urvijain02/claude-autopilot/actions/workflows/traffic-archive.yml`) | 30 | 10 |
| **/actions/runs/39072240583/job/117512071539** (`/urvijain02/claude-autopilot/actions/runs/39072240583/job/117512071539`) | 12 | 12 |
| **/actions/runs/39072240583/job/117512071719** (`/urvijain02/claude-autopilot/actions/runs/39072240583/job/117512071719`) | 12 | 12 |
| **Overview** (`/urvijain02/claude-autopilot`) | 12 | 6 |
| **/tree/main** (`/urvijain02/claude-autopilot/tree/main`) | 11 | 1 |
| **/actions/runs/39410164482** (`/urvijain02/claude-autopilot/actions/runs/39410164482`) | 9 | 9 |
| **/actions/runs/39410164482/job/118585688863** (`/urvijain02/claude-autopilot/actions/runs/39410164482/job/118585688863`) | 9 | 9 |
| **/actions/runs/39413793156** (`/urvijain02/claude-autopilot/actions/runs/39413793156`) | 6 | 6 |
| **/activity** (`/urvijain02/claude-autopilot/activity`) | 2 | 2 |
| **/commits/main** (`/urvijain02/claude-autopilot/commits/main`) | 2 | 2 |
| **/compare/phase-4-telemetry** (`/urvijain02/claude-autopilot/compare/phase-4-telemetry`) | 2 | 2 |

---

*Automated repository telemetry archived nightly at 00:15 UTC via Claude Autopilot Traffic Archiver.*
