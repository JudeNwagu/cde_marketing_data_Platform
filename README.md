# Marketing Data Platform (Facebook Ads and Snapchat Ads)

A small, production-minded data platform that combines Facebook Ads and Snapchat Ads data into one trusted, documented table.
It is built with **Databricks** (Unity Catalog), **dbt**, **Elementary** and **GitHub Actions**.

Marketers no longer need to open each advertising platform separately. Analysts, BI tools and AI agents can all query one model, `fct_marketing_spend`, without knowing how either platform structures its data.

> Author: Jude Nwagu. Repository: https://github.com/JudeNwagu/cde_marketing_data_Platform

---

## Contents

1. [Architecture](#1-architecture)
2. [The final model](#2-the-final-model)
3. [Engineering decisions](#3-engineering-decisions)
4. [Data quality](#4-data-quality)
5. [Documentation, lineage and observability](#5-documentation-lineage-and-observability)
6. [Environments and security](#6-environments-and-security)
7. [CI/CD](#7-cicd)
8. [Setup](#8-setup)
9. [Business questions the model answers](#9-business-questions-the-model-answers)
10. [Known limitations](#10-known-limitations)
11. [Repository layout](#11-repository-layout)

---

## 1. Architecture

```
Facebook Ads CSVs ─┐
                   ├─► Databricks volumes ─► Bronze (raw tables, never modified)
Snapchat Ads CSVs ─┘                              │
                                                  ▼
                                   dbt staging  (clean one source at a time)
                                                  │
                                                  ▼
                                   dbt intermediate (join and stack platforms)
                                                  │
                                                  ▼
                                   fct_marketing_spend  (gold)
                                                  │
                          ┌───────────────────────┼───────────────────────┐
                          ▼                       ▼                       ▼
                      Analysts (SQL)           BI tools              AI agents
```

| Layer | Where it lives (production) | Built by |
|---|---|---|
| Bronze (raw) | `marketing_bronze_prod.facebook_ads` and `.snapchat_ads` | `setup/databricks_setup.sql` |
| Staging | `marketing_silver_prod.staging` | dbt |
| Intermediate | `marketing_silver_prod.intermediate` | dbt |
| Final model | `marketing_gold_prod.marketing.fct_marketing_spend` | dbt |
| Monitoring | `marketing_gold_prod.elementary` | Elementary |

The four concerns the case study asks to keep separate are separate: **raw data** (bronze), **transformation logic** (staging and intermediate), **analytical models** (gold) and the **consumption layer** (SQL, BI, AI agents).

### Models

```
facebook_ads.* ─► stg_facebook_ads_stats ─┐
                  stg_facebook_ads        ├─► int_facebook_ads ─┐
                  stg_facebook_campaigns  │   (ephemeral)       │
                  stg_facebook_accounts  ─┘                     │
                                                                ├─► int_marketing_ads ─► fct_marketing_spend
snapchat_ads.* ─► stg_snapchat_ads_stats ─┐                     │
                  stg_snapchat_ads        ├─► int_snapchat_ads ─┘
                  stg_snapchat_ad_groups  │   (ephemeral)
                  stg_snapchat_campaigns ─┘
```

The full interactive lineage graph is in the generated dbt documentation (`docs/index.html`, also produced as a downloadable artifact on every CI and production run).

---

## 2. The final model

**`fct_marketing_spend`**

> **Grain: one row per campaign, platform, country, currency and day.**

**Primary key:** `marketing_spend_key`, a hash of `report_date`, `platform`, `campaign_id`, `country` and `currency`.

| Column | Meaning |
|---|---|
| `marketing_spend_key` | Unique key for the row |
| `report_date` | The day the activity happened |
| `platform` | `facebook` or `snapchat` |
| `campaign_id`, `campaign_name` | The platform's campaign. IDs are only unique within a platform, so always use them with `platform`. |
| `account_id` | The advertising account |
| `country` | Two-letter code. Only Snapchat reports it. Facebook rows use `unknown`, meaning "not reported". |
| `currency` | `USD` or `EUR`. **Never add spend across currencies.** |
| `spend`, `impressions`, `clicks` | Totals for the grain |
| `ctr` | `clicks / impressions` (a fraction, so 0.02 means 2 percent) |
| `cpc` | `spend / clicks` |
| `cpm` | `spend / impressions * 1000` |
| `has_missing_clicks`, `has_missing_impressions` | `true` when at least one ad in the row had no value reported, so totals and metrics built on them may be understated |

Metrics use `try_divide`, so zero or null clicks and impressions give `null` and never an error. Cost per click is undefined when nobody clicked, and `0` would wrongly claim clicks were free.

---

## 3. Engineering decisions

These answer the questions the case study asks for in section 20.

### Model structure
One staging model per raw table (no joins), then intermediate models for joins, then one wide final fact table. A single wide table was chosen over a fact plus dimension tables because there is one clear grain and the consumers (analysts, BI, an AI agent) want one table to query. If more consumers or more attributes appear, dimensions such as `dim_campaigns` can be split out of it.

### Grain and keys
The final grain is campaign × platform × country × currency × day, which is the case study's example grain plus the two columns the data forced on us. `platform` is part of the key because Facebook IDs are integers and Snapchat IDs are UUIDs, and nothing guarantees they never collide.

### Platform differences

| | Facebook | Snapchat |
|---|---|---|
| Stats grain | ad × day | ad × country × day |
| Stats-to-ad key | `ad_id` | `ad_detail_id` (renamed to `ad_id` in staging) |
| ID type | integer | UUID text (all IDs are cast to text in staging) |
| Path to campaign | ad → campaign | ad → ad group → campaign |
| Currency | per account (account table) | in the stats rows |
| Ad groups | not needed | history table with several versions per ad group |

Metric column names (`ad_spend`, `ad_impressions`, `ad_clicks`) matched across platforms. The real differences were keys, grain and join paths.

### Data issues found, and what was done

| Issue | Handling |
|---|---|
| The raw files contain the **text** `null`, not empty cells (24,337 Facebook clicks rows, 1,474 impressions rows, 111 Snapchat rows). Casting failed on it. | Staging uses `nullif(trim(col), 'null')` before casting. Any other malformed value still fails loudly, because `try_cast` would hide unexpected bad data. |
| Snapchat ad groups are a history table (3 ad groups have two versions). Joining without picking one multiplies rows and overcounts spend. | `stg_snapchat_ad_groups` keeps only the latest version per `ad_group_id` (264 rows from 267). |
| Null versus zero clicks | Null stays null and 0 stays 0. They mean different things (unknown versus nobody clicked). |
| Two currencies (USD and EUR) | A `currency` column is kept and spend is never converted, because no exchange rates exist in the data. |
| Facebook has no country | Filled with `unknown` so the key never contains a null. |
| 304 Snapchat ads point to an ad group missing from the ad group file | None of them has performance data, so no spend is affected. Documented, and tested with `severity: warn`. |

### Materializations

| Model | Materialization | Why |
|---|---|---|
| Staging | view | Light cleaning, no storage cost, always shows current bronze data |
| `int_facebook_ads`, `int_snapchat_ads` | ephemeral | Each is used by exactly one model and never queried directly, so there is nothing to store or keep in sync |
| `int_marketing_ads` | view | It is tested and read by the final model, so it needs a real object (ephemeral models cannot be tested) |
| `fct_marketing_spend` | incremental (`merge` on `marketing_spend_key`) | Queried constantly, and platforms add new days of data. Each run reprocesses only the last 3 days, because platforms often revise recent numbers. |

Honest note: with about 8,000 rows and static files, incremental is not needed for speed today. It is implemented because it is the right design once daily data keeps arriving. A `--full-refresh` rebuilds everything from scratch.

---

## 4. Data quality

56 automated tests (52 dbt tests and 4 Elementary tests) run on every build.

| Test | Protects against |
|---|---|
| `unique` and `not_null` on keys, and unique combinations at every grain | Duplicate rows and wrong grain (for example a join that multiplies rows) |
| `relationships` (stats to ads, ads to campaigns, ads to accounts, ad groups to campaigns) | Orphan rows and silently dropped spend |
| `accepted_values` for `platform`, `currency`, Facebook `ad_status` | A new or misspelled value appearing unnoticed |
| `accepted_range` of at least 0 for spend, impressions, clicks | Negative numbers from bad exports |
| `clicks <= impressions` (where nothing is missing) | Impossible rows |
| Elementary `schema_changes` on the final model and both stats staging models | A platform renaming or retyping a column |
| Elementary `volume_anomalies` on the final model | A sudden loss or gain of rows |

Deliberately **not** tested: `not_null` on `clicks`, because null clicks are legitimate in this data.

The 52 dbt tests finish with `PASS=51 WARN=1`. The single warning is the known Snapchat finding described above.

Time-bucketed Elementary anomaly tests (for example per-day volume) are not used. The data is from 2024 and 2025 and Elementary measures against the current date, so it would raise false alarms.

---

## 5. Documentation, lineage and observability

- Every source, model and important column has a description, including the grain of each model and the currency warning on the final model.
- **Static dbt documentation:** `docs/index.html`. Regenerate with `uv run dbt docs generate --static` (the file is `target/static_index.html`).
- **Lineage:** the lineage graph in the documentation shows every source flowing through staging and intermediate into `fct_marketing_spend`.
- **Elementary** records every production run and test result in `marketing_gold_prod.elementary` and produces an HTML report (`docs/elementary_report.html`): test results, failures, model health, run history and anomaly monitoring. The report is also saved as an artifact by the production workflow.

---

## 6. Environments and security

| Environment | dbt target | Authentication | Builds in |
|---|---|---|---|
| Development | `dev` | Personal access token (local only) | `marketing_dev.dbt_jude`, all layers together |
| CI | `ci` | Service Principal (OAuth) | `marketing_ci`, one schema per pull request (`pr_<number>`), deleted afterwards |
| Production | `prod` | **Service Principal (OAuth). No personal access token.** | `marketing_silver_prod` (staging, intermediate) and `marketing_gold_prod` (marketing, elementary) |

Two macros (`generate_database_name`, `generate_schema_name`) implement this: when the target is `prod`, each layer goes to the catalog and schema set in `dbt_project.yml`. For every other target, everything goes to the catalog and schema in the profile. A development run cannot touch production.

### Production authentication
Production runs as the Service Principal `sp-marketing-dbt`, so it does not depend on any individual's credentials. The tables it builds are **owned by the Service Principal**, not by a developer.
The OAuth secret was created with the `all-apis` scope, because the dbt connector requests that scope and a `sql`-only secret is rejected. The real limit on what the Service Principal can do is its Unity Catalog grants, below. The secret expires **11 October 2027** and must be rotated before then.

### Unity Catalog permissions (least privilege)

| Catalog | Service Principal | Developer |
|---|---|---|
| `marketing_bronze_prod` | `USE CATALOG`, `USE SCHEMA`, `SELECT` (read only) | owner |
| `marketing_silver_prod` | `USE CATALOG`, `USE SCHEMA`, `CREATE SCHEMA`, `CREATE TABLE`, `SELECT` | `USE CATALOG`, `USE SCHEMA`, `SELECT` |
| `marketing_gold_prod` | same as silver | same as silver |
| `marketing_ci` | same as silver | same as silver |

These differ from the case study's example grants on purpose: production never writes to bronze, never creates catalogs, and the raw data cannot be altered by the pipeline. The exact statements are in `setup/databricks_setup.sql`.

### Secrets handling
- Local credentials live in `.env` (ignored by Git). `.env.template` lists the variable names only.
- `profiles.yml` contains no secrets, only `env_var()` references, so it is safe to commit.
- Credential variables use the `DBX_` prefix. The Databricks library reads variables named `DATABRICKS_TOKEN`, `DATABRICKS_CLIENT_ID` and `DATABRICKS_CLIENT_SECRET` by itself, and having both a token and a client secret set made it refuse to choose a login method.
- GitHub Actions reads four repository secrets: `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH`, `DBX_CLIENT_ID`, `DBX_CLIENT_SECRET`. The personal token is never given to CI.

---

## 7. CI/CD

```
Feature branch ─► Pull request ─► CI (dbt build --target ci) ─► Merge to main ─► Production (dbt build --target prod)
```

| Workflow | Trigger | What it does |
|---|---|---|
| `.github/workflows/ci.yml` | Pull request into `main` | Installs the exact versions in `uv.lock`, runs `dbt build --target ci` in a schema named for the pull request, generates the docs, uploads them as an artifact, and always deletes the pull request schema afterwards |
| `.github/workflows/deploy.yml` | Merge into `main` (when the dbt project or its dependencies change), a daily schedule (06:00 UTC), or a manual button | Runs `dbt build --target prod` as the Service Principal, generates the docs and the Elementary report, and uploads both as artifacts. Two deployments can never run at once. |

Design choices:
- **Full build on every pull request** instead of "slim CI" (building only changed models). The whole project builds in about two minutes, so testing everything is simpler and safer. Slim CI becomes worthwhile when the project grows.
- `dbt build` runs each model and then its tests, in dependency order. If a test fails, everything downstream is skipped, so bad data cannot reach the final table.
- A cleanup macro (`drop_ci_schema`) refuses to run on any target except `ci`, so it can never be pointed at production.

---

## 8. Setup

### Prerequisites
- A Databricks workspace with Unity Catalog and a SQL warehouse
- [uv](https://docs.astral.sh/uv/) installed
- Git
- The raw CSV files (not stored in this repository)

### One-time Databricks setup
1. Create a Service Principal, generate an OAuth secret (scope `all-apis`), give it **Can use** on your SQL warehouse, and note its client ID.
2. Run `setup/databricks_setup.sql` in the SQL Editor. It creates the catalogs, schemas and volumes, then (after you upload the CSV files to the volumes) loads and verifies the bronze tables and applies the grants. Replace the two placeholders in section 7 of that file first.

### Local development

```bash
git clone https://github.com/JudeNwagu/cde_marketing_data_Platform.git
cd cde_marketing_data_Platform

uv sync                                  # installs dbt-databricks at the locked versions
cp .env.template .env                    # then fill in your values
set -a; source .env; set +a              # load them into this terminal

cd marketing_platform
uv run dbt deps
uv run dbt debug                         # dev target (personal access token)
uv run dbt build                         # builds and tests in marketing_dev.dbt_jude
uv run dbt docs generate --static
```

Run all dbt commands from inside `marketing_platform/`, which holds `dbt_project.yml` and `profiles.yml`.

### Production (normally done by GitHub Actions)

```bash
uv run dbt build --target prod
```

### Elementary report

```bash
uv tool install 'elementary-data[databricks]'
edr report --project-dir marketing_platform --profiles-dir marketing_platform --file-path docs/elementary_report.html
```

### GitHub secrets
Add `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH`, `DBX_CLIENT_ID` and `DBX_CLIENT_SECRET` under Settings, Secrets and variables, Actions.

---

## 9. Business questions the model answers

All queries read `marketing_gold_prod.marketing.fct_marketing_spend`. Because the model holds two currencies, spend questions are answered per currency.

**How much did we spend in total, on Facebook, and on Snapchat?**
```sql
SELECT platform, currency, ROUND(SUM(spend), 2) AS spend
FROM marketing_gold_prod.marketing.fct_marketing_spend
GROUP BY platform, currency
ORDER BY platform, currency;
```

**How many impressions and clicks did each platform generate?**
```sql
SELECT platform, SUM(impressions) AS impressions, SUM(clicks) AS clicks
FROM marketing_gold_prod.marketing.fct_marketing_spend
GROUP BY platform;
```

**Which campaigns generated the most clicks and impressions?**
```sql
SELECT platform, campaign_name, currency,
       ROUND(SUM(spend), 2) AS spend,
       SUM(impressions) AS impressions,
       SUM(clicks) AS clicks
FROM marketing_gold_prod.marketing.fct_marketing_spend
GROUP BY platform, campaign_name, currency
ORDER BY clicks DESC
LIMIT 10;
```

**What are CTR, CPC and CPM by platform?** (computed from totals, not by averaging row-level ratios)
```sql
SELECT platform, currency,
       try_divide(SUM(clicks), SUM(impressions))         AS ctr,
       try_divide(SUM(spend), SUM(clicks))               AS cpc,
       try_divide(CAST(SUM(spend) AS DOUBLE) * 1000, SUM(impressions))   AS cpm
FROM marketing_gold_prod.marketing.fct_marketing_spend
GROUP BY platform, currency;
```

**How does spend change over time?**
```sql
SELECT date_trunc('month', report_date) AS month, platform, currency,
       ROUND(SUM(spend), 2) AS spend
FROM marketing_gold_prod.marketing.fct_marketing_spend
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
```

### For AI agents
The model is designed to be queried in natural language. Table and column descriptions are written into the dbt documentation, and for the final model they are also persisted as Unity Catalog comments (`persist_docs`), so any tool that reads the catalog sees them. Names are plain (`spend`, `report_date`), metric definitions are stated, and the key trap is called out in the table description: never add spend across currencies. Example questions it should handle: "How much did we spend on Facebook last month?", "Which campaign had the highest number of clicks?", "Compare Facebook and Snapchat spend."

---

## 10. Known limitations

- **The platforms do not overlap in time.** Facebook covers 2025-01-01 to 2025-12-31 and Snapchat covers 2024-01-01 to 2024-12-02. A same-period comparison is not possible with this data, and the only like-for-like comparison is Facebook EUR versus Snapchat EUR.
- **Coverage gaps.** Snapchat has data in only 9 of the 12 months between its first and last day, and the Facebook EUR account stops on 2025-09-17 while the Facebook USD accounts run to 2025-12-31. Monthly trend charts will therefore show gaps. They are in the source data and are not a model error.
- **No currency conversion.** There are no exchange rates in the source data, so USD and EUR are always reported separately.
- **Facebook country is `unknown`.** Facebook campaign names start with a country code, which could fill it in a future version. It was not done because it infers data from a naming habit.
- **Null clicks and impressions** exist in the source data (about 26 percent of Facebook ad-days have no click count). They stay null, and the `has_missing_*` flags warn when a total may be understated.
- **Package override warning.** Elementary replaces dbt's built-in test materialization, which dbt 1.12 reports as `PackageMaterializationOverrideDeprecation`. It is only a warning. Versions are pinned in `uv.lock`, and this should be revisited when upgrading dbt or Elementary.
- **Leftover views.** After `int_facebook_ads` and `int_snapchat_ads` became ephemeral, the views from earlier runs remain in the intermediate schema. Nothing reads them, and dbt does not delete old objects automatically.
- **Broad OAuth scope.** The Service Principal's secret uses `all-apis`. Its Unity Catalog grants, not the scope, are what limit its access.
- **Secret rotation** is manual. The OAuth secret expires after 365 days.

---

## 11. Repository layout

```
.
├── .github/workflows/
│   ├── ci.yml                      # pull request validation
│   └── deploy.yml                  # production deployment
├── docs/
│   ├── index.html                  # static dbt documentation
│   └── elementary_report.html      # Elementary observability report
├── marketing_platform/             # the dbt project
│   ├── dbt_project.yml
│   ├── profiles.yml                # dev, ci, prod, elementary (no secrets)
│   ├── packages.yml                # dbt_utils, elementary
│   ├── macros/
│   │   ├── generate_database_name.sql
│   │   ├── generate_schema_name.sql
│   │   └── drop_ci_schema.sql
│   └── models/
│       ├── staging/{facebook_ads,snapchat_ads}/
│       ├── intermediate/
│       └── marts/
├── setup/databricks_setup.sql      # catalogs, schemas, volumes, bronze load, grants
├── .env.template                   # variable names only
├── pyproject.toml
├── uv.lock
└── README.md
```
