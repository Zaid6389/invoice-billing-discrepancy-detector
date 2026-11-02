-- 1. Vendors
CREATE TABLE vendors (
    vendor_id VARCHAR(50) PRIMARY KEY,
    vendor_name VARCHAR(150),
    category VARCHAR(100),
    payment_terms_days INTEGER
); 

-- 2. Contracts
CREATE TABLE contracts (
    vendor_id VARCHAR(50),
    item_code VARCHAR(50),
    contract_rate NUMERIC(12,2)
);

-- 3. Purchase Orders
CREATE TABLE purchase_orders (
    po_number VARCHAR(50) PRIMARY KEY,
    vendor_id VARCHAR(50),
    item_code VARCHAR(50),
    quantity INTEGER,
    po_rate NUMERIC(12,2),
    po_date DATE
);

-- 4. Invoices
CREATE TABLE invoices (
    invoice_id VARCHAR(50) PRIMARY KEY,
    po_number VARCHAR(50),
    vendor_id VARCHAR(50),
    item_code VARCHAR(50),
    billed_qty INTEGER,
    billed_rate NUMERIC(12,2),
    invoice_amount NUMERIC(15,2),
    invoice_date DATE,
    payment_date DATE,
    injected_error VARCHAR(50)
);

-- SECTION 2: TABLE EXISTENCE VALIDATION

SELECT
    table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
      'vendors',
      'contracts',
      'purchase_orders',
      'invoices'
  )
ORDER BY table_name;

-- SECTION 3: DATA IMPORT VALIDATION

SELECT 'vendors' AS table_name, COUNT(*) AS total_rows
FROM vendors

UNION ALL

SELECT 'contracts', COUNT(*)
FROM contracts

UNION ALL

SELECT 'purchase_orders', COUNT(*)
FROM purchase_orders

UNION ALL

SELECT 'invoices', COUNT(*)
FROM invoices;
