
-- =========================================================
-- PROJECT: Invoice & Billing Discrepancy Detector
-- FILE: 04_financial_analysis.sql
-- SECTION 1: DUPLICATE BILLING FINANCIAL EXPOSURE
-- =========================================================

-- OBJECTIVE:
-- Calculate the billed value of additional invoice
-- occurrences with identical billing details.
--
-- BUSINESS PURPOSE:
-- Estimate potential duplicate billing exposure.
--
-- INNER JOIN:
-- Include only invoices referencing existing POs.
--
-- ROW_NUMBER():
-- Assign a sequence within each matching billing group.
-- Rank 1 = first occurrence.
-- Rank > 1 = additional potential duplicate.
--
-- IMPORTANT:
-- This is potential billing exposure, not confirmed
-- duplicate payment or financial loss.

WITH duplicate_check AS (
    SELECT
        i.invoice_id,
        i.po_number,
        i.vendor_id,
        i.item_code,
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

SELECT
    COUNT(*) AS duplicate_invoices,

    COALESCE(SUM(invoice_amount), 0)
        AS potential_duplicate_exposure

FROM duplicate_check

WHERE duplicate_rank > 1;

