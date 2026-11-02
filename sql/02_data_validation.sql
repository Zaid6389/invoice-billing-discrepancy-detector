-- 02_data_validation.sql
-- OBJECTIVE:
-- Classify every invoice according to its PO reference:
-- 1. Missing PO: No PO number provided
-- 2. Invalid PO: PO number not found in purchase_orders
-- 3. Valid PO: Matching purchase order exists

SELECT
    i.invoice_id,
    i.po_number,
    i.vendor_id,
    CASE
        WHEN i.po_number IS NULL
          OR TRIM(i.po_number) = ''
        THEN 'Missing PO'

        WHEN po.po_number IS NULL
        THEN 'Invalid PO'

        ELSE 'Valid PO'
    END AS po_status

FROM invoices AS i
LEFT JOIN purchase_orders AS po
    ON i.po_number = po.po_number;


-- SECTION 2: PO REFERENCE VALIDATION SUMMARY

-- OBJECTIVE:
-- Count invoices with valid, missing, or invalid PO numbers.
--
-- Missing PO: PO number is NULL or blank.
-- Invalid PO: PO number exists but is not found in
--             the purchase_orders table.
-- Valid PO: PO number matches an existing purchase order.
--
-- LEFT JOIN ensures all invoices are included.

SELECT
    CASE
        WHEN i.po_number IS NULL
          OR TRIM(i.po_number) = ''
        THEN 'Missing PO'

        WHEN po.po_number IS NULL
        THEN 'Invalid PO'

        ELSE 'Valid PO'
    END AS po_status,

    COUNT(*) AS total_invoices

FROM invoices AS i

LEFT JOIN purchase_orders AS po
    ON i.po_number = po.po_number

GROUP BY 1
ORDER BY total_invoices DESC;

-- SECTION 3: INVOICE RATE RECONCILIATION

-- OBJECTIVE:
-- Identify invoices where the billed rate differs
-- from the approved purchase-order rate.
--
-- BUSINESS PURPOSE:
-- Detect potential overbilling or underbilling.
--
-- INNER JOIN:
-- Only invoices with matching purchase orders are checked.

SELECT
    i.invoice_id,
    i.po_number,
    i.vendor_id,
    i.billed_qty,
    i.billed_rate,
    po.po_rate AS approved_rate,

    i.billed_rate - po.po_rate AS rate_difference,

    (i.billed_rate - po.po_rate) * i.billed_qty
        AS potential_rate_variance

FROM invoices AS i

INNER JOIN purchase_orders AS po
    ON i.po_number = po.po_number

WHERE i.billed_rate <> po.po_rate

ORDER BY potential_rate_variance DESC;

-- SECTION 4: INVOICE QUANTITY RECONCILIATION

-- OBJECTIVE:
-- Identify invoices where billed quantity differs
-- from the approved purchase-order quantity.
--
-- BUSINESS PURPOSE:
-- Detect potential overbilling or underbilling caused
-- by quantity discrepancies.
--
-- INNER JOIN:
-- Compare only invoices with matching purchase orders.
--
-- NOTE:
-- Assumes each invoice represents the full PO quantity.
-- Partial deliveries or multiple legitimate invoices
-- against one PO require separate business rules.

SELECT
    i.invoice_id,
    i.po_number,
    i.vendor_id,
    i.billed_qty,
    po.quantity AS approved_qty,

    i.billed_qty - po.quantity AS qty_difference,

    (i.billed_qty - po.quantity) * po.po_rate
        AS potential_qty_variance

FROM invoices AS i

INNER JOIN purchase_orders AS po
    ON i.po_number = po.po_number

WHERE i.billed_qty <> po.quantity

ORDER BY potential_qty_variance DESC;

-- SECTION 5: DUPLICATE BILLING DETECTION

-- OBJECTIVE:
-- Identify invoices with identical billing details,
-- even when their invoice IDs are different.
--
-- BUSINESS PURPOSE:
-- Detect possible repeated billing for the same
-- purchase order, vendor, item, quantity and amount.
--
-- ROW_NUMBER():
-- Assigns a sequence number within each matching
-- group of billing records.
--
-- The first record is treated as the original
-- occurrence; subsequent records are flagged.
--
-- NOTE:
-- The first record is not necessarily the true
-- original invoice without additional evidence.

WITH duplicate_check AS (
    SELECT
        invoice_id,
        po_number,
        vendor_id,
        item_code,
        billed_qty,
        billed_rate,
        invoice_amount,

        ROW_NUMBER() OVER (
            PARTITION BY
                po_number,
                vendor_id,
                item_code,
                billed_qty,
                billed_rate,
                invoice_amount
            ORDER BY invoice_date, invoice_id
        ) AS duplicate_rank

    FROM invoices
)

SELECT
    invoice_id,
    po_number,
    vendor_id,
    item_code,
    billed_qty,
    billed_rate,
    invoice_amount,
    duplicate_rank

FROM duplicate_check

WHERE duplicate_rank > 1

ORDER BY po_number, duplicate_rank;

-- SECTION 6: REFINED DUPLICATE BILLING DETECTION

-- OBJECTIVE:
-- Detect repeated billing against valid purchase orders.
--
-- Exclude missing or invalid PO references because
-- their billing identity cannot be reliably verified.
--
-- NOTE:
-- This is a conservative detection rule.
-- Missing-PO invoices may still contain real duplicates.

WITH duplicate_check AS (
    SELECT
        i.invoice_id,
        i.po_number,
        i.vendor_id,
        i.item_code,
        i.billed_qty,
        i.billed_rate,
        i.invoice_amount,

        ROW_NUMBER() OVER (
            PARTITION BY
                i.po_number,
                i.vendor_id,
                i.item_code,
                i.billed_qty,
                i.billed_rate,
                i.invoice_amount
            ORDER BY i.invoice_date, i.invoice_id
        ) AS duplicate_rank

    FROM invoices AS i

    INNER JOIN purchase_orders AS po
        ON i.po_number = po.po_number
)

SELECT *
FROM duplicate_check
WHERE duplicate_rank > 1;

-- SECTION 7: RATE AND QUANTITY MISMATCH OVERLAP

-- OBJECTIVE:
-- Identify invoices with both rate and quantity mismatches.
--
-- BUSINESS PURPOSE:
-- Avoid double-counting financial exposure when
-- calculating total billing discrepancies.

SELECT
    COUNT(*) AS overlapping_invoices

FROM invoices AS i

INNER JOIN purchase_orders AS po
    ON i.po_number = po.po_number

WHERE i.billed_rate <> po.po_rate
  AND i.billed_qty <> po.quantity;

-- SECTION 8: FINANCIAL VARIANCE ANALYSIS

-- OBJECTIVE:
-- Calculate potential overbilling and underbilling
-- caused by rate and quantity discrepancies.
--
-- BUSINESS PURPOSE:
-- Quantify the financial impact of invoice mismatches.
--
-- IMPORTANT:
-- Excludes invoices without matching purchase orders.
-- Duplicate billing exposure will be calculated separately.

WITH invoice_variance AS (
    SELECT
        i.invoice_id,
        i.invoice_amount,

        po.quantity * po.po_rate AS approved_amount,

        i.invoice_amount
          - (po.quantity * po.po_rate) AS variance_amount

    FROM invoices AS i

    INNER JOIN purchase_orders AS po
        ON i.po_number = po.po_number

    WHERE i.billed_rate <> po.po_rate
       OR i.billed_qty <> po.quantity
)

SELECT
    COUNT(*) AS discrepant_invoices,

    SUM(
        CASE
            WHEN variance_amount > 0 THEN variance_amount
            ELSE 0
        END
    ) AS potential_overbilling,

    SUM(
        CASE
            WHEN variance_amount < 0 THEN ABS(variance_amount)
            ELSE 0
        END
    ) AS potential_underbilling,

    SUM(variance_amount) AS net_variance

FROM invoice_variance;


-- =========================================================
-- SECTION 9: VENDOR AND ITEM CONSISTENCY VALIDATION
-- =========================================================

-- OBJECTIVE:
-- Verify that invoice vendor and item identifiers match
-- the corresponding purchase order.
--
-- BUSINESS PURPOSE:
-- Detect invoices referencing a valid PO number but
-- containing inconsistent vendor or item information.
--
-- INNER JOIN:
-- Only invoices with an existing PO are evaluated.
--
-- IS DISTINCT FROM:
-- Performs NULL-safe comparisons in PostgreSQL.

SELECT
    COUNT(*) AS checked_invoices,

    COUNT(*) FILTER (
        WHERE i.vendor_id IS DISTINCT FROM po.vendor_id
    ) AS vendor_mismatches,

    COUNT(*) FILTER (
        WHERE i.item_code IS DISTINCT FROM po.item_code
    ) AS item_mismatches,

    COUNT(*) FILTER (
        WHERE i.vendor_id IS DISTINCT FROM po.vendor_id
           OR i.item_code IS DISTINCT FROM po.item_code
    ) AS total_inconsistent_invoices

FROM invoices AS i

INNER JOIN purchase_orders AS po
    ON i.po_number = po.po_number;
