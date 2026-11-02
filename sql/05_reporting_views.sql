
-- =========================================================
-- PROJECT: Invoice & Billing Discrepancy Detector
-- FILE: 05_reporting_views.sql
-- SECTION 1: VENDOR-LEVEL AUDIT SUMMARY
-- =========================================================

-- OBJECTIVE:
-- Summarize invoice discrepancies for each vendor.
--
-- BUSINESS PURPOSE:
-- Identify vendors with high exception counts
-- and prioritize invoices for investigation.
--
-- NOTE:
-- An invoice may have more than one audit flag.
-- Exception counts should not be summed to calculate
-- the number of unique flagged invoices.

CREATE OR REPLACE VIEW vw_vendor_audit_summary AS

SELECT
    v.vendor_id,
    v.vendor_name,
    v.category,

    COUNT(a.invoice_id) AS total_invoices,

    COUNT(a.invoice_id) FILTER (
        WHERE a.po_status = 'Missing PO'
    ) AS missing_po_count,

    COUNT(a.invoice_id) FILTER (
        WHERE a.po_status = 'Invalid PO'
    ) AS invalid_po_count,

    COUNT(a.invoice_id) FILTER (
        WHERE a.rate_mismatch_flag = 1
    ) AS rate_mismatch_count,

    COUNT(a.invoice_id) FILTER (
        WHERE a.qty_mismatch_flag = 1
    ) AS qty_mismatch_count,

    COUNT(a.invoice_id) FILTER (
        WHERE a.duplicate_flag = 1
    ) AS duplicate_count,

    COUNT(a.invoice_id) FILTER (
        WHERE a.po_status <> 'Valid PO'
           OR a.rate_mismatch_flag = 1
           OR a.qty_mismatch_flag = 1
           OR a.duplicate_flag = 1
    ) AS flagged_invoices,

    COALESCE(SUM(a.invoice_amount), 0)
        AS total_billed_amount

FROM vendors AS v

LEFT JOIN vw_invoice_audit AS a
    ON v.vendor_id = a.vendor_id

GROUP BY
    v.vendor_id,
    v.vendor_name,
    v.category;

-- =========================================================
-- SECTION 2: VENDOR SUMMARY VALIDATION
-- =========================================================

-- OBJECTIVE:
-- Verify vendor count and total invoice coverage.

SELECT
    COUNT(*) AS total_vendors,
    SUM(total_invoices) AS total_invoices,
    SUM(flagged_invoices) AS flagged_invoices
FROM vw_vendor_audit_summary;
