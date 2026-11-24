"""Salesforce Marketing Cloud style data views: _Subscribers, _Job, _Sent, _Open, _Click, _Bounce, _Unsubscribe.

Broadcasts (newsletters and campaign blasts) are simulated first, chronologically, because the
engagement-based segmentation (from SEGMENTATION_START) depends on earlier opens and clicks.
Triggered journeys are added later, once the GA4 step knows which emails led to sessions.
"""
import uuid

import numpy as np
import pandas as pd

from . import config as C
from . import reference as R
from .calendar_model import BLACK_FRIDAYS, local_to_utc, us_datetime_text
from .shop import _make_emails, person_profile

CST = pd.Timedelta(hours=-6)            # SFMC data views use a fixed UTC-6 clock
LANGS = ["nl", "fr", "de", "en"]

# Journey launch dates (business facts)
FLOW_START = {"welcome": pd.Timestamp("2024-03-01"), "post_purchase": pd.Timestamp("2024-05-01"),
              "abandoned_cart": pd.Timestamp("2024-10-01"), "winback": pd.Timestamp("2025-06-01")}


def _slug(s):
    return s.lower().replace(" - ", "_").replace(" ", "_").replace("%", "")


# ==========================================================================
# Subscribers
# ==========================================================================
def build_subscribers(rng, cal, cust):
    rows = []
    real = cust[cust._channel != "test"]
    # A) Customer accounts that opted in
    a = real[real.marketing_opt_in]
    rows.append(pd.DataFrame({"_person": a._person, "_join": a._created, "EmailAddress": a.email,
                              "_lang": a.preferred_language, "_country": a._country,
                              "_key_kind": "customer", "_cid": a.customer_id}))
    # B) Newsletter sign-ups of people who later became customers (email channel)
    b = real[real._nl_signup.notna()]
    rows.append(pd.DataFrame({"_person": b._person, "_join": b._nl_signup, "EmailAddress": b.email.str.lower(),
                              "_lang": b.preferred_language, "_country": b._country,
                              "_key_kind": "newsletter", "_cid": -1}))
    # C) Newsletter-only subscribers (never bought)
    n = C.N_NEWSLETTER_ONLY
    codes = list(R.COUNTRIES)
    country = rng.choice(codes, size=n, p=[R.COUNTRIES[c][0] for c in codes])
    first, last, lang, _, _ = person_profile(rng, country, n)
    emails = _make_emails(rng, first, last, country, set(cust.email.str.lower()))
    day = cal.sample_days(rng, n)
    join = cal.days[day] + pd.to_timedelta(rng.integers(0, 86400, n), unit="s")
    rows.append(pd.DataFrame({"_person": -1, "_join": join, "EmailAddress": emails, "_lang": lang, "_country": country,
                              "_key_kind": "newsletter", "_cid": -1}))
    s = pd.concat(rows, ignore_index=True)
    s["_join"] = pd.to_datetime(s._join)
    s = s.sort_values("_join", kind="stable").reset_index(drop=True)
    s["_join_utc"] = local_to_utc(s._join)
    s["SubscriberID"] = np.arange(1000001, 1000001 + len(s))
    legacy = s._join < C.PLATFORM_MIGRATION
    nl_key = "NL-" + pd.Series(rng.choice(np.arange(100000, 999999), len(s), replace=False)).astype(str)
    s["SubscriberKey"] = np.where(legacy, s.EmailAddress,
                                  np.where(s._key_kind == "customer", s._cid.astype(str), nl_key))
    s["Domain"] = s.EmailAddress.str.split("@").str[1].str.lower()
    s["Locale"] = s._lang + "-" + np.where(s._lang == "en", "GB", s._country)
    s["_invalid"] = s.Domain.isin(R.TYPO_DOMAINS.values())
    m = len(s)
    s["_p_open"] = rng.beta(2, 5, m)
    s["_p_click"] = rng.beta(1.2, 14, m)
    s["_apple"] = np.where(s.Domain == "icloud.com", rng.random(m) < 0.9, rng.random(m) < 0.3)
    s["_scanner"] = rng.random(m) < 0.0025
    return s


# ==========================================================================
# Broadcast calendar
# ==========================================================================
def broadcast_calendar():
    """List of broadcasts: local send time, email name, subject, category, links."""
    b = []
    d = pd.Timestamp("2023-11-09 10:00")
    while d <= C.END:
        b.append((d, f"NL_{d:%Y-%m-%d}_Biweekly", "Fresh beta: what's new at Kalkberg", "Newsletter"))
        d += pd.Timedelta(days=14)
    for i, bf in enumerate(BLACK_FRIDAYS):
        y = bf.year
        b += [(bf - pd.Timedelta(days=2) + pd.Timedelta(hours=18), f"CMP_BF{y}_Teaser", "Black Friday is coming - get ready", "Campaign"),
              (bf + pd.Timedelta(hours=7), f"CMP_BF{y}_Launch", "Black Friday: up to 25% off climbing shoes", "Campaign"),
              (bf + pd.Timedelta(days=2, hours=10), f"CMP_BF{y}_Reminder", "Last weekend of Black Friday deals", "Campaign"),
              (bf + pd.Timedelta(days=3, hours=8), f"CMP_CM{y}_Launch", "Cyber Monday: final call", "Campaign"),
              (pd.Timestamp(f"{y}-12-16 09:00"), f"CMP_XMAS{y}_LastOrderDay", "Order today for delivery before Christmas", "Campaign")]
    for y in (2024, 2025, 2026):
        b += [(pd.Timestamp(f"{y}-01-02 08:00"), f"CMP_JANSALE{y}_Launch", "January sale starts now", "Campaign"),
              (pd.Timestamp(f"{y}-01-09 18:00"), f"CMP_JANSALE{y}_Reminder", "January sale: last week", "Campaign"),
              (pd.Timestamp(f"{y}-07-01 08:00"), f"CMP_SUMMER{y}_Launch", "Summer sale: up to 30% off", "Campaign"),
              (pd.Timestamp(f"{y}-07-19 18:00"), f"CMP_SUMMER{y}_LastChance", "Summer sale ends Sunday", "Campaign"),
              (pd.Timestamp(f"{y}-09-04 10:00"), f"CMP_NEWSHOES{y}_Launch", "New season, new shoes", "Campaign")]
    for y in (2025, 2026):
        b.append((pd.Timestamp(f"{y}-03-20 10:00"), f"CMP_OUTDOOR{y}_Launch", "Outdoor season: pads and ropes 15% off", "Campaign"))
    b = [x for x in b if C.START <= x[0] <= C.END]
    df = pd.DataFrame(b, columns=["send_local", "EmailName", "EmailSubject", "Category"]).sort_values("send_local")
    return df.reset_index(drop=True)


LINKS = [("Hero banner", 0.45), ("Product block 1", 0.2), ("Product block 2", 0.15), ("Blog teaser", 0.1), ("Footer - Shop", 0.1)]
LINK_PATHS = ["/collections/climbing-shoes", "/collections/chalk", "/collections/crash-pads", "/collections/clothing",
              "/collections/training", "/sale", "/collections/new-arrivals"]


def email_utm(rng, send_local, campaign):
    """UTM parameters used in email links (conventions changed over time)."""
    if send_local < C.PLATFORM_MIGRATION:
        source, medium = "newsletter", "email"
    else:
        source = "SFMC" if rng.random() < 0.08 else "sfmc"
        medium = "Email" if rng.random() < 0.05 else "email"
    return source, medium, campaign


# ==========================================================================
# Broadcast simulation
# ==========================================================================
def simulate_broadcasts(rng, subs):
    bc = broadcast_calendar()
    bc["send_utc"] = local_to_utc(bc.send_local)
    # Four content links per broadcast + footer link to the homepage
    bc["_paths"] = [list(np.array(LINK_PATHS)[rng.permutation(len(LINK_PATHS))[:4]]) + ["/"] for _ in range(len(bc))]
    m = len(subs)
    join = subs._join_utc.to_numpy()
    active = np.ones(m, dtype=bool)
    unsub_time = np.full(m, np.datetime64("NaT"), dtype="datetime64[ns]")
    held_time = np.full(m, np.datetime64("NaT"), dtype="datetime64[ns]")
    last_eng = join.copy()
    lang_idx = subs._lang.map({l: i for i, l in enumerate(LANGS)}).to_numpy()
    p_open, p_click = subs._p_open.to_numpy(), subs._p_click.to_numpy()
    apple, scanner, invalid = subs._apple.to_numpy(), subs._scanner.to_numpy(), subs._invalid.to_numpy()

    jobs, sent, opens, clicks, bounces, unsubs = [], [], [], [], [], []
    job_id = 412300
    for bi, b in bc.iterrows():
        t = np.datetime64(b.send_utc)
        rec = active & (join <= t)
        if b.send_local >= C.SEGMENTATION_START:
            rec &= (last_eng >= t - np.timedelta64(120, "D")) | (join >= t - np.timedelta64(60, "D"))
        idx = np.where(rec)[0]
        if len(idx) == 0:
            continue
        utm = email_utm(rng, b.send_local, b.EmailName.lower())
        jid = {}
        for li, lang in enumerate(LANGS):
            jid[li] = job_id
            jobs.append(dict(JobID=job_id, EmailName=f"{b.EmailName}_{lang.upper()}", EmailSubject=b.EmailSubject,
                             Category=b.Category, _send_utc=b.send_utc, _bi=bi, _utm=utm, _kind="broadcast"))
            job_id += 1
        k = len(idx)
        sent_t = t + (rng.uniform(0, 2400, k) * 1e9).astype("timedelta64[ns]")
        job = np.array([jid[l] for l in lang_idx[idx]])
        batch = 1 + (rng.random(k) * 12).astype(int)
        sent.append(pd.DataFrame({"JobID": job, "BatchID": batch, "_sub": idx, "_t": sent_t}))

        r = rng.random(k)
        hard = invalid[idx]
        soft = ~hard & (r < 0.004)
        bmask = hard | soft
        if bmask.any():
            bounces.append(pd.DataFrame({"JobID": job[bmask], "BatchID": batch[bmask], "_sub": idx[bmask],
                                         "_t": sent_t[bmask] + np.timedelta64(30, "s"), "_hard": hard[bmask]}))
            hi = idx[hard]
            active[hi] = False
            held_time[hi] = t
        dl = ~bmask
        boost = 1.15 if b.Category == "Campaign" else 1.0
        fatigue = 0.85 if b.send_local < C.SEGMENTATION_START else 1.0
        mpp = dl & apple[idx] & (rng.random(k) < 0.95)
        real = dl & (rng.random(k) < p_open[idx] * boost * fatigue)
        scan = dl & scanner[idx]
        t_mpp = sent_t + (rng.uniform(5, 900, k) * 1e9).astype("timedelta64[ns]")
        t_real = sent_t + (np.minimum(rng.lognormal(np.log(2.5 * 3600), 1.2, k), 7 * 86400) * 1e9).astype("timedelta64[ns]")
        t_scan = sent_t + (rng.uniform(1, 4, k) * 1e9).astype("timedelta64[ns]")
        for mask, tt in ((mpp, t_mpp), (real, t_real), (scan, t_scan)):
            opens.append(pd.DataFrame({"JobID": job[mask], "BatchID": batch[mask], "_sub": idx[mask], "_t": tt[mask]}))
        again = real & (rng.random(k) < 0.1)
        opens.append(pd.DataFrame({"JobID": job[again], "BatchID": batch[again], "_sub": idx[again],
                                   "_t": t_real[again] + (rng.uniform(600, 2 * 86400, again.sum()) * 1e9).astype("timedelta64[ns]")}))
        clk = real & (rng.random(k) < p_click[idx] * boost)
        link = rng.choice(len(LINKS), k, p=[l[1] for l in LINKS])
        t_clk = t_real + (rng.uniform(10, 600, k) * 1e9).astype("timedelta64[ns]")
        clicks.append(pd.DataFrame({"JobID": job[clk], "BatchID": batch[clk], "_sub": idx[clk], "_t": t_clk[clk],
                                    "_link": link[clk], "_bi": bi}))
        for li in range(len(LINKS)):      # link scanners click everything
            clicks.append(pd.DataFrame({"JobID": job[scan], "BatchID": batch[scan], "_sub": idx[scan],
                                        "_t": t_scan[scan] + np.timedelta64(li, "s"), "_link": li, "_bi": bi}))
        uns = real & (rng.random(k) < 0.004)
        if uns.any():
            ut = t_real[uns] + np.timedelta64(40, "s")
            unsubs.append(pd.DataFrame({"JobID": job[uns], "BatchID": batch[uns], "_sub": idx[uns], "_t": ut}))
            active[idx[uns]] = False
            unsub_time[idx[uns]] = ut
        eng = np.where(real, t_real, np.where(mpp, t_mpp, np.datetime64("NaT")))
        upd = ~np.isnat(eng)
        last_eng[idx[upd]] = np.maximum(last_eng[idx[upd]], eng[upd])

    state = pd.DataFrame({"active": active, "unsub_time": unsub_time, "held_time": held_time})
    out = dict(jobs=pd.DataFrame(jobs), sent=pd.concat(sent, ignore_index=True), opens=pd.concat(opens, ignore_index=True),
               clicks=pd.concat(clicks, ignore_index=True), bounces=pd.concat(bounces, ignore_index=True),
               unsubs=pd.concat(unsubs, ignore_index=True), bc=bc)
    return out, state


def link_url(path, utm):
    source, medium, campaign = utm
    return f"{C.SHOP_DOMAIN}{path}?utm_source={source}&utm_medium={medium}&utm_campaign={campaign}"


# ==========================================================================
# Triggered journeys
# ==========================================================================
def simulate_triggered(rng, subs, state, orders, cust, known_abandons, forced):
    """Welcome, post-purchase, abandoned cart and win-back journeys.

    forced: dict with lists of required sends/clicks coming from the GA4 step:
        forced["welcome"]: DataFrame(_sub, step, click_t)
        forced["cart"]:    DataFrame(_sub, send_t, click_t)
    """
    m = len(subs)
    join = subs._join_utc.to_numpy()
    stop = np.minimum(state.unsub_time.fillna(pd.Timestamp("2100-01-01")).to_numpy(),
                      state.held_time.fillna(pd.Timestamp("2100-01-01")).to_numpy())
    end = np.datetime64(C.END + pd.Timedelta(days=1))
    sends = []

    # Welcome 1 + 2 (all new subscribers after the journey went live)
    ok = subs._join.to_numpy() >= np.datetime64(FLOW_START["welcome"])
    idx = np.where(ok)[0]
    t1 = join[idx] + (rng.uniform(60, 600, len(idx)) * 1e9).astype("timedelta64[ns]")
    t2 = join[idx] + np.timedelta64(3, "D")
    welcome = pd.concat([pd.DataFrame({"_sub": idx, "_t": t1, "_flow": "welcome_1"}),
                         pd.DataFrame({"_sub": idx, "_t": t2, "_flow": "welcome_2"})], ignore_index=True)
    fw = forced["welcome"].rename(columns={"click_t": "_forced_click", "step": "_flow"})
    welcome = welcome.merge(fw.drop_duplicates(["_sub", "_flow"]), on=["_sub", "_flow"], how="left")
    sends.append(welcome)

    # Post-purchase review request, 7 days after the order, to subscribed customers
    cust_sub = subs[subs._key_kind == "customer"][["_person", "SubscriberID"]].reset_index()
    cust_sub = cust_sub.drop_duplicates("_person")
    o = orders[(~orders._test) & (orders._person >= 0) & (orders._ts_local >= FLOW_START["post_purchase"])
               & (orders.status != "cancelled")]
    o = o.merge(cust_sub, on="_person")
    o = o[rng.random(len(o)) < 0.9]
    sends.append(pd.DataFrame({"_sub": o["index"].to_numpy(), "_flow": "post_purchase",
                               "_t": o._ts_utc.to_numpy() + np.timedelta64(7, "D") + (rng.uniform(0, 3600, len(o)) * 1e9).astype("timedelta64[ns]")}))

    # Abandoned cart (logged-in sessions with add_to_cart and no purchase)
    ka = known_abandons[known_abandons._t >= np.datetime64(FLOW_START["abandoned_cart"])]
    sends.append(pd.DataFrame({"_sub": ka._sub.to_numpy(), "_flow": "abandoned_cart",
                               "_t": ka._t.to_numpy() + (rng.uniform(3600, 3 * 3600, len(ka)) * 1e9).astype("timedelta64[ns]")}))
    fc = forced["cart"]
    sends.append(pd.DataFrame({"_sub": fc._sub.to_numpy(), "_t": fc.send_t.to_numpy(), "_flow": "abandoned_cart", "_forced_click": fc.click_t.to_numpy()}))

    # Win-back: first day of each month, customers without an order in the last 180 days (once per 180 days)
    last_order = orders[(orders._person >= 0) & ~orders._test].groupby("_person")._ts_utc.max()
    order_ts = orders[(orders._person >= 0) & ~orders._test][["_person", "_ts_utc"]].sort_values("_ts_utc")
    months = pd.date_range(FLOW_START["winback"], C.END, freq="MS")
    sub_of_person = cust_sub.set_index("_person")["index"]
    last_wb = pd.Series(dtype="datetime64[ns]")
    for mth in months:
        t = local_to_utc([mth + pd.Timedelta(hours=11)])[0]
        before = order_ts[order_ts._ts_utc < t].groupby("_person")._ts_utc.max()
        lapsed = before[before < t - pd.Timedelta(days=180)].index
        lapsed = lapsed[lapsed.isin(sub_of_person.index)]
        recent = last_wb[last_wb > t - pd.Timedelta(days=180)].index
        lapsed = lapsed[~lapsed.isin(recent)]
        sends.append(pd.DataFrame({"_sub": sub_of_person.loc[lapsed].to_numpy(), "_flow": "winback",
                                   "_t": t + (rng.uniform(0, 1800, len(lapsed)) * 1e9).astype("timedelta64[ns]")}))
        last_wb = pd.concat([last_wb, pd.Series(t, index=lapsed)])
        last_wb = last_wb[~last_wb.index.duplicated(keep="last")]
    _ = last_order

    s = pd.concat(sends, ignore_index=True)
    s["_t"] = pd.to_datetime(s._t)
    s = s[(s._t.to_numpy() < stop[s._sub]) & (s._t.to_numpy() < end) & (s._t.to_numpy() >= join[s._sub])].copy()
    # Welcome emails for forced welcome clicks must exist: they are part of the welcome set already
    s = s.reset_index(drop=True)
    k = len(s)
    flows = ["welcome_1", "welcome_2", "post_purchase", "abandoned_cart", "winback"]
    s["_flow_i"] = s._flow.map({f: i for i, f in enumerate(flows)})

    # Jobs: one per journey email per year (republished every January) and language
    s["_year"] = s._t.dt.year
    lang = subs._lang.to_numpy()[s._sub]
    s["_lang"] = lang
    keys = s[["_flow", "_year", "_lang"]].drop_duplicates().sort_values(["_year", "_flow", "_lang"]).reset_index(drop=True)
    keys["JobID"] = np.arange(470000, 470000 + len(keys))
    names = {"welcome_1": ("Welcome to Kalkberg - here is your 10% code", "TS_Welcome_1"),
             "welcome_2": ("How to choose your first climbing shoes", "TS_Welcome_2"),
             "post_purchase": ("How is your new gear? Leave a review", "TS_PostPurchase_Review"),
             "abandoned_cart": ("You left something in your cart", "TS_AbandonedCart"),
             "winback": ("We miss you at the wall", "TS_Winback")}
    guid = {f: str(uuid.UUID(int=int(rng.integers(0, 2**63)) << 64 | int(rng.integers(0, 2**63)))) for f in flows}
    keys["EmailName"] = keys._flow.map(lambda f: names[f][1]) + "_" + keys._year.astype(str) + "_" + keys._lang.str.upper()
    keys["EmailSubject"] = keys._flow.map(lambda f: names[f][0])
    keys["Category"] = "Journeys"
    keys["TriggeredSendCustomerKey"] = keys._flow.map(lambda f: names[f][1])
    keys["TriggererSendDefinitionObjectID"] = keys._flow.map(guid)
    first_send = s.groupby(["_flow", "_year", "_lang"])._t.min().rename("_send_utc").reset_index()
    keys = keys.merge(first_send, on=["_flow", "_year", "_lang"])
    keys["_kind"] = "triggered"
    keys["_utm"] = [("sfmc", "email", f) for f in keys._flow]
    s = s.merge(keys[["_flow", "_year", "_lang", "JobID", "TriggeredSendCustomerKey", "TriggererSendDefinitionObjectID"]],
                on=["_flow", "_year", "_lang"])
    s["BatchID"] = 1

    p_open = subs._p_open.to_numpy()[s._sub]
    p_click = subs._p_click.to_numpy()[s._sub]
    apple = subs._apple.to_numpy()[s._sub]
    invalid = subs._invalid.to_numpy()[s._sub]
    k = len(s)
    st = s._t.to_numpy()
    forced_click = s["_forced_click"].to_numpy() if "_forced_click" in s else np.full(k, np.datetime64("NaT"))
    forced_click = pd.to_datetime(pd.Series(forced_click)).to_numpy()
    bounce = invalid | (rng.random(k) < 0.003)
    dl = ~bounce
    mpp = dl & apple & (rng.random(k) < 0.95)
    rate = np.where(s._flow.isin(["welcome_1", "abandoned_cart"]), 1.9, 1.4)
    real = dl & ((rng.random(k) < np.minimum(p_open * rate, 0.95)) | ~np.isnat(forced_click))
    t_real = st + (np.minimum(rng.lognormal(np.log(1.5 * 3600), 1.1, k), 5 * 86400) * 1e9).astype("timedelta64[ns]")
    has_fc = ~np.isnat(forced_click)
    t_real = np.where(has_fc, forced_click - (rng.uniform(15, 240, k) * 1e9).astype("timedelta64[ns]"), t_real)
    t_mpp = st + (rng.uniform(5, 900, k) * 1e9).astype("timedelta64[ns]")
    clk = real & ~has_fc & (rng.random(k) < np.minimum(p_click * 2.0, 0.6))
    t_clk = np.where(has_fc, forced_click, t_real + (rng.uniform(10, 300, k) * 1e9).astype("timedelta64[ns]"))
    clk |= has_fc

    base = dict(JobID=s.JobID.to_numpy(), BatchID=1, _sub=s._sub.to_numpy(),
                TriggeredSendCustomerKey=s.TriggeredSendCustomerKey.to_numpy(),
                TriggererSendDefinitionObjectID=s.TriggererSendDefinitionObjectID.to_numpy())

    def sub(mask, t, **extra):
        d = {k2: (v[mask] if isinstance(v, np.ndarray) else v) for k2, v in base.items()}
        d["_t"] = t[mask]
        d.update({k2: v[mask] for k2, v in extra.items()})
        return pd.DataFrame(d)

    flow_link = {"welcome_1": "/collections/climbing-shoes", "welcome_2": "/blog/how-to-choose-climbing-shoes",
                 "post_purchase": "/account/reviews", "abandoned_cart": "/cart", "winback": "/collections/new-arrivals"}
    out = dict(
        jobs=keys,
        sent=sub(np.ones(k, bool), st),
        bounces=sub(bounce, st + np.timedelta64(20, "s"), _hard=invalid),
        opens=pd.concat([sub(mpp, t_mpp), sub(real, t_real)], ignore_index=True),
        clicks=sub(clk, t_clk, _path=s._flow.map(flow_link).to_numpy(), _flow=s._flow.to_numpy()),
        unsubs=sub(real & ~has_fc & (rng.random(k) < 0.002), t_real + np.timedelta64(30, "s")),
    )
    return out


# ==========================================================================
# Export formatting
# ==========================================================================
def to_data_views(rng, subs, state, bc_out, tr_out):
    """Turn simulated events into the SFMC data view exports."""
    def fmt(ts):
        return us_datetime_text(pd.to_datetime(ts) + CST)

    jobs = pd.concat([bc_out["jobs"], tr_out["jobs"]], ignore_index=True)
    jobs["EmailID"] = jobs.EmailName.factorize()[0] + 9100
    jobs["FromName"] = "Kalkberg"
    jobs["FromEmail"] = "hello@kalkberg.example"
    jobs["SchedTime"] = np.where(jobs._kind == "broadcast", fmt(jobs._send_utc - pd.Timedelta(minutes=5)), None)
    jobs["PickupTime"] = fmt(jobs._send_utc - pd.Timedelta(minutes=1))
    jobs["DeliveredTime"] = fmt(jobs._send_utc)
    jobs["JobType"] = np.where(jobs._kind == "broadcast", "Email", "TriggeredSend")
    jobs["JobStatus"] = "Complete"
    jobs["AccountID"] = 518000123
    job_cols = ["JobID", "EmailID", "AccountID", "FromName", "FromEmail", "SchedTime", "PickupTime", "DeliveredTime",
                "JobType", "JobStatus", "EmailName", "EmailSubject", "Category", "TriggererSendDefinitionObjectID",
                "TriggeredSendCustomerKey"]
    for c in ("TriggererSendDefinitionObjectID", "TriggeredSendCustomerKey"):
        if c not in jobs:
            jobs[c] = None
    jobs_out = jobs[job_cols]

    key = subs.SubscriberKey.to_numpy()
    sid = subs.SubscriberID.to_numpy()
    dom = subs.Domain.to_numpy()

    def event_table(parts, cols, unique=True):
        df = pd.concat([p for p in parts if len(p)], ignore_index=True)
        for c in ("TriggeredSendCustomerKey", "TriggererSendDefinitionObjectID"):
            if c not in df:
                df[c] = None
        df = df.sort_values("_t", kind="stable").reset_index(drop=True)
        df["JobID"] = df.JobID.astype("int64")
        df["BatchID"] = df.BatchID.astype("int64")
        df["AccountID"] = 518000123
        df["OYBAccountID"] = None
        df["ListID"] = np.where(df.TriggeredSendCustomerKey.isna(), 1047, 1052)
        df["SubscriberID"] = sid[df._sub]
        df["SubscriberKey"] = key[df._sub]
        df["Domain"] = dom[df._sub]
        df["EventDate"] = fmt(df._t)
        if unique:
            df["IsUnique"] = ~df.duplicated(["JobID", "_sub"] + (["URL"] if "URL" in df else []))
        return df[cols]

    base_cols = ["AccountID", "OYBAccountID", "JobID", "ListID", "BatchID", "SubscriberID", "SubscriberKey", "EventDate", "Domain"]
    ts_cols = ["TriggererSendDefinitionObjectID", "TriggeredSendCustomerKey"]
    sent = event_table([bc_out["sent"], tr_out["sent"]], base_cols + ts_cols, unique=False)
    opens = event_table([bc_out["opens"], tr_out["opens"]], base_cols + ["IsUnique"] + ts_cols)

    # Clicks: resolve URL from the job's UTM parameters
    job_utm = dict(zip(jobs.JobID, jobs._utm))
    bclk = bc_out["clicks"].copy()
    paths = bc_out["bc"]["_paths"]
    bclk["_path"] = [paths[bi][li] for bi, li in zip(bclk._bi, bclk._link)]
    bclk["LinkName"] = [LINKS[li][0] for li in bclk._link]
    tclk = tr_out["clicks"].copy()
    tclk["LinkName"] = "Main CTA"
    clicks = pd.concat([bclk, tclk], ignore_index=True)
    clicks["URL"] = [link_url(p, job_utm[j]) for p, j in zip(clicks._path, clicks.JobID)]
    clicks["LinkContent"] = clicks.URL.str.split("?").str[0] + "?utm_source=%%=v(@utm_source)=%%&utm_medium=email"
    clicks = event_table([clicks], base_cols + ["URL", "LinkName", "LinkContent", "IsUnique"] + ts_cols)

    b = pd.concat([bc_out["bounces"], tr_out["bounces"]], ignore_index=True)
    b["BounceCategory"] = np.where(b._hard, "Hard bounce", "Soft bounce")
    b["BounceSubcategory"] = np.where(b._hard, "User Unknown", "Mailbox Full")
    b["BounceType"] = np.where(b._hard, "immediate", "delayed")
    b["SMTPBounceReason"] = np.where(b._hard, "550 5.1.1 The email account that you tried to reach does not exist",
                                     "452 4.2.2 The email account that you tried to reach is over quota")
    bounces = event_table([b], base_cols + ["BounceCategory", "BounceSubcategory", "BounceType", "SMTPBounceReason", "IsUnique"] + ts_cols)
    unsubs = event_table([bc_out["unsubs"], tr_out["unsubs"]], base_cols + ["IsUnique"])

    # Subscriber status at export time
    all_uns = pd.concat([bc_out["unsubs"], tr_out["unsubs"]]).groupby("_sub")._t.min()
    hard = b[b._hard].groupby("_sub")._t.min()
    status = np.full(len(subs), "Active", dtype=object)
    status[all_uns.index] = "Unsubscribed"
    status[hard.index] = "Held"
    bounce_count = b.groupby("_sub").size().reindex(range(len(subs)), fill_value=0).to_numpy()
    out_subs = pd.DataFrame({
        "SubscriberID": sid, "DateUndeliverable": None, "DateJoined": fmt(subs._join_utc), "DateUnsubscribed": None,
        "Domain": dom, "EmailAddress": subs.EmailAddress, "BounceCount": bounce_count, "SubscriberKey": key,
        "SubscriberType": "Subscriber", "Status": status, "Locale": subs.Locale})
    out_subs.loc[all_uns.index, "DateUnsubscribed"] = fmt(all_uns.to_numpy())
    out_subs.loc[hard.index, "DateUndeliverable"] = fmt(hard.to_numpy())
    return dict(subscribers=out_subs, job=jobs_out, sent=sent, open=opens, click=clicks, bounce=bounces, unsubscribe=unsubs)
