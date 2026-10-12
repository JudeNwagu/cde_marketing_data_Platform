-- =====================================================================
-- Marketing Data Platform: Databricks setup
-- Run these statements in the Databricks SQL Editor, in order.
-- Replace the placeholders in section 7 before running it.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Catalogs (one per layer and environment)
-- ---------------------------------------------------------------------
CREATE CATALOG IF NOT EXISTS marketing_bronze_prod;   -- raw data
CREATE CATALOG IF NOT EXISTS marketing_silver_prod;   -- dbt staging and intermediate (production)
CREATE CATALOG IF NOT EXISTS marketing_gold_prod;     -- final model and Elementary (production)
CREATE CATALOG IF NOT EXISTS marketing_ci;            -- pull request builds
CREATE CATALOG IF NOT EXISTS marketing_dev;           -- local development

SHOW CATALOGS;


-- ---------------------------------------------------------------------
-- 2. Raw schemas: one per source system
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS marketing_bronze_prod.facebook_ads;
CREATE SCHEMA IF NOT EXISTS marketing_bronze_prod.snapchat_ads;


-- ---------------------------------------------------------------------
-- 3. Volumes: storage for the original CSV files
-- ---------------------------------------------------------------------
CREATE VOLUME IF NOT EXISTS marketing_bronze_prod.facebook_ads.raw_files;
CREATE VOLUME IF NOT EXISTS marketing_bronze_prod.snapchat_ads.raw_files;


-- ---------------------------------------------------------------------
-- 4. MANUAL STEP: upload the CSV files
--    Catalog -> marketing_bronze_prod -> <schema> -> Volumes -> raw_files
--    -> "Upload to this volume". Keep the file names exactly as they are.
--
--    facebook_ads/raw_files:
--      ads_stats.csv
--      new_ads_de_randomized.csv
--      new_campaign_de_randomized.csv
--      new_adgroup_de_randomized.csv
--      new_acccount_de_randomized.csv        (three c's, as in the source)
--
--    snapchat_ads/raw_files:
--      snapchat_ads_stats.csv
--      snapchat_ads_ad_history_new_ad_names.csv
--      snapchat_ads_adgroup_history_new_ad_group_names.csv
--      snapchat_ads_campaign_history_new_campaign_names.csv
-- ---------------------------------------------------------------------

LIST '/Volumes/marketing_bronze_prod/facebook_ads/raw_files/';
LIST '/Volumes/marketing_bronze_prod/snapchat_ads/raw_files/';


-- ---------------------------------------------------------------------
-- 5. Load the bronze tables
--    All columns are loaded as text (inferSchema = false) so bronze stays
--    exactly as received. Typing happens in the dbt staging models.
--    COPY INTO remembers which files it loaded, so re-running is safe.
-- ---------------------------------------------------------------------

-- Facebook
CREATE TABLE IF NOT EXISTS marketing_bronze_prod.facebook_ads.ads_stats;
COPY INTO marketing_bronze_prod.facebook_ads.ads_stats
FROM '/Volumes/marketing_bronze_prod/facebook_ads/raw_files/ads_stats.csv'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'false', 'mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

CREATE TABLE IF NOT EXISTS marketing_bronze_prod.facebook_ads.ads;
COPY INTO marketing_bronze_prod.facebook_ads.ads
FROM '/Volumes/marketing_bronze_prod/facebook_ads/raw_files/new_ads_de_randomized.csv'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'false', 'mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

CREATE TABLE IF NOT EXISTS marketing_bronze_prod.facebook_ads.campaigns;
COPY INTO marketing_bronze_prod.facebook_ads.campaigns
FROM '/Volumes/marketing_bronze_prod/facebook_ads/raw_files/new_campaign_de_randomized.csv'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'false', 'mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

CREATE TABLE IF NOT EXISTS marketing_bronze_prod.facebook_ads.ad_groups;
COPY INTO marketing_bronze_prod.facebook_ads.ad_groups
FROM '/Volumes/marketing_bronze_prod/facebook_ads/raw_files/new_adgroup_de_randomized.csv'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'false', 'mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

CREATE TABLE IF NOT EXISTS marketing_bronze_prod.facebook_ads.accounts;
COPY INTO marketing_bronze_prod.facebook_ads.accounts
FROM '/Volumes/marketing_bronze_prod/facebook_ads/raw_files/new_acccount_de_randomized.csv'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'false', 'mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

-- Snapchat
CREATE TABLE IF NOT EXISTS marketing_bronze_prod.snapchat_ads.ads_stats;
COPY INTO marketing_bronze_prod.snapchat_ads.ads_stats
FROM '/Volumes/marketing_bronze_prod/snapchat_ads/raw_files/snapchat_ads_stats.csv'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'false', 'mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

CREATE TABLE IF NOT EXISTS marketing_bronze_prod.snapchat_ads.ads;
COPY INTO marketing_bronze_prod.snapchat_ads.ads
FROM '/Volumes/marketing_bronze_prod/snapchat_ads/raw_files/snapchat_ads_ad_history_new_ad_names.csv'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'false', 'mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

CREATE TABLE IF NOT EXISTS marketing_bronze_prod.snapchat_ads.ad_groups;
COPY INTO marketing_bronze_prod.snapchat_ads.ad_groups
FROM '/Volumes/marketing_bronze_prod/snapchat_ads/raw_files/snapchat_ads_adgroup_history_new_ad_group_names.csv'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'false', 'mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

CREATE TABLE IF NOT EXISTS marketing_bronze_prod.snapchat_ads.campaigns;
COPY INTO marketing_bronze_prod.snapchat_ads.campaigns
FROM '/Volumes/marketing_bronze_prod/snapchat_ads/raw_files/snapchat_ads_campaign_history_new_campaign_names.csv'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'false', 'mergeSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');


-- ---------------------------------------------------------------------
-- 6. Verify the load: row counts must match the source files
-- ---------------------------------------------------------------------
SELECT 'facebook_ads.ads_stats' AS tbl, COUNT(*) AS row_count FROM marketing_bronze_prod.facebook_ads.ads_stats      -- expect 92,300
UNION ALL SELECT 'facebook_ads.ads',        COUNT(*) FROM marketing_bronze_prod.facebook_ads.ads                       -- expect 98,926
UNION ALL SELECT 'facebook_ads.campaigns',  COUNT(*) FROM marketing_bronze_prod.facebook_ads.campaigns                 -- expect 4,162
UNION ALL SELECT 'facebook_ads.ad_groups',  COUNT(*) FROM marketing_bronze_prod.facebook_ads.ad_groups                 -- expect 13,433
UNION ALL SELECT 'facebook_ads.accounts',   COUNT(*) FROM marketing_bronze_prod.facebook_ads.accounts                  -- expect 16
UNION ALL SELECT 'snapchat_ads.ads_stats',  COUNT(*) FROM marketing_bronze_prod.snapchat_ads.ads_stats                 -- expect 2,809
UNION ALL SELECT 'snapchat_ads.ads',        COUNT(*) FROM marketing_bronze_prod.snapchat_ads.ads                       -- expect 2,513
UNION ALL SELECT 'snapchat_ads.ad_groups',  COUNT(*) FROM marketing_bronze_prod.snapchat_ads.ad_groups                 -- expect 267
UNION ALL SELECT 'snapchat_ads.campaigns',  COUNT(*) FROM marketing_bronze_prod.snapchat_ads.campaigns;                -- expect 109


-- ---------------------------------------------------------------------
-- 7. Unity Catalog permissions
--    Replace <SERVICE_PRINCIPAL_CLIENT_ID> with the Service Principal's
--    application (client) ID, and <YOUR_EMAIL> with your Databricks login.
--    Keep the backticks.
-- ---------------------------------------------------------------------

-- Bronze: the Service Principal only READS raw data
GRANT USE CATALOG, USE SCHEMA, SELECT
ON CATALOG marketing_bronze_prod TO `<SERVICE_PRINCIPAL_CLIENT_ID>`;

-- Silver, gold and CI: the Service Principal builds and owns these models
GRANT USE CATALOG, USE SCHEMA, CREATE SCHEMA, CREATE TABLE, SELECT
ON CATALOG marketing_silver_prod TO `<SERVICE_PRINCIPAL_CLIENT_ID>`;

GRANT USE CATALOG, USE SCHEMA, CREATE SCHEMA, CREATE TABLE, SELECT
ON CATALOG marketing_gold_prod TO `<SERVICE_PRINCIPAL_CLIENT_ID>`;

GRANT USE CATALOG, USE SCHEMA, CREATE SCHEMA, CREATE TABLE, SELECT
ON CATALOG marketing_ci TO `<SERVICE_PRINCIPAL_CLIENT_ID>`;

-- Developer: read-only access to what production and CI build
GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG marketing_silver_prod TO `<YOUR_EMAIL>`;
GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG marketing_gold_prod   TO `<YOUR_EMAIL>`;
GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG marketing_ci          TO `<YOUR_EMAIL>`;

-- Check
SHOW GRANTS ON CATALOG marketing_bronze_prod;
SHOW GRANTS ON CATALOG marketing_gold_prod;
