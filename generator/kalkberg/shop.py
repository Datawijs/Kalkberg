"""Webshop (OLTP) data: catalog, customers, orders, order lines, returns.

Functions return public tables (written to CSV) and hidden "truth" columns
(prefixed with '_') that later steps use to keep GA4/SFMC/ads consistent.
"""
import unicodedata

import numpy as np
import pandas as pd

from . import config as C
from . import reference as R
from .calendar_model import local_to_utc, sample_time_of_day

CAT_NAMES = [c[0] for c in R.CATEGORIES]
CAT_INDEX = {n: i for i, n in enumerate(CAT_NAMES)}
COUNTRY_NAMES_LEGACY = {"BE": ["Belgium", "België", "Belgique"], "NL": ["Netherlands", "Nederland"],
                        "FR": ["France"], "DE": ["Germany", "Deutschland"], "LU": ["Luxembourg"]}


def _ascii(s):
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower().replace(" ", "")


def _round_price(p):
    """Retail price points: 24.99, 129.95, ..."""
    p = np.asarray(p, dtype=float)
    out = np.where(p < 10, np.round(p * 2) / 2 - 0.01, np.round(p) - 0.01)
    return np.round(np.maximum(out, 0.99), 2)


def _weighted(rng, items, n):
    vals, w = zip(*items)
    w = np.asarray(w, float)
    return np.asarray(vals, dtype=object)[rng.choice(len(vals), size=n, p=w / w.sum())]


# ==========================================================================
# Catalog
# ==========================================================================
def build_catalog(rng, cal):
    categories = pd.DataFrame({
        "category_id": np.arange(1, len(R.CATEGORIES) + 1),
        "category_name": CAT_NAMES,
        "parent_category": [c[1] for c in R.CATEGORIES],
    })
    brands = pd.DataFrame({
        "brand_id": np.arange(1, len(R.BRANDS) + 1),
        "brand_name": [b[0] for b in R.BRANDS],
        "is_own_brand": [b[1] for b in R.BRANDS],
    })
    brand_id = dict(zip(brands.brand_name, brands.brand_id))

    products, variants = [], []
    pid, vid = 1000, 50000
    launch_default = pd.Timestamp("2023-10-15")
    for ci, (cat, _parent, n, pmin, pmax, cost_ratio, vtype, *_rest, cat_brands) in enumerate(R.CATEGORIES):
        names_used = set()
        for k in range(n):
            brand = cat_brands[rng.integers(len(cat_brands))]
            models = R.MODEL_NAMES[cat]
            if cat == "Gift cards":
                name, brand = "Kalkberg Gift Card", "Kalkberg Basics"
            elif cat == "Books & guides":
                base = models[k % len(models)]
                name = base if k < len(models) else f"{base} ({2 + k // len(models)}nd edition)"
            else:
                for _ in range(100):
                    name = f"{brand} {models[rng.integers(len(models))]}{R.MODEL_SUFFIXES[rng.integers(len(R.MODEL_SUFFIXES))]}"
                    if name not in names_used:
                        break
            names_used.add(name)

            price = pmin + (pmax - pmin) * rng.beta(1.6, 2.6)
            if rng.random() < 0.65 or cat == "Gift cards":
                launched = launch_default
            else:
                y = rng.choice([2024, 2025, 2026], p=[0.4, 0.4, 0.2])
                m = rng.choice([2, 3, 8, 9])
                launched = pd.Timestamp(year=int(y), month=int(m), day=int(rng.integers(1, 28)))
            discontinued = pd.NaT
            if cat != "Gift cards" and rng.random() < (0.18 if launched == launch_default else 0.06):
                lo = max(launched + pd.Timedelta(days=200), pd.Timestamp("2024-06-01"))
                if lo < pd.Timestamp("2026-08-31"):
                    discontinued = lo + pd.Timedelta(days=int(rng.integers(0, (pd.Timestamp("2026-08-31") - lo).days + 1)))
            products.append(dict(product_id=pid, product_name=name, brand_id=brand_id[brand], category_id=ci + 1,
                                 launched_at=launched.date(), discontinued_at=None if pd.isna(discontinued) else discontinued.date(),
                                 _cat=ci, _pop=rng.lognormal(0, 0.9), _launch=launched, _disc=discontinued))

            # Variants
            if vtype == "shoe":
                opts = [(f"EU {s:g}", 1.0) for s in R.SHOE_SIZES]
            elif vtype == "apparel":
                opts = [(s, 1.0) for s in R.APPAREL_SIZES]
            elif vtype == "harness":
                opts = [(s, 1.0) for s in R.HARNESS_SIZES]
            elif vtype == "helmet":
                opts = [(s, 1.0) for s in R.HELMET_SIZES]
            elif vtype == "rope":
                opts = [(lbl, mult) for lbl, mult, _ in R.ROPE_LENGTHS]
            elif vtype == "giftcard":
                opts = [(f"EUR {v}", v) for v, _ in R.GIFT_CARD_VALUES]
            else:
                opts = [(None, 1.0)]
            code = "".join(w[0] for w in cat.replace("&", "").split())[:3].upper()
            for j, (label, mult) in enumerate(opts):
                lp = float(mult) if vtype == "giftcard" else float(_round_price(price * mult))
                cost = round(lp / 1.21 * cost_ratio * rng.uniform(0.9, 1.1), 2)
                if vtype != "giftcard" and rng.random() < 0.02:
                    cost = None                                     # missing cost price
                variants.append(dict(variant_id=vid, product_id=pid,
                                     sku=f"KB-{code}-{pid}" + (f"-{j + 1:02d}" if label else ""),
                                     size_label=label, list_price=lp, unit_cost=cost, _pos=j))
                vid += 1
            pid += 1

    products = pd.DataFrame(products)
    # A few discontinued products were re-listed later under a new id with the same name
    relist = products[products._disc.notna() & (products._disc < pd.Timestamp("2026-03-01"))].sample(5, random_state=1)
    extra_p, extra_v = [], []
    vmax = max(v["variant_id"] for v in variants) + 1
    for _, row in relist.iterrows():
        new_launch = row._disc + pd.Timedelta(days=int(rng.integers(30, 150)))
        new = row.to_dict()
        new.update(product_id=pid, product_name=row.product_name + (" " if rng.random() < 0.5 else ""),
                   launched_at=new_launch.date(), discontinued_at=None, _launch=new_launch, _disc=pd.NaT)
        extra_p.append(new)
        for v in [v for v in variants if v["product_id"] == row.product_id]:
            nv = dict(v, variant_id=vmax, product_id=pid, sku=v["sku"].replace(str(row.product_id), str(pid)),
                      list_price=float(_round_price(v["list_price"] * 1.05)))
            extra_v.append(nv)
            vmax += 1
        pid += 1
    products = pd.concat([products, pd.DataFrame(extra_p)], ignore_index=True)
    variants = pd.DataFrame(variants + extra_v)
    products["is_active"] = products._disc.isna() | (products._disc > C.END)

    # Index helpers for fast sampling
    products["_launch_idx"] = cal.idx(products._launch)
    disc_idx = cal.idx(products._disc.fillna(C.END + pd.Timedelta(days=1)))
    products["_disc_idx"] = disc_idx
    first_var = variants.groupby("product_id").variant_id.min()
    products["_first_variant_row"] = products.product_id.map(
        pd.Series(variants.index, index=variants.variant_id).reindex(first_var.values).set_axis(first_var.index))
    products["_n_variants"] = products.product_id.map(variants.groupby("product_id").size())
    return categories, brands, products, variants


# ==========================================================================
# Customers (main accounts; duplicates and test accounts are added later)
# ==========================================================================
def _make_emails(rng, first, last, country, taken):
    n = len(first)
    fa = np.array([_ascii(x) for x in first])
    la = np.array([_ascii(x) for x in last])
    style = rng.integers(0, 6, n)
    num = rng.integers(1, 99, n).astype(str)
    local = np.select(
        [style == 0, style == 1, style == 2, style == 3, style == 4],
        [np.char.add(np.char.add(fa, "."), la), np.char.add(fa, la),
         np.char.add(np.char.add(np.array([x[:1] for x in fa]), "."), la),
         np.char.add(np.char.add(fa, "_"), la), np.char.add(np.char.add(fa, la), num)],
        np.char.add(np.char.add(np.char.add(fa, "."), la), num))
    domains = np.empty(n, dtype=object)
    for cc in R.COUNTRIES:
        m = country == cc
        domains[m] = _weighted(rng, R.EMAIL_DOMAINS[cc], m.sum())
    emails = []
    for loc, dom in zip(local, domains):
        e = f"{loc}@{dom}"
        i = 2
        while e in taken:
            e = f"{loc}{i}@{dom}"
            i += 1
        taken.add(e)
        emails.append(e)
    return np.array(emails, dtype=object)


def _phone(rng, cc):
    if rng.random() < 0.3:
        return None
    d = "".join(str(x) for x in rng.integers(0, 10, 8))
    style = rng.integers(0, 3)
    if cc == "BE":
        return [f"+32 4{d[0]}{d[1]} {d[2:4]} {d[4:6]} {d[6:8]}", f"04{d[0]}{d[1]}/{d[2:4]}.{d[4:6]}.{d[6:8]}", f"00324{d}"][style]
    if cc == "NL":
        return [f"+31 6 {d}", f"06-{d}", f"0031 6{d}"][style]
    if cc == "FR":
        return [f"+33 6 {d[:2]} {d[2:4]} {d[4:6]} {d[6:]}", f"06{d}", f"06.{d[:2]}.{d[2:4]}.{d[4:6]}.{d[6:]}"][style]
    if cc == "DE":
        return [f"+49 151 {d}", f"0151 {d}", f"0151-{d}"][style]
    return [f"+352 621 {d[:6]}", f"621{d[:6]}", f"00352 621 {d[:6]}"][style]


def _postal(rng, cc, code):
    if cc == "NL":
        letters = "".join(rng.choice(list("ABCDEGHJKLMNPRSTVWXZ"), 2))
        return f"{code} {letters}" if rng.random() < 0.7 else f"{code}{letters}"
    if cc == "LU":
        return f"L-{code}" if rng.random() < 0.5 else code
    if cc in ("FR", "DE") and rng.random() < 0.02:
        return code.lstrip("0") if code.startswith("0") else code   # leading zero lost
    return code


def person_profile(rng, country, n):
    """Name, language, address for n people of the given countries."""
    first = np.empty(n, dtype=object)
    last = np.empty(n, dtype=object)
    lang = np.empty(n, dtype=object)
    for cc, opts in R.CULTURES.items():
        idx = np.where(country == cc)[0]
        if len(idx) == 0:
            continue
        pick = rng.choice(len(opts), size=len(idx), p=[o[2] for o in opts])
        for j, (culture, language, _) in enumerate(opts):
            sub = idx[pick == j]
            first[sub] = rng.choice(R.FIRST_NAMES[culture], len(sub))
            last[sub] = rng.choice(R.LAST_NAMES[culture], len(sub))
            lang[sub] = language
    # Some customers write in English
    lang[rng.random(n) < 0.04] = "en"
    postal = np.empty(n, dtype=object)
    city = np.empty(n, dtype=object)
    for cc in R.COUNTRIES:
        idx = np.where(country == cc)[0]
        rows = R.CITIES[cc]
        w = np.array([r[2] for r in rows], float)
        pick = rng.choice(len(rows), size=len(idx), p=w / w.sum())
        for i, p in zip(idx, pick):
            postal[i] = _postal(rng, cc, rows[p][0])
            city[i] = rows[p][1]
    return first, last, lang, postal, city


def build_customers(rng, cal):
    n = C.N_CUSTOMERS
    codes = list(R.COUNTRIES)
    country = rng.choice(codes, size=n, p=[R.COUNTRIES[c][0] for c in codes])
    first, last, lang, postal, city = person_profile(rng, country, n)
    channels = list(R.ACQUISITION_CHANNELS)
    channel = rng.choice(channels, size=n, p=[R.ACQUISITION_CHANNELS[c][0] for c in channels])

    first_day = cal.sample_days(rng, n, kind="acq")
    first_ts = cal.days[first_day] + pd.to_timedelta(sample_time_of_day(rng, n), unit="s")
    never = rng.random(n) < 0.04
    early = rng.random(n) < 0.15
    created = first_ts - pd.to_timedelta(rng.integers(60, 900, n), unit="s")
    early_gap = pd.to_timedelta(rng.integers(1, 60, n), unit="D") + pd.to_timedelta(rng.integers(0, 86400, n), unit="s")
    early_created = created - early_gap
    early &= early_created >= C.START          # no accounts before the webshop launch
    created = pd.DatetimeIndex(np.where(early, early_created, created))

    # Influencer customers only exist while a creator contract is active
    cre_start = np.array([pd.Timestamp(c[3]) for c in R.CREATORS])
    cre_end = np.array([pd.Timestamp(c[4]) for c in R.CREATORS])
    creator = np.full(n, -1)
    for i in np.where(channel == "influencer")[0]:
        active = np.where((cre_start <= first_ts[i]) & (cre_end >= first_ts[i]))[0]
        if len(active):
            creator[i] = rng.choice(active)
        else:
            channel[i] = "paid_social"
    affiliate = np.where(channel == "affiliate", rng.choice(len(R.AFFILIATES), size=n, p=[0.7, 0.3]), -1)

    taken = set()
    emails = _make_emails(rng, first, last, country, taken)
    typo = rng.random(n) < 0.012
    for i in np.where(typo)[0]:
        loc, dom = emails[i].split("@")
        if dom in R.TYPO_DOMAINS:
            emails[i] = f"{loc}@{R.TYPO_DOMAINS[dom]}"

    # Opt-in: email-acquired customers already subscribed to the newsletter before buying
    opt_in = np.where(channel == "email", rng.random(n) < 0.6, rng.random(n) < 0.55)
    nl_signup = np.where(channel == "email",
                         first_ts - pd.to_timedelta(rng.uniform(2 / 24, 20, n), unit="D"), pd.NaT)

    age = 18 + rng.gamma(3.0, 4.0, n)
    birth = pd.Timestamp("2025-01-01") - pd.to_timedelta((age * 365.25).astype(int), unit="D")
    birth = pd.Series(birth).where(rng.random(n) < 0.75)

    df = pd.DataFrame({
        "_person": np.arange(n), "_country": country, "_channel": channel, "_creator": creator,
        "_affiliate": affiliate, "_never": never, "_first_ts": first_ts, "_nl_signup": pd.to_datetime(nl_signup),
        "_propensity": rng.lognormal(0, 0.6, n),
        "_shoe": np.clip(np.round(rng.normal(40.7, 2.2, n) * 2) / 2, 36, 46),
        "_apparel": np.clip(np.round(rng.normal(2.2, 1.0, n)), 0, 5).astype(int),
        "first_name": first, "last_name": last, "email": emails, "phone": [_phone(rng, c) for c in country],
        "birth_date": birth, "preferred_language": lang, "postal_code": postal, "city": city,
        "country_code": country, "marketing_opt_in": opt_in, "_created": created,
    })
    return df


def _mess_customer_fields(rng, df):
    """Data-entry and legacy-platform problems in customer records."""
    n = len(df)
    first = df.first_name.to_numpy(object).copy()
    last = df.last_name.to_numpy(object).copy()
    r = rng.random(n)
    first[r < 0.02] = [x.upper() for x in first[r < 0.02]]
    last[r < 0.02] = [x.upper() for x in last[r < 0.02]]
    m = (r >= 0.02) & (r < 0.035)
    first[m] = [x.lower() for x in first[m]]
    last[m] = [x.lower() for x in last[m]]
    m = (r >= 0.035) & (r < 0.045)
    first[m] = [x + " " for x in first[m]]
    df["first_name"], df["last_name"] = first, last

    email = df.email.to_numpy(object).copy()
    m = rng.random(n) < 0.03
    email[m] = [e[0].upper() + e[1:] for e in email[m]]
    df["email"] = email

    birth = pd.to_datetime(df.birth_date)
    r = rng.random(n)
    birth = birth.mask(r < 0.01, pd.Timestamp("1900-01-01"))
    future = (r >= 0.01) & (r < 0.013)
    birth = birth.mask(future, df._created.dt.normalize())
    df["birth_date"] = birth.dt.date

    legacy = df._created < C.PLATFORM_MIGRATION
    country = df.country_code.to_numpy(object).copy()
    for i in np.where(legacy)[0]:
        names = COUNTRY_NAMES_LEGACY[country[i]]
        country[i] = names[0] if rng.random() < 0.8 else names[rng.integers(len(names))]
    low = rng.random(n) < 0.01
    country[low] = [c.lower() for c in country[low]]
    df["country_code"] = country
    return df


# ==========================================================================
# Orders
# ==========================================================================
def build_orders(rng, cal, cust, products, variants):
    n = len(cust)
    first_day = cal.idx(cust._first_ts)
    chan_mult = cust._channel.map({k: v[1] for k, v in R.ACQUISITION_CHANNELS.items()}).to_numpy()
    one_and_done = rng.random(n) < 0.33
    lifetime = np.where(one_and_done, 0, rng.exponential(420 * chan_mult))
    active_end = np.minimum(first_day + lifetime.astype(int), cal.n - 1)
    lo = first_day + 5
    hi = active_end + 1
    span = np.clip(hi - lo, 0, None)
    ordering = ~cust._never.to_numpy()
    base = cust._propensity.to_numpy() * chan_mult * span / 365 * ordering

    n_guest = int(C.TARGET_ORDERS * C.GUEST_ORDER_SHARE)
    needed = C.TARGET_ORDERS - n_guest - ordering.sum()
    k = rng.poisson(base * needed / base.sum())
    k[span <= 0] = 0

    # First orders
    fo = pd.DataFrame({"_acc": np.where(ordering)[0], "_ts_local": cust._first_ts[ordering].to_numpy()})
    fo["_true_first"] = True
    # Repeat orders
    rep_acc = np.repeat(np.arange(n), k)
    rep_day = cal.sample_days(rng, len(rep_acc), lo[rep_acc], hi[rep_acc], kind="season")
    ro = pd.DataFrame({"_acc": rep_acc, "_ts_local": cal.days[rep_day] + pd.to_timedelta(sample_time_of_day(rng, len(rep_acc)), unit="s")})
    ro["_true_first"] = False
    orders = pd.concat([fo, ro], ignore_index=True)
    orders["_person"] = orders._acc
    orders["_guest"] = False
    orders["_test"] = False

    # ------------------------------------------------------------------ duplicate accounts
    counts = orders.groupby("_acc").size()
    cand = counts[counts >= 3].index.to_numpy()
    dup_people = rng.choice(cand, size=min(len(cand), int(0.015 * n)), replace=False)
    dup_rows = []
    taken = set(cust.email)
    for j, p in enumerate(dup_people):
        o = orders.index[orders._acc == p]
        ts = orders.loc[o, "_ts_local"].sort_values()
        cut = ts.iloc[0] + (ts.iloc[-1] - ts.iloc[0]) * rng.uniform(0.2, 0.8)
        move = o[(orders.loc[o, "_ts_local"] > cut).to_numpy() & (rng.random(len(o)) < 0.7)]
        acc_new = n + j
        orders.loc[move, "_acc"] = acc_new
        src = cust.iloc[p].to_dict()
        loc, dom = src["email"].split("@")
        style = rng.integers(0, 4)
        new_email = [loc.replace(".", "") + "@" + dom, loc + "@" + ("outlook.com" if dom == "gmail.com" else "gmail.com"),
                     src["email"].upper(), loc + str(rng.integers(1, 99)) + "@" + dom][style]
        if new_email in taken or new_email.lower() == src["email"].lower() and style != 2:
            new_email = loc + "." + str(rng.integers(100, 999)) + "@" + dom
        taken.add(new_email)
        created = (orders.loc[move, "_ts_local"].min() - pd.Timedelta(seconds=int(rng.integers(60, 600)))) if len(move) else cut
        src.update(email=new_email, _created=created, marketing_opt_in=bool(rng.random() < 0.6), _nl_signup=pd.NaT,
                   first_name=src["first_name"].upper() if rng.random() < 0.3 else src["first_name"],
                   _dup_of=p)
        dup_rows.append(src)
    cust["_dup_of"] = -1
    cust = pd.concat([cust, pd.DataFrame(dup_rows)], ignore_index=True)

    # ------------------------------------------------------------------ test accounts
    t = C.N_TEST_ACCOUNTS
    t_created = cal.days[rng.integers(0, cal.n - 30, t)] + pd.to_timedelta(rng.integers(8 * 3600, 18 * 3600, t), unit="s")
    test = pd.DataFrame({
        "_person": -2, "_country": "BE", "_channel": "test", "_creator": -1, "_affiliate": -1, "_never": False,
        "_first_ts": t_created, "_nl_signup": pd.NaT, "_propensity": 0.0, "_shoe": 42.0, "_apparel": 2,
        "first_name": rng.choice(["Test", "QA", "Test Klant", "test"], t),
        "last_name": rng.choice(["Kalkberg", "Test", "Order", "Account"], t),
        "email": [f"test+{i}@kalkberg.example" if i % 3 else f"qa.kalkberg+{i}@gmail.com" for i in range(t)],
        "phone": None, "birth_date": None, "preferred_language": "nl", "postal_code": "9000", "city": "Gent",
        "country_code": "BE", "marketing_opt_in": False, "_created": t_created, "_dup_of": -1,
    })
    test_start = len(cust)
    cust = pd.concat([cust, test], ignore_index=True)
    t_orders = []
    for i in range(t):
        for _ in range(rng.integers(1, 6)):
            day = rng.integers(cal.idx([t_created[i]])[0], cal.n)
            t_orders.append(dict(_acc=test_start + i, _person=-2, _true_first=False, _guest=False, _test=True,
                                 _ts_local=cal.days[day] + pd.Timedelta(seconds=int(rng.integers(9 * 3600, 17 * 3600)))))
    orders = pd.concat([orders, pd.DataFrame(t_orders)], ignore_index=True)

    # ------------------------------------------------------------------ guest orders
    g_day = cal.sample_days(rng, n_guest)
    codes = list(R.COUNTRIES)
    g_country = rng.choice(codes, size=n_guest, p=[R.COUNTRIES[c][0] for c in codes])
    g_first, g_last, _, g_postal, g_city = person_profile(rng, g_country, n_guest)
    g_email = _make_emails(rng, g_first, g_last, g_country, set(cust.email))
    known = rng.random(n_guest) < 0.3            # existing customers checking out as guest
    pick = rng.integers(0, C.N_CUSTOMERS, n_guest)
    g_email = np.where(known, cust.email.to_numpy()[pick], g_email)
    g_email = np.array([e.lower() if (k and rng.random() < 0.5) else e for e, k in zip(g_email, known)], dtype=object)
    g_country = np.where(known, cust._country.to_numpy()[pick], g_country)
    guests = pd.DataFrame({"_acc": -1, "_person": np.where(known, pick, -1), "_true_first": False, "_guest": True,
                           "_test": False, "_ts_local": cal.days[g_day] + pd.to_timedelta(sample_time_of_day(rng, n_guest), unit="s"),
                           "guest_email": g_email, "_g_country": g_country, "_g_postal": g_postal, "_g_city": g_city})
    orders = pd.concat([orders, guests], ignore_index=True)

    # ------------------------------------------------------------------ customer ids (sequential by creation time)
    cust = _mess_customer_fields(rng, cust)
    order_of_creation = np.argsort(cust._created.to_numpy(), kind="stable")
    cust_id = np.empty(len(cust), dtype=int)
    cust_id[order_of_creation] = np.arange(100001, 100001 + len(cust))
    cust["customer_id"] = cust_id
    # Duplicate accounts belong to the same person
    cust["_person"] = np.where(cust._dup_of >= 0, cust._dup_of, cust._person)

    # ------------------------------------------------------------------ order header attributes
    orders = orders.sort_values("_ts_local", kind="stable").reset_index(drop=True)
    orders["order_id"] = np.arange(1, len(orders) + 1)
    acc = orders._acc.to_numpy()
    has_acc = acc >= 0
    orders["customer_id"] = pd.array(np.where(has_acc, cust.customer_id.to_numpy()[np.where(has_acc, acc, 0)], 0), dtype="Int64")
    orders.loc[~has_acc, "customer_id"] = pd.NA
    country = np.where(has_acc, cust._country.to_numpy()[np.where(has_acc, acc, 0)], orders.get("_g_country"))
    orders["_country"] = country
    orders["_channel"] = np.where(has_acc, cust._channel.to_numpy()[np.where(has_acc, acc, 0)], "guest")
    person = orders._person.to_numpy()
    orders["_true_first"] = orders._true_first.astype(bool)

    legacy = (orders._ts_local < C.PLATFORM_MIGRATION).to_numpy()
    seq_post = np.cumsum(~legacy)
    yy = orders._ts_local.dt.strftime("%y").to_numpy()
    orders["order_number"] = np.where(legacy, np.char.add("KB", (100000 + orders.order_id.to_numpy()).astype(str)),
                                      np.char.add(np.char.add(np.char.add("KB-", yy.astype(str)), "-"),
                                                  np.char.zfill(seq_post.astype(str), 6)))
    utc = local_to_utc(orders._ts_local)
    orders["_ts_utc"] = utc
    orders["created_at"] = np.where(legacy, orders._ts_local.to_numpy(), utc)    # legacy platform stored local time

    lines = _build_lines(rng, cal, orders, cust, products, variants)
    orders, lines = _price_orders(rng, cal, orders, cust, lines, variants)
    returns = _build_returns(rng, cal, orders, lines, products, variants)
    orders = _final_status(rng, orders, lines, returns)

    # Shipping address
    acc_safe = np.where(has_acc, acc, 0)
    orders["shipping_postal_code"] = np.where(has_acc, cust.postal_code.to_numpy()[acc_safe], orders.get("_g_postal"))
    orders["shipping_city"] = np.where(has_acc, cust.city.to_numpy()[acc_safe], orders.get("_g_city"))
    sc = orders._country.to_numpy(object).copy()
    sc[legacy] = [COUNTRY_NAMES_LEGACY[c][0] for c in sc[legacy]]
    orders["shipping_country"] = sc
    pay = np.empty(len(orders), dtype=object)
    for cc in R.COUNTRIES:
        m = orders._country.to_numpy() == cc
        pay[m] = _weighted(rng, R.PAYMENT_METHODS[cc], m.sum())
    pay[orders._test.to_numpy()] = "Manual"
    orders["payment_method"] = pay
    orders["currency"] = "EUR"
    return cust, orders, lines, returns


def _build_lines(rng, cal, orders, cust, products, variants):
    n = len(orders)
    first = orders._true_first.to_numpy()
    test = orders._test.to_numpy()
    n_lines = np.clip(1 + rng.poisson(np.where(first, 0.85, 1.0)), 1, 6)
    n_lines[test] = 1
    oi = np.repeat(np.arange(n), n_lines)
    pos = np.concatenate([np.arange(k) for k in n_lines])
    m = len(oi)

    w_first = np.array([c[8] for c in R.CATEGORIES])
    w_rep = np.array([c[9] for c in R.CATEGORIES])
    is_first_line = pos == 0
    cat = np.empty(m, dtype=int)
    fl = np.where(is_first_line)[0]
    p_first = first[oi[fl]]
    cat[fl[p_first]] = rng.choice(len(w_first), p_first.sum(), p=w_first / w_first.sum())
    cat[fl[~p_first]] = rng.choice(len(w_rep), (~p_first).sum(), p=w_rep / w_rep.sum())
    # Following lines: complements of the first item (65%) or a regular pick
    first_cat_of_order = np.empty(n, dtype=int)
    first_cat_of_order[oi[fl]] = cat[fl]
    other = np.where(~is_first_line)[0]
    aff = np.zeros((len(CAT_NAMES), len(CAT_NAMES)))
    for a, row in R.AFFINITY.items():
        for b, w in row.items():
            aff[CAT_INDEX[a], CAT_INDEX[b]] = w
    aff_cum = np.cumsum(aff / aff.sum(axis=1, keepdims=True), axis=1)
    fc = first_cat_of_order[oi[other]]
    use_aff = rng.random(len(other)) < 0.65
    u = rng.random(len(other))
    cat_aff = np.minimum((u[:, None] > aff_cum[fc]).sum(axis=1), len(CAT_NAMES) - 1)
    cat_reg = rng.choice(len(w_rep), len(other), p=w_rep / w_rep.sum())
    cat[other] = np.where(use_aff, cat_aff, cat_reg)

    # Product (available on the order date)
    day = cal.idx(orders._ts_local)[oi]
    prod = np.full(m, -1)
    for ci in range(len(CAT_NAMES)):
        rows = np.where(cat == ci)[0]
        pr = products.index[products._cat == ci].to_numpy()
        pop = products.loc[pr, "_pop"].to_numpy()
        launch = products.loc[pr, "_launch_idx"].to_numpy()
        disc = products.loc[pr, "_disc_idx"].to_numpy()
        todo = rows
        for _ in range(40):
            if len(todo) == 0:
                break
            pick = rng.choice(len(pr), len(todo), p=pop / pop.sum())
            ok = (launch[pick] <= day[todo]) & (disc[pick] > day[todo])
            prod[todo[ok]] = pr[pick[ok]]
            todo = todo[~ok]
        for r in todo:     # rare fallback: any available product in the category
            avail = np.where((launch <= day[r]) & (disc > day[r]))[0]
            prod[r] = pr[rng.choice(avail)] if len(avail) else pr[0]

    # Variant
    acc = orders._acc.to_numpy()[oi]
    person_shoe = np.where(acc >= 0, cust._shoe.to_numpy()[np.maximum(acc, 0)], np.round(rng.normal(40.7, 2.2, m) * 2) / 2)
    person_app = np.where(acc >= 0, cust._apparel.to_numpy()[np.maximum(acc, 0)], rng.integers(1, 5, m))
    vtype = np.array([R.CATEGORIES[c][6] for c in cat])
    offset = np.zeros(m, dtype=int)
    shoe_pos = np.clip(((person_shoe - 36) * 2).astype(int), 0, len(R.SHOE_SIZES) - 1)
    app_shift = np.where(rng.random(m) < 0.1, rng.choice([-1, 1], m), 0)
    offset = np.where(vtype == "shoe", shoe_pos, offset)
    offset = np.where(vtype == "apparel", np.clip(person_app + app_shift, 0, 5), offset)
    offset = np.where(vtype == "harness", np.clip(person_app + app_shift, 0, 4), offset)
    offset = np.where(vtype == "helmet", rng.integers(0, 2, m), offset)
    offset = np.where(vtype == "rope", rng.choice(3, m, p=[r[2] for r in R.ROPE_LENGTHS]), offset)
    offset = np.where(vtype == "giftcard", rng.choice(4, m, p=[g[1] for g in R.GIFT_CARD_VALUES]), offset)
    vrow = products._first_variant_row.to_numpy()[prod] + offset

    lines = pd.DataFrame({"_oi": oi, "_cat": cat, "_prod": prod, "_vrow": vrow, "_bracket": False})
    qty = np.ones(m, dtype=int)
    qty += np.where(cat == CAT_INDEX["Chalk"], (rng.random(m) < 0.35).astype(int) + (rng.random(m) < 0.1), 0)
    qty += np.where(cat == CAT_INDEX["Accessories"], (rng.random(m) < 0.2).astype(int), 0)
    qty += np.where(cat == CAT_INDEX["Quickdraws & carabiners"], (rng.random(m) < 0.15).astype(int), 0)
    lines["quantity"] = qty

    # Size bracketing: order the same shoe in two sizes and send one back
    br = np.where((vtype == "shoe") & (rng.random(m) < 0.06))[0]
    extra = lines.iloc[br].copy()
    shift = np.where(shoe_pos[br] >= len(R.SHOE_SIZES) - 1, -1, np.where(shoe_pos[br] == 0, 1, rng.choice([-1, 1], len(br))))
    extra["_vrow"] = extra._vrow + shift
    extra["_bracket"] = True
    lines = pd.concat([lines, extra], ignore_index=True)
    lines = lines.groupby(["_oi", "_vrow"], as_index=False).agg(
        _cat=("_cat", "first"), _prod=("_prod", "first"), _bracket=("_bracket", "max"), quantity=("quantity", "sum"))
    lines = lines.sort_values(["_oi", "_vrow"]).reset_index(drop=True)
    lines["variant_id"] = variants.variant_id.to_numpy()[lines._vrow]
    return lines


def _price_orders(rng, cal, orders, cust, lines, variants):
    n = len(orders)
    oi = lines._oi.to_numpy()
    ts = orders._ts_local
    day = cal.idx(ts)

    # ---- discount codes (order level)
    code = np.full(n, None, dtype=object)
    acc = orders._acc.to_numpy()
    acc0 = np.maximum(acc, 0)
    chan = orders._channel.to_numpy()
    first = orders._true_first.to_numpy()
    r = rng.random(n)
    nl = cust._nl_signup.to_numpy()[acc0]
    welcome = first & (chan == "email") & (r < 0.85)
    variants_w = rng.choice(["WELCOME10", "welcome10", "Welcome10", " WELCOME10"], n, p=[0.67, 0.2, 0.1, 0.03])
    code[welcome] = variants_w[welcome]
    creator = cust._creator.to_numpy()[acc0]
    infl = (chan == "influencer") & (creator >= 0) & ((first & (r < 0.75)) | (~first & (r < 0.12)))
    cre_end = np.array([pd.Timestamp(c[4]) for c in R.CREATORS])
    for i in np.where(infl)[0]:
        if ts.iloc[i] <= cre_end[creator[i]] + pd.Timedelta(days=14):     # codes keep working a bit after the contract
            code[i] = R.CREATORS[creator[i]][2] if rng.random() > 0.15 else R.CREATORS[creator[i]][2].lower()
    aff = cust._affiliate.to_numpy()[acc0]
    aff_code = (chan == "affiliate") & (aff == 0) & ((first & (r < 0.55)) | (~first & (r < 0.10)))
    code[aff_code] = "CLIMBDEALS10"
    sorry = (code == None) & (rng.random(n) < 0.005)  # noqa: E711
    code[sorry] = "SORRY10"
    test = orders._test.to_numpy()
    code[test & (rng.random(n) < 0.7)] = "TEST100"
    code_pct = pd.Series(code).str.strip().str.upper().map(
        {"WELCOME10": 0.10, "CLIMBDEALS10": 0.10, "SORRY10": 0.10, "TEST100": 1.0,
         **{c[2]: 0.15 for c in R.CREATORS}}).fillna(0).to_numpy()
    orders["discount_code"] = code
    orders["_code_pct"] = code_pct

    # ---- line prices
    cat = lines._cat.to_numpy()
    vprice = variants.list_price.to_numpy()[lines._vrow.to_numpy()]
    gift = cat == CAT_INDEX["Gift cards"]
    idx_price = cal.price_index(ts.iloc[oi])
    unit = np.where(gift, vprice, _round_price(vprice * idx_price))
    unit = np.where(gift, vprice, np.minimum(unit, vprice))
    promo = cal.promo[day[oi], cat]
    pct = np.where(promo > 0, promo, np.where(gift, 0, code_pct[oi]))
    qty = lines.quantity.to_numpy()
    disc = np.round(qty * unit * pct, 2)
    lines["unit_price"] = np.round(unit, 2)
    lines["discount_amount"] = disc
    lines["line_total"] = np.round(qty * unit - disc, 2)

    # ---- order totals
    g = lines.groupby("_oi")
    subtotal = (lines.quantity * lines.unit_price).groupby(lines._oi).sum().reindex(range(n)).to_numpy()
    disc_total = g.discount_amount.sum().reindex(range(n)).to_numpy()
    net = subtotal - disc_total
    country = orders._country.to_numpy()
    new_rules = (ts >= pd.Timestamp("2025-01-15")).to_numpy()
    threshold = np.where(np.isin(country, ["BE", "NL"]), np.where(new_rules, 69, 60), np.where(new_rules, 85, 75))
    fee = np.select([np.isin(country, ["BE", "NL"]), country == "LU"], [4.95, 6.95], 7.95) + np.where(new_rules, 1.0, 0)
    shipping = np.where((net >= threshold) | test, 0.0, fee)
    total = np.round(net + shipping, 2)
    glitch = rng.random(n) < 0.002
    total = np.where(glitch, np.round(total + rng.choice([-0.05, -0.02, -0.01, 0.01, 0.02], n), 2), total)
    orders["subtotal"] = np.round(subtotal, 2)
    orders["discount_total"] = np.round(disc_total, 2)
    orders["shipping_fee"] = shipping
    orders["order_total"] = total
    orders["_net"] = np.round(net, 2)
    return orders, lines


def _build_returns(rng, cal, orders, lines, products, variants):
    cat = lines._cat.to_numpy()
    rate = np.array([R.CATEGORIES[c][7] for c in cat])
    rate = np.where(lines._bracket.to_numpy(), 0.5, rate)   # one of the two bracketed shoes goes back
    ret = rng.random(len(lines)) < rate
    ret &= ~orders._test.to_numpy()[lines._oi]
    r = lines[ret].copy()
    ots = orders._ts_local.to_numpy()[r._oi]
    requested = pd.DatetimeIndex(ots) + pd.to_timedelta(rng.uniform(3, 25, len(r)), unit="D")
    received = requested + pd.to_timedelta(rng.uniform(2, 8, len(r)), unit="D")
    keep = requested <= C.END
    r, requested, received = r[keep], requested[keep], received[keep]
    received = pd.Series(received).where(received <= C.END)

    c = r._cat.to_numpy()
    reasons = np.where(np.isin(c, [CAT_INDEX["Climbing shoes"], CAT_INDEX["Clothing"], CAT_INDEX["Harnesses"]]),
                       rng.choice(["Too small", "Too big", "Not as expected", "Defective", "Changed mind"], len(r),
                                  p=[0.42, 0.28, 0.14, 0.06, 0.10]),
                       rng.choice(["Defective", "Not as expected", "Changed mind", "Wrong item received"], len(r),
                                  p=[0.35, 0.3, 0.25, 0.10]))
    qty = np.array([rng.integers(1, q + 1) for q in r.quantity])
    status = np.where(received.isna(), "in_transit", np.where(rng.random(len(r)) < 0.03, "rejected", "refunded"))
    refund = np.where(status == "refunded", np.round(r.line_total.to_numpy() / r.quantity.to_numpy() * qty, 2), 0.0)
    returns = pd.DataFrame({
        "_line_row": r.index.to_numpy(), "_oi": r._oi.to_numpy(),
        "requested_at": requested.round("s"), "received_at": received.dt.round("s"),
        "quantity": qty, "reason": reasons, "status": status, "refund_amount": refund})
    returns = returns.sort_values("requested_at").reset_index(drop=True)
    returns["return_id"] = np.arange(1, len(returns) + 1)
    return returns


def _final_status(rng, orders, lines, returns):
    n = len(orders)
    status = np.full(n, "completed", dtype=object)
    cancelled = (rng.random(n) < 0.015) & ~orders.index.isin(returns._oi)
    status[cancelled] = "cancelled"
    refunded_lines = returns[returns.status == "refunded"]
    ref_amt = refunded_lines.groupby("_oi").refund_amount.sum()
    tot = orders._net.to_numpy()
    full = ref_amt.index[(ref_amt.to_numpy() >= tot[ref_amt.index] - 0.01)]
    status[ref_amt.index] = "partially_refunded"
    status[full] = "refunded"
    ts = orders._ts_local
    status[(ts > C.END - pd.Timedelta(days=6)).to_numpy() & (status == "completed")] = "shipped"
    status[(ts > C.END - pd.Timedelta(days=2)).to_numpy() & (status == "shipped")] = "processing"
    orders["status"] = status
    return orders
