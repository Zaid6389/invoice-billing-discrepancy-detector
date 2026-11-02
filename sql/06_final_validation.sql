
-- =========================================================
-- PROJECT: INVOICE & BILLING DISCREPANCY DETECTOR
-- FILE: 06_final_validation.sql
-- SECTION 1: OVERALL DETECTION ACCURACY
-- =========================================================

WITH validation AS (
    SELECT
        i.invoice_id,
        i.injected_error,

        CASE
            WHEN i.injected_error <> 'none'
            THEN 1 ELSE 0
        END AS actual_error,

        CASE
            WHEN a.po_status <> 'Valid PO'
              OR a.rate_mismatch_flag = 1
              OR a.qty_mismatch_flag = 1
              OR a.duplicate_flag = 1
            THEN 1 ELSE 0
        END AS detected_error

    FROM invoices i
    INNER JOIN vw_invoice_audit a
        ON i.invoice_id = a.invoice_id
),

confusion_matrix AS (
    SELECT
        COUNT(*) FILTER (
            WHERE actual_error = 1
              AND detected_error = 1
        ) AS true_positive,

        COUNT(*) FILTER (
            WHERE actual_error = 0
              AND detected_error = 1
        ) AS false_positive,

        COUNT(*) FILTER (
            WHERE actual_error = 1
              AND detected_error = 0
        ) AS false_negative,

        COUNT(*) FILTER (
            WHERE actual_error = 0
              AND detected_error = 0
        ) AS true_negative

    FROM validation
)

SELECT
    true_positive,
    false_positive,
    false_negative,
    true_negative,

    ROUND(
        100.0 * (true_positive + true_negative)
        / NULLIF(
            true_positive + false_positive
            + false_negative + true_negative, 0
        ), 2
    ) AS accuracy_pct,

    ROUND(
        100.0 * true_positive
        / NULLIF(true_positive + false_positive, 0), 2
    ) AS precision_pct,

    ROUND(
        100.0 * true_positive
        / NULLIF(true_positive + false_negative, 0), 2
    ) AS recall_pct

FROM confusion_matrix;


-- =========================================================
-- SECTION 2: ERROR CATEGORY VALIDATION
-- Compare injected labels with detected discrepancy types.
-- =========================================================

WITH category_validation AS (
    SELECT
        i.invoice_id,
        i.injected_error AS actual_category,

        CASE
            WHEN a.po_status = 'Missing PO'
                THEN 'missing_po'
            WHEN a.po_status = 'Invalid PO'
                THEN 'invalid_po'
            WHEN a.rate_mismatch_flag = 1
                THEN 'rate_mismatch'
            WHEN a.qty_mismatch_flag = 1
                THEN 'qty_mismatch'
            WHEN a.duplicate_flag = 1
                THEN 'duplicate'
            ELSE 'none'
        END AS detected_category

    FROM invoices i
    INNER JOIN vw_invoice_audit a
        ON i.invoice_id = a.invoice_id
)

SELECT
    actual_category,
    detected_category,
    COUNT(*) AS invoice_count
FROM category_validation
GROUP BY actual_category, detected_category
ORDER BY actual_category, detected_category;


-- =========================================================
-- SECTION 3: CONTRACT-RATE RECONCILIATION
-- Check contract key uniqueness before joining.
-- =========================================================

SELECT
    vendor_id,
    item_code,
    COUNT(*) AS contract_count
FROM contracts
GROUP BY vendor_id, item_code
HAVING COUNT(*) > 1;

-- =========================================================
-- Compare PO rates against agreed contract rates.
-- =========================================================

SELECT
    COUNT(*) AS total_purchase_orders,

    COUNT(*) FILTER (
        WHERE c.vendor_id IS NULL
    ) AS missing_contracts,

    COUNT(*) FILTER (
        WHERE c.vendor_id IS NOT NULL
          AND po.po_rate IS DISTINCT FROM c.contract_rate
    ) AS contract_rate_mismatches,

    COUNT(*) FILTER (
        WHERE c.vendor_id IS NOT NULL
          AND po.po_rate = c.contract_rate
    ) AS matching_contract_rates

FROM purchase_orders po
LEFT JOIN contracts c
    ON po.vendor_id = c.vendor_id
   AND po.item_code = c.item_code;

--Contract validation, to check no duplicate.
SELECT
    vendor_id,
    item_code,
    COUNT(*) AS contract_count
FROM contracts
GROUP BY vendor_id, item_code
HAVING COUNT(*) > 1;


-- =========================================================
-- SECTION 4: FINAL FINANCIAL RECONCILIATION
-- Verify total financial exposure across categories.
-- =========================================================

SELECT
    rate_qty_overbilling,
    duplicate_exposure,
    missing_po_exposure,

    rate_qty_overbilling
      + duplicate_exposure
      + missing_po_exposure
        AS total_flagged_financial_value

FROM vw_financial_audit_summary;
