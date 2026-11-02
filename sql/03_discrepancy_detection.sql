
-- =========================================================
-- PROJECT: Invoice & Billing Discrepancy Detector
-- FILE: 03_discrepancy_detection.sql
-- SECTION 1: CONSOLIDATED INVOICE AUDIT VIEW
-- =========================================================

-- OBJECTIVE:
-- Combine PO validation, rate mismatch, quantity mismatch,
-- and duplicate detection into one reusable SQL view.
--
-- BUSINESS PURPOSE:
-- Provide invoice-level audit flags for Power BI.
--
-- NOTE:
-- injected_error is not used for detection.

CREATE OR REPLACE VIEW vw_invoice_audit AS

WITH invoice_checks AS (
    SELECT
        i.invoice_id,
        i.po_number,
        i.vendor_id,
        i.item_code,
        i.invoice_date,
        i.invoice_amount,
        i.billed_qty,
        i.billed_rate,
        po.quantity AS approved_qty,
        po.po_rate AS approved_rate,

        CASE
            WHEN i.po_number IS NULL
              OR TRIM(i.po_number) = ''
            THEN 'Missing PO'

            WHEN po.po_number IS NULL
            THEN 'Invalid PO'

            ELSE 'Valid PO'
        END AS po_status,

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

    LEFT JOIN purchase_orders AS po
        ON i.po_number = po.po_number
)

SELECT
    invoice_id,
    po_number,
    vendor_id,
    item_code,
    invoice_date,
    invoice_amount,
    billed_qty,
    billed_rate,
    approved_qty,
    approved_rate,
    po_status,

    CASE
        WHEN po_status = 'Valid PO'
         AND billed_rate IS DISTINCT FROM approved_rate
        THEN 1 ELSE 0
    END AS rate_mismatch_flag,

    CASE
        WHEN po_status = 'Valid PO'
         AND billed_qty IS DISTINCT FROM approved_qty
        THEN 1 ELSE 0
    END AS qty_mismatch_flag,

    CASE
        WHEN po_status = 'Valid PO'
         AND duplicate_rank > 1
        THEN 1 ELSE 0
    END AS duplicate_flag,

    CASE
        WHEN po_status = 'Valid PO'
        THEN invoice_amount - (approved_qty * approved_rate)
        ELSE NULL
    END AS billing_variance

FROM invoice_checks;

--Verify the view, now

SELECT
    COUNT(*) AS total_invoices,
    COUNT(*) FILTER (
        WHERE po_status = 'Missing PO'
    ) AS missing_po,
    COUNT(*) FILTER (
        WHERE rate_mismatch_flag = 1
    ) AS rate_mismatches,
    COUNT(*) FILTER (
        WHERE qty_mismatch_flag = 1
    ) AS qty_mismatches,
    COUNT(*) FILTER (
        WHERE duplicate_flag = 1
    ) AS duplicates
FROM vw_invoice_audit;
