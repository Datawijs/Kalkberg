"""Google Ads and Meta Ads exports, derived from the paid traffic GA4 saw (so spend and traffic agree)."""
import numpy as np
import pandas as pd

from . import reference as R
from .calendar_model import BLACK_FRIDAYS
from .ga4 import CONSENT_RATE


def _fmt_num(x, decimals=0):
    """'1,234.56' style text, like a Google Ads UI download."""
    return [f"{v:,.{decimals}f}" for v in x]


def _lookup(ads_sessions, prefix, name, days):
    sub = ads_sessions[ads_sessions.ckey == prefix + name].set_index("day")
    return (sub.sessions.reindex(days, fill_value=0).to_numpy(),
            sub.final_purchase.reindex(days, fill_value=0).to_numpy(),
            sub.revenue.reindex(days, fill_value=0).to_numpy())


def _bf_factor(dates):
    f = np.ones(len(dates))
    for bf in BLACK_FRIDAYS:
        f[(dates >= bf - pd.Timedelta(days=7)) & (dates <= bf + pd.Timedelta(days=3))] = 1.35
    return f


def build_google(rng, cal, ads_sessions):
    rows = []
    for name, ctype, s, e, ctr, cpc in R.GOOGLE_CAMPAIGNS:
        days = np.arange(cal.idx([pd.Timestamp(s)])[0], cal.idx([pd.Timestamp(e)])[0] + 1)
        dates = cal.days[days]
        sess, purch, rev = _lookup(ads_sessions, "G:", name, days)
        k = len(days)
        clicks = np.round(sess / CONSENT_RATE * rng.lognormal(0, 0.06, k)).astype(int)
        impr = np.round(clicks / (ctr * rng.lognormal(0, 0.12, k))).astype(int)
        cost = np.round(clicks * cpc * rng.lognormal(0, 0.08, k) * _bf_factor(dates), 2)
        conv = np.round(purch / CONSENT_RATE * rng.uniform(1.0, 1.25, k), 2)
        value = np.round(rev / CONSENT_RATE * rng.uniform(1.0, 1.25, k), 2)
        rows.append(pd.DataFrame({"Day": dates.strftime("%Y-%m-%d"), "Campaign": name, "Campaign type": ctype,
                                  "_cost": cost, "_impr": impr, "_clicks": clicks, "_conv": conv, "_value": value}))
    g = pd.concat(rows, ignore_index=True)
    g = g[g._impr > 0].sort_values(["Day", "Campaign"]).reset_index(drop=True)
    totals = [("Total: Account", g)] + [(f"Total: {t}", g[g["Campaign type"] == t]) for t in g["Campaign type"].unique()]
    tot = pd.DataFrame([{"Day": lbl, "Campaign": "--", "Campaign type": "--", "_cost": d._cost.sum(), "_impr": d._impr.sum(),
                         "_clicks": d._clicks.sum(), "_conv": d._conv.sum(), "_value": d._value.sum()} for lbl, d in totals])
    out = pd.concat([g, tot], ignore_index=True)
    export = pd.DataFrame({
        "Day": out.Day, "Campaign": out.Campaign, "Campaign type": out["Campaign type"], "Currency code": "EUR",
        "Cost": _fmt_num(out._cost, 2), "Impr.": _fmt_num(out._impr), "Clicks": _fmt_num(out._clicks),
        "Conversions": _fmt_num(out._conv, 2), "Conv. value": _fmt_num(out._value, 2)})
    spend = g.assign(month=pd.to_datetime(g.Day).dt.to_period("M")).groupby("month")._cost.sum()
    return export, spend


def build_meta(rng, cal, ads_sessions):
    rows = []
    for name, s, e, adsets in R.META_CAMPAIGNS:
        days = np.arange(cal.idx([pd.Timestamp(s)])[0], cal.idx([pd.Timestamp(e)])[0] + 1)
        dates = cal.days[days]
        sess, purch, rev = _lookup(ads_sessions, "M:", name, days)
        k = len(days)
        clicks = sess / CONSENT_RATE * rng.lognormal(0, 0.06, k)
        share = rng.dirichlet(np.ones(len(adsets)) * 3)
        retarget = "Retargeting" in name or "Sale" in name
        for j, adset in enumerate(adsets):
            sh = share[j] * rng.lognormal(0, 0.1, k)
            c = np.round(clicks * sh).astype(int)
            ctr = rng.uniform(0.014, 0.02, k) if retarget else rng.uniform(0.008, 0.013, k)
            impr = np.round(c / ctr).astype(int)
            cpm = (rng.uniform(9, 14, k) if retarget else rng.uniform(5.5, 9.5, k)) * _bf_factor(dates)
            spend = np.round(impr / 1000 * cpm, 2)
            reach = np.round(impr / rng.uniform(1.2, 1.9, k)).astype(int)
            p = np.round(purch / CONSENT_RATE * sh * rng.uniform(1.6, 2.4, k)).astype(int)
            v = np.round(rev / CONSENT_RATE * sh * rng.uniform(1.6, 2.4, k), 2)
            rows.append(pd.DataFrame({"Reporting starts": dates.strftime("%Y-%m-%d"), "Reporting ends": dates.strftime("%Y-%m-%d"),
                                      "Campaign name": name, "Ad set name": adset, "Amount spent (EUR)": spend,
                                      "Impressions": impr, "Reach": reach, "Link clicks": c, "Purchases": p,
                                      "Purchases conversion value": v}))
    m = pd.concat(rows, ignore_index=True)
    m = m[m.Impressions > 0].sort_values(["Reporting starts", "Campaign name", "Ad set name"]).reset_index(drop=True)
    spend = m.assign(month=pd.to_datetime(m["Reporting starts"]).dt.to_period("M")).groupby("month")["Amount spent (EUR)"].sum()
    export = m.copy()
    for c in ("Link clicks", "Purchases"):
        export[c] = export[c].astype("Int64").mask(export[c] == 0)      # Meta leaves empty cells instead of zeros
    export["Purchases conversion value"] = export["Purchases conversion value"].mask(export["Purchases conversion value"] == 0)
    return export, spend
