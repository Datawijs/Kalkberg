
"""Run all generation steps and write the raw exports."""
import time

import numpy as np
import pandas as pd

from . import ads, budget, ga4, sfmc, shop
from . import config as C
from .calendar_model import Calendar


def _ts_text(values):
    """Timestamps as 'YYYY-MM-DD HH:MM:SS' (empty for missing)."""
    s = pd.Series(pd.to_datetime(values)).dt.round("s")
    return s.dt.strftime("%Y-%m-%d %H:%M:%S").where(s.notna(), None).to_numpy()


def _stored_time(local, migration=C.PLATFORM_MIGRATION):
    """Legacy platform stored local time, the new platform stores UTC."""
    from .calendar_model import local_to_utc
    local = pd.to_datetime(pd.Series(local))
    utc = pd.Series(local_to_utc(local.fillna(C.START)))
    return local.where(local < migration, utc).where(local.notna())


def write_csv(df, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(path, index=False, encoding="utf-8", lineterminator="\n")
    print(f"  {path.relative_to(C.OUTPUT_DIR)}: {len(df):,} rows")


def run(out_dir=C.OUTPUT_DIR):
    t0 = time.time()
    rng = np.random.default_rng(C.SEED)
    cal = Calendar()

    print("Webshop ...")
    categories, brands, products, variants = shop.build_catalog(rng, cal)
    cust = shop.build_customers(rng, cal)
    cust, orders, lines, returns = shop.build_orders(rng, cal, cust, products, variants)
    n_lines = lines.groupby("_oi").size().reindex(range(len(orders)), fill_value=1).to_numpy()

    print("SFMC broadcasts ...")
    subs = sfmc.build_subscribers(rng, cal, cust)
    bc_out, sub_state = sfmc.simulate_broadcasts(rng, subs)

    print("GA4 ...")
    events, daily, ads_sessions, known_abandons, forced = ga4.build_ga4(
        rng, cal, orders, cust, subs, sub_state, bc_out, products, n_lines)

    print("SFMC journeys ...")
    tr_out = sfmc.simulate_triggered(rng, subs, sub_state, orders, cust, known_abandons, forced)
    views = sfmc.to_data_views(rng, subs, sub_state, bc_out, tr_out)

    print("Ads ...")
    google, g_spend = ads.build_google(rng, cal, ads_sessions)
    meta, m_spend = ads.build_meta(rng, cal, ads_sessions)

    print("Writing files ...")
    C.OUTPUT_DIR = out_dir
    shop_dir, ga_dir, sf_dir, ad_dir, bu_dir = (out_dir / d for d in ("shop", "ga4", "sfmc", "ads", "budget"))

    write_csv(categories, shop_dir / "categories.csv")
    write_csv(brands, shop_dir / "brands.csv")
    write_csv(products[["product_id", "product_name", "brand_id", "category_id", "launched_at", "discontinued_at", "is_active"]],
              shop_dir / "products.csv")
    write_csv(variants[["variant_id", "product_id", "sku", "size_label", "list_price", "unit_cost"]], shop_dir / "product_variants.csv")

    c = cust.copy()
    c["created_at"] = _ts_text(_stored_time(c._created))
    c = c.sort_values("customer_id")
    write_csv(c[["customer_id", "email", "first_name", "last_name", "phone", "birth_date", "preferred_language",
                 "postal_code", "city", "country_code", "marketing_opt_in", "created_at"]], shop_dir / "customers.csv")

    o = orders.copy()
    o["created_at"] = _ts_text(o.created_at)
    o["guest_email"] = o.get("guest_email")
    write_csv(o[["order_id", "order_number", "customer_id", "guest_email", "created_at", "status", "currency", "subtotal",
                 "discount_total", "shipping_fee", "order_total", "discount_code", "payment_method", "shipping_country",
                 "shipping_postal_code", "shipping_city"]], shop_dir / "orders.csv")

    lines = lines.reset_index(drop=True)
    lines["order_line_id"] = np.arange(1, len(lines) + 1)
    lines["order_id"] = orders.order_id.to_numpy()[lines._oi]
    write_csv(lines[["order_line_id", "order_id", "variant_id", "quantity", "unit_price", "discount_amount", "line_total"]],
              shop_dir / "order_lines.csv")
    r = returns.copy()
    r["order_line_id"] = lines.order_line_id.to_numpy()[r._line_row]
    r["requested_at"] = _ts_text(_stored_time(r.requested_at))
    r["received_at"] = _ts_text(_stored_time(r.received_at))
    write_csv(r[["return_id", "order_line_id", "requested_at", "received_at", "quantity", "reason", "status", "refund_amount"]],
              shop_dir / "returns.csv")

    write_csv(events, ga_dir / "events.csv")
    write_csv(daily, ga_dir / "daily_traffic.csv")

    for name, df in views.items():
        write_csv(df, sf_dir / f"{name}.csv")

    write_csv(google, ad_dir / "google_ads_campaign_report.csv")
    write_csv(meta, ad_dir / "meta_ads_report.csv")

    act = budget.monthly_actuals(g_spend, m_spend, ads_sessions, cal)
    paid = orders[~orders._test & (orders.status != "cancelled")]
    rev = paid.groupby(paid._ts_local.dt.to_period("M")).order_total.sum()
    for m in pd.period_range("2026-11", "2026-12", freq="M"):
        rev.loc[m] = rev.loc[m - 12] * 1.15
    bu_dir.mkdir(parents=True, exist_ok=True)
    budget.build_workbook(rng, act, rev.sort_index(), bu_dir / "marketing_budget.xlsx")
    print("  budget/marketing_budget.xlsx")
    print(f"Done in {time.time() - t0:.0f} s")