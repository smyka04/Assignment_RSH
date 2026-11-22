-- 01_load.sql
-- Read the four raw CSVs with explicit types.
-- Product ids are read as text: Instamart ids have leading zeros (IM062962)
-- and Zepto ids contain letters (ZP57321X).

CREATE OR REPLACE TABLE raw_daily_sales AS
SELECT *
FROM read_csv(getvariable('data_dir') || '/daily_sales.csv',
    header = true,
    columns = {
        'date': 'DATE',
        'platform': 'VARCHAR',
        'dark_store_id': 'VARCHAR',
        'platform_product_id': 'VARCHAR',
        'availability_pct': 'DOUBLE',
        'units_sold': 'INTEGER',
        'selling_price_inr': 'DOUBLE',
        'sales_inr': 'DOUBLE',
        'search_rank': 'INTEGER'
    });

CREATE OR REPLACE TABLE raw_dark_stores AS
SELECT *
FROM read_csv(getvariable('data_dir') || '/dark_stores.csv',
    header = true,
    columns = {
        'dark_store_id': 'VARCHAR',
        'platform': 'VARCHAR',
        'city': 'VARCHAR',
        'pincode': 'VARCHAR',
        'warehouse_id': 'VARCHAR',
        'opened_date': 'DATE'
    });

CREATE OR REPLACE TABLE raw_products AS
SELECT *
FROM read_csv(getvariable('data_dir') || '/products.csv',
    header = true,
    columns = {
        'platform': 'VARCHAR',
        'platform_product_id': 'VARCHAR',
        'sku_code': 'VARCHAR',
        'product_name': 'VARCHAR',
        'category': 'VARCHAR',
        'pack_size': 'VARCHAR',
        'mrp_inr': 'DOUBLE'
    });

CREATE OR REPLACE TABLE raw_purchase_orders AS
SELECT *
FROM read_csv(getvariable('data_dir') || '/purchase_orders.csv',
    header = true,
    columns = {
        'po_id': 'VARCHAR',
        'po_date': 'DATE',
        'platform': 'VARCHAR',
        'warehouse_id': 'VARCHAR',
        'sku_code': 'VARCHAR',
        'qty_ordered': 'INTEGER',
        'qty_delivered': 'INTEGER',
        'delivery_date': 'DATE'
    });
