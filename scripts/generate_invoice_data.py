"""
Synthetic data generator for the Invoice & Billing Discrepancy Detector project.
Creates 4 CSVs: vendors, contracts, purchase_orders, invoices.
Errors are injected on purpose and logged in invoices.csv (injected_error)
so you can later measure how well your SQL/Python checks catch them.

Run:  pip install pandas numpy
      python generate_invoice_data.py
"""
import numpy as np
import pandas as pd

rng = np.random.default_rng(42)
N_VENDORS, N_ITEMS, N_PO, N_INV = 40, 25, 30000, 30000

# ---------- vendors ----------
vendors = pd.DataFrame({
    "vendor_id": [f"V{i:03d}" for i in range(1, N_VENDORS + 1)],
    "vendor_name": [f"Vendor_{i:03d}" for i in range(1, N_VENDORS + 1)],
    "category": rng.choice(["Logistics", "IT Services", "Facilities", "Raw Material", "Consulting"], N_VENDORS),
    "payment_terms_days": rng.choice([30, 45, 60], N_VENDORS),
})

# ---------- contracts (agreed unit rate per vendor + item) ----------
rows = []
for v in vendors.vendor_id:
    for item in rng.choice(N_ITEMS, size=8, replace=False):
        rows.append({
            "vendor_id": v,
            "item_code": f"ITM{item:03d}",
            "contract_rate": round(float(rng.uniform(100, 5000)), 2),
        })
contracts = pd.DataFrame(rows)

# ---------- purchase orders ----------
po = contracts.sample(N_PO, replace=True, random_state=1).reset_index(drop=True)
po["po_number"] = [f"PO{100000 + i}" for i in range(N_PO)]
po["quantity"] = rng.integers(1, 200, N_PO)
po["po_date"] = pd.to_datetime("2025-01-01") + pd.to_timedelta(rng.integers(0, 600, N_PO), unit="D")
po = po[["po_number", "vendor_id", "item_code", "quantity", "contract_rate", "po_date"]]
po = po.rename(columns={"contract_rate": "po_rate"})

# ---------- invoices (clean first, then inject errors) ----------
inv = po.sample(N_INV, random_state=2).reset_index(drop=True)
inv["invoice_id"] = [f"INV{500000 + i}" for i in range(N_INV)]
inv["invoice_date"] = inv["po_date"] + pd.to_timedelta(rng.integers(5, 40, N_INV), unit="D")
inv["billed_rate"] = inv["po_rate"]
inv["billed_qty"] = inv["quantity"]
inv["injected_error"] = "none"

idx = rng.permutation(N_INV)
n = lambda p: int(N_INV * p)
a, b, c, d = n(0.04), n(0.03), n(0.02), n(0.02)

# 1) rate mismatch: billed above contract rate (4%)
i1 = idx[:a]
inv.loc[i1, "billed_rate"] = (inv.loc[i1, "po_rate"] * rng.uniform(1.05, 1.25, a)).round(2)
inv.loc[i1, "injected_error"] = "rate_mismatch"

# 2) quantity mismatch: billed more than ordered (3%)
i2 = idx[a:a + b]
inv.loc[i2, "billed_qty"] = inv.loc[i2, "quantity"] + rng.integers(1, 20, b)
inv.loc[i2, "injected_error"] = "qty_mismatch"

# 3) missing PO reference (2%)
i3 = idx[a + b:a + b + c]
inv.loc[i3, "po_number"] = None
inv.loc[i3, "injected_error"] = "missing_po"

inv["invoice_amount"] = (inv["billed_rate"] * inv["billed_qty"]).round(2)

# 4) duplicates: re-submit existing invoices with a new invoice_id (2%)
dups = inv[inv.injected_error == "none"].sample(d, random_state=3).copy()
dups["invoice_id"] = [f"INV{900000 + i}" for i in range(d)]
dups["invoice_date"] = dups["invoice_date"] + pd.to_timedelta(rng.integers(1, 15, d), unit="D")
dups["injected_error"] = "duplicate"
inv = pd.concat([inv, dups], ignore_index=True)

# payment date (some late vs terms)
terms = inv["vendor_id"].map(vendors.set_index("vendor_id")["payment_terms_days"])
inv["payment_date"] = inv["invoice_date"] + pd.to_timedelta(terms + rng.integers(-10, 25, len(inv)), unit="D")

invoices = inv[["invoice_id", "po_number", "vendor_id", "item_code", "billed_qty",
                "billed_rate", "invoice_amount", "invoice_date", "payment_date", "injected_error"]]

vendors.to_csv("vendors.csv", index=False)
contracts.to_csv("contracts.csv", index=False)
po.to_csv("purchase_orders.csv", index=False)
invoices.to_csv("invoices.csv", index=False)

print("vendors", len(vendors), "| contracts", len(contracts), "| POs", len(po), "| invoices", len(invoices))
print(invoices.injected_error.value_counts())
