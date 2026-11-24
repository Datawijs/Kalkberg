"""Marketing budget workbook, maintained by hand by the marketing manager (so: messy)."""
import numpy as np
import pandas as pd
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill

from . import reference as R

CHANNELS = ["SEA (Google Ads)", "Paid Social (Meta)", "Influencers", "Affiliates (commission est.)",
            "Email (SFMC licence)", "SEO / content agency"]
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def _round(x, step=250):
    return float(np.round(x / step) * step)


def monthly_actuals(google_spend, meta_spend, ads_sessions, cal):
    """Approximate monthly cost per channel (used to make a realistic plan)."""
    months = pd.period_range("2023-11", "2026-12", freq="M")
    act = pd.DataFrame(index=months, columns=CHANNELS, dtype=float).fillna(0.0)
    act[CHANNELS[0]] = google_spend.reindex(months).fillna(0)
    act[CHANNELS[1]] = meta_spend.reindex(months).fillna(0)
    for _h, _p, _c, s, e, fee in R.CREATORS:
        for m in pd.period_range(pd.Timestamp(s).to_period("M"), pd.Timestamp(e).to_period("M"), freq="M"):
            if m in act.index:
                act.loc[m, CHANNELS[2]] += fee
    aff = ads_sessions[ads_sessions.ckey.str.startswith("A:")].copy()
    aff["month"] = cal.days[aff.day.to_numpy()].to_period("M")
    act[CHANNELS[3]] = (aff.groupby("month").revenue.sum() / 0.82 * R.AFFILIATE_COMMISSION).reindex(months).fillna(0)
    act[CHANNELS[4]] = 2950.0
    act[CHANNELS[5]] = np.where(months >= pd.Period("2024-04", "M"), 3500.0, 0.0)
    # Months after the data period: last year's value + 15%
    for m in pd.period_range("2026-11", "2026-12", freq="M"):
        act.loc[m, CHANNELS[:4]] = act.loc[m - 12, CHANNELS[:4]] * 1.15
    return act


def build_workbook(rng, act, revenue_by_month, path):
    wb = Workbook()
    wb.remove(wb.active)
    bold = Font(bold=True)
    head_fill = PatternFill("solid", fgColor="DDEBF7")
    for year in (2023, 2024, 2025, 2026):
        ws = wb.create_sheet(f"Budget {year}")
        ws["A1"] = f"Kalkberg - Marketing budget {year} (EUR)"
        ws["A1"].font = Font(bold=True, size=14)
        ws.merge_cells("A1:O1")
        updated = "2023-10-20" if year == 2023 else f"{year - 1}-12-1{year % 7}"
        ws["A2"] = f"Owner: Marketing | Version: {'v3 FINAL' if year < 2026 else 'v2'} | Last update: {updated}"
        header = ["Channel"] + MONTHS + ["FY total", "Notes"]
        if year == 2026:
            header = ["Channel"] + [pd.Timestamp(year=year, month=m, day=1) for m in range(1, 13)] + ["FY total", "Notes"]
        for j, h in enumerate(header, start=1):
            c = ws.cell(row=4, column=j, value=h)
            c.font, c.fill = bold, head_fill
            if isinstance(h, pd.Timestamp):
                c.number_format = "mmm-yy"
        r = 5
        totals = np.zeros(12)
        for ch in CHANNELS:
            ws.cell(row=r, column=1, value=ch)
            vals = []
            for m in range(1, 13):
                p = pd.Period(year=year, month=m, freq="M")
                if p not in act.index:
                    ws.cell(row=r, column=m + 1, value="-")
                    vals.append(0)
                    continue
                a = act.loc[p, ch]
                factor = rng.uniform(0.85, 1.15)
                if ch in CHANNELS[:2] and m == 11:
                    factor = rng.uniform(0.7, 0.85)          # Black Friday is always under-budgeted
                v = _round(a * factor) if ch not in CHANNELS[4:] else a
                vals.append(v)
                cell_value = v
                if year == 2024 and rng.random() < 0.08:
                    cell_value = f"€ {v:,.0f}".replace(",", ".")     # typed as text, Belgian notation
                ws.cell(row=r, column=m + 1, value=cell_value)
            totals += np.array(vals)
            ws.cell(row=r, column=14, value=float(sum(vals)))
            note = {"SEA (Google Ads)": "incl. Black Friday search" if year > 2023 else "launch campaign",
                    "Paid Social (Meta)": "new agency from Feb 2025" if year == 2025 else None,
                    "Affiliates (commission est.)": "8% on sales via affiliates",
                    "Influencers": "see tab Influencer contracts",
                    "SEO / content agency": "contract started April 2024" if year == 2024 else None}.get(ch)
            ws.cell(row=r, column=15, value=note)
            r += 1
        if year == 2025:
            # mid-year revision of the Meta budget, added as an extra row
            ws.cell(row=r, column=1, value="Paid Social (Meta) - REVISED Q4")
            for m in (10, 11, 12):
                ws.cell(row=r, column=m + 1, value=_round(act.loc[pd.Period(year=2025, month=m, freq="M"), CHANNELS[1]] * 1.05))
            ws.cell(row=r, column=15, value="replaces original Q4 values above (approved by CFO in Sept)")
            r += 1
        r += 1
        ws.cell(row=r, column=1, value="TOTAL").font = bold
        for m in range(12):
            ws.cell(row=r, column=m + 2, value=float(totals[m])).font = bold
        ws.cell(row=r, column=14, value=float(totals.sum())).font = bold
        ws.column_dimensions["A"].width = 34
        ws.column_dimensions["O"].width = 50

    # Targets
    ws = wb.create_sheet("Targets")
    ws.append(["Month", "Revenue target (EUR)", "New customers target", "Comment"])
    for c in ws[1]:
        c.font, c.fill = bold, head_fill
    for p, rev in revenue_by_month.items():
        ws.append([p.to_timestamp().to_pydatetime(), _round(rev * rng.uniform(0.92, 1.12), 1000),
                   int(_round(rev / 110 * 0.32 * rng.uniform(0.9, 1.15), 10)),
                   "stretch target" if p.month == 11 else None])
        ws.cell(row=ws.max_row, column=1).number_format = "yyyy-mm-dd"
    ws.column_dimensions["A"].width = 14

    # Influencer contracts
    ws = wb.create_sheet("Influencer contracts")
    ws.append(["Creator", "Platform", "Discount code", "Start", "End", "Monthly fee (EUR)", "Remarks"])
    for c in ws[1]:
        c.font, c.fill = bold, head_fill
    for h, platform, code, s, e, fee in R.CREATORS:
        ws.append([h, platform, code, pd.Timestamp(s).to_pydatetime(), pd.Timestamp(e).to_pydatetime(), fee,
                   "code valid 14 days after contract end"])
        for col in (4, 5):
            ws.cell(row=ws.max_row, column=col).number_format = "dd/mm/yyyy"
    for col in "ABCDEFG":
        ws.column_dimensions[col].width = 18
    for row in wb["Influencer contracts"].iter_rows():
        for c in row:
            c.alignment = Alignment(vertical="top")
    wb.save(path)
