"""GA4 data: a flattened event-level export and a daily traffic report.

Every tracked order gets a session path (earlier visits + the purchase session). Email sessions are
tied to real SFMC sends: when a session comes from an email, the matching click is added to SFMC.
"""
import re
from urllib.parse import quote

import numpy as np
import pandas as pd

from . import config as C
from . import reference as R
from .calendar_model import utc_to_local
from .sfmc import FLOW_START, LINKS

MIX_FIRST = {"organic_search": .27, "paid_search": .24, "paid_social": .18, "direct": .12, "referral": .07,
             "influencer": .05, "affiliate": .04, "email_bcast": .03}
MIX_REPEAT = {"direct": .25, "organic_search": .19, "email_bcast": .24, "paid_search": .13, "paid_social": .08,
              "referral": .04, "influencer": .03, "affiliate": .04}
MIX_EARLIER = {"organic_search": .26, "paid_social": .22, "paid_search": .16, "direct": .14, "referral": .09,
               "influencer": .05, "email_bcast": .08}
CONSENT_RATE = 0.82                       # share of visitors that accept analytics cookies
GA4_COUNTRY = {k: v[1] for k, v in R.COUNTRIES.items()}
ANON_COUNTRIES = [("Belgium", .40), ("Netherlands", .27), ("France", .12), ("Germany", .10), ("Luxembourg", .03),
                  ("United Kingdom", .03), ("United States", .03), ("(not set)", .02)]
DEVICES = ["mobile", "desktop", "tablet"]
GENERIC_LANDING = ["/", "/", "/collections/climbing-shoes", "/collections/chalk", "/collections/crash-pads",
                   "/collections/clothing", "/collections/training", "/blog/bouldering-for-beginners",
                   "/blog/how-to-choose-climbing-shoes", "PRODUCT", "PRODUCT", "PRODUCT"]


def _pick(rng, mix, n):
    k = list(mix)
    p = np.array([mix[x] for x in k])
    return np.asarray(k, dtype=object)[rng.choice(len(k), n, p=p / p.sum())]


def _slugify(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def _ns(seconds):
    return (np.asarray(seconds) * 1e9).astype("timedelta64[ns]")


# ==========================================================================
# Traffic sources available on a given day
# ==========================================================================
class TrafficOptions:
    """(source, medium, campaign, campaign key, landing) options with weights, per channel and day."""

    def __init__(self, cal, bc, bc_utm, products):
        self.cal = cal
        self.bc_day = cal.idx(bc.send_local)
        self.bc_utm = bc_utm
        self.bc_paths = bc["_paths"].tolist()
        self.product_slugs = ["/products/" + _slugify(n) for n in products.product_name.str.strip().unique()]
        self.cache = {}

    def get(self, chan, day):
        key = (chan, day)
        if key not in self.cache:
            self.cache[key] = self._build(chan, day)
        return self.cache[key]

    def _build(self, chan, day):
        date = self.cal.days[day]
        opts = []          # (source, medium, campaign, ckey, landing, weight)
        if chan == "organic_search":
            opts = [("google", "organic", "(organic)", None, "GEN", 88), ("bing", "organic", "(organic)", None, "GEN", 7),
                    ("duckduckgo", "organic", "(organic)", None, "GEN", 3), ("ecosia.org", "organic", "(organic)", None, "GEN", 2)]
        elif chan == "direct":
            opts = [("(direct)", "(none)", "(direct)", None, "GEN", 1)]
        elif chan == "referral":
            opts = [(s, "referral", "(referral)", None, "GEN", w) for s, w in R.REFERRAL_SOURCES]
        elif chan == "paid_search":
            for name, ctype, s, e, *_ in R.GOOGLE_CAMPAIGNS:
                if pd.Timestamp(s) <= date <= pd.Timestamp(e):
                    w = R.GOOGLE_WEIGHTS.get(name, R.GOOGLE_SEASONAL_WEIGHT)
                    landing = ("/" if "Brand" in name else "/collections/climbing-shoes" if "Shoes" in name
                               else "/collections/crash-pads" if "Crash" in name else "/collections/hardware" if "Hardware" in name
                               else "/black-friday" if "Black Friday" in name else "/sale" if "Summer" in name else "PRODUCT")
                    opts.append(("google", "cpc", name, "G:" + name, landing, w))
        elif chan == "paid_social":
            camps = [(n, R.META_WEIGHTS.get(n, R.META_SEASONAL_WEIGHT)) for n, s, e, _ in R.META_CAMPAIGNS
                     if pd.Timestamp(s) <= date <= pd.Timestamp(e)]
            if date < C.META_AGENCY_SWITCH:
                srcs = [("facebook", .45), ("instagram", .35), ("fb", .12), ("Facebook", .08)]
                meds = [("paid_social", .7), ("cpc", .2), ("paid-social", .1)]
                cmode = [("slug", 1.0)]
            else:
                srcs = [("meta", .6), ("facebook", .2), ("ig", .2)]
                meds = [("paid-social", .85), ("paidsocial", .15)]
                cmode = [("exact", .85), ("slug", .12), ("template", .03)]
            for name, w in camps:
                for s_, ws in srcs:
                    for m_, wm in meds:
                        for mode, wc in cmode:
                            camp = {"exact": name, "slug": name.lower().replace(" - ", "_").replace(" ", "_").replace("%", ""),
                                    "template": "{{campaign.name}}"}[mode]
                            land = "/sale" if "Sale" in name else "/black-friday" if "BF" in name else "PRODUCT"
                            opts.append((s_, m_, camp, "M:" + name, land, w * ws * wm * wc))
        elif chan == "influencer":
            for handle, platform, _code, s, e, _fee in R.CREATORS:
                if pd.Timestamp(s) <= date <= pd.Timestamp(e) + pd.Timedelta(days=14):
                    for m_, wm in [("influencer", .75), ("Influencer", .1), ("social", .15)]:
                        for camp, wc in [(handle, .7), (handle.replace(".", "_"), .3)]:
                            opts.append((platform.lower(), m_, camp, "I:" + handle, "GEN", wm * wc))
        elif chan == "affiliate":
            opts = [("climbdeals", "affiliate", "climbdeals_deals_page", "A:climbdeals", "GEN", 70),
                    ("outdoorvouchers", "affiliate", "vouchers", "A:outdoorvouchers", "GEN", 20),
                    ("climbdeals", "aff", "climbdeals_deals_page", "A:climbdeals", "GEN", 10)]
        elif chan == "email":
            recent = np.where((self.bc_day <= day) & (self.bc_day > day - 10))[0]
            for bi in recent:
                age = day - self.bc_day[bi]
                s_, m_, c_ = self.bc_utm[bi]
                for path in self.bc_paths[bi][:2]:
                    opts.append((s_, m_, c_, "E:" + c_, path, np.exp(-age / 1.5)))
            for flow in ("welcome_1", "abandoned_cart", "post_purchase"):
                opts.append(("sfmc", "email", flow, "E:" + flow, "/", 0.3))
        if not opts:
            return None
        w = np.array([o[5] for o in opts], float)
        return opts, w / w.sum()

    def landing(self, rng, kind):
        if kind == "GEN":
            kind = GENERIC_LANDING[rng.integers(len(GENERIC_LANDING))]
        if kind == "PRODUCT":
            return self.product_slugs[rng.integers(len(self.product_slugs))]
        return kind


# ==========================================================================
# Main
# ==========================================================================
def build_ga4(rng, cal, orders, cust, subs, sub_state, bc_out, products, n_lines):
    bc = bc_out["bc"]
    job_bi = dict(zip(bc_out["jobs"].JobID, bc_out["jobs"]._bi))
    bc_utm = bc_out["jobs"].drop_duplicates("_bi").set_index("_bi")._utm.to_dict()
    opts = TrafficOptions(cal, bc, bc_utm, products)
    n_persons = C.N_CUSTOMERS

    # ---------------- device profiles per person
    n_dev = 1 + (rng.random(n_persons) < 0.45) + (rng.random(n_persons) < 0.12)
    dev_type = rng.choice(3, (n_persons, 3), p=[0.6, 0.33, 0.07])
    dev_type[:, 0] = rng.choice(3, n_persons, p=[0.62, 0.33, 0.05])
    ios = rng.random((n_persons, 3)) < np.where(dev_type == 2, 0.7, 0.5)
    life = np.where((dev_type != 1) & ios, 7, 180)
    offset = (rng.random((n_persons, 3)) * life).astype(int)

    # ---------------- sessions linked to orders
    o = orders[~orders._test].copy()
    o["_oi"] = o.index
    o = o[rng.random(len(o)) < CONSENT_RATE]
    no = len(o)
    o_person = o._person.to_numpy()
    o_first = o._true_first.to_numpy()
    o_guest = o._guest.to_numpy()
    o_acc = o._acc.to_numpy()
    o_ts = o._ts_utc.to_numpy()
    acq = cust._channel.to_numpy()

    final_chan = np.where(o_first, np.where(rng.random(no) < 0.75, acq[np.maximum(o_acc, 0)], _pick(rng, MIX_FIRST, no)),
                          np.where(o_guest, _pick(rng, MIX_FIRST, no), _pick(rng, MIX_REPEAT, no))).astype(object)
    final_chan[o_first & (final_chan == "email")] = "email_welcome"
    final_chan[final_chan == "email"] = "email_bcast"
    final_chan[(o_person < 0) & np.isin(final_chan, ["email_bcast", "email_welcome"])] = "direct"

    # person -> subscribers
    sp = subs[subs._person >= 0]
    cust_sub = pd.Series(sp[sp._key_kind == "customer"].drop_duplicates("_person").index,
                         index=sp[sp._key_kind == "customer"].drop_duplicates("_person")._person)
    nl_sub = pd.Series(sp[sp._key_kind == "newsletter"].drop_duplicates("_person").index,
                       index=sp[sp._key_kind == "newsletter"].drop_duplicates("_person")._person)
    stop = np.minimum(sub_state.unsub_time.fillna(pd.Timestamp("2100-01-01")).to_numpy(),
                      sub_state.held_time.fillna(pd.Timestamp("2100-01-01")).to_numpy())
    invalid = subs._invalid.to_numpy()
    join_utc = subs._join_utc.to_numpy()

    # abandoned-cart recoveries
    cs = cust_sub.reindex(o_person).to_numpy()
    has_cs = ~np.isnan(cs)
    cs_i = np.where(has_cs, cs, 0).astype(int)
    t0 = o_ts - _ns(rng.uniform(4 * 3600, 3 * 86400, no))
    recov = (has_cs & ~o_guest & (rng.random(no) < 0.07) & (t0 >= np.datetime64(local_ts(FLOW_START["abandoned_cart"])))
             & (stop[cs_i] > o_ts) & ~invalid[cs_i] & (join_utc[cs_i] < t0))
    final_chan[recov] = "email_cart"

    final_start = o_ts - _ns(rng.uniform(4 * 60, 45 * 60, no))
    rows = [pd.DataFrame({"_o": np.arange(no), "role": "final", "start": final_start, "chan": final_chan})]
    k_e = rng.poisson(np.where(o_first, 1.1, 0.6))
    e_o = np.repeat(np.arange(no), k_e)
    e_start = o_ts[e_o] - _ns(rng.uniform(0.2 * 86400, 21 * 86400, len(e_o)))
    e_chan = _pick(rng, MIX_EARLIER, len(e_o))
    # the earliest visit of a first order usually comes from the acquisition channel
    first_of_group = np.r_[True, e_o[1:] != e_o[:-1]]
    use_acq = first_of_group & o_first[e_o] & (rng.random(len(e_o)) < 0.8)
    acq_e = acq[np.maximum(o_acc[e_o], 0)]
    e_chan = np.where(use_acq, np.where(acq_e == "email", "organic_search", acq_e), e_chan)
    e_chan = np.where((o_person[e_o] < 0) & (e_chan == "email_bcast"), "direct", e_chan)
    rows.append(pd.DataFrame({"_o": e_o, "role": "earlier", "start": e_start, "chan": e_chan}))
    r_o = np.where(recov)[0]
    rows.append(pd.DataFrame({"_o": r_o, "role": "cart_abandon", "start": t0[r_o], "chan": _pick(rng, MIX_REPEAT, len(r_o))}))
    S = pd.concat(rows, ignore_index=True)
    S["chan"] = S.chan.astype(object)
    S.loc[(S.role == "cart_abandon") & (S.chan == "email_bcast"), "chan"] = "direct"
    S["person"] = o_person[S._o]
    S["acc"] = o_acc[S._o]

    # ---------------- logged-in visits with a cart but no purchase (known users)
    cand = orders[(orders._person >= 0) & ~orders._test & ~orders._guest]
    pick = cand.sample(int(0.3 * len(orders)), replace=True, random_state=7)
    k_start = pick._ts_utc.to_numpy() + _ns(rng.uniform(2 * 86400, 60 * 86400, len(pick)))
    keep = k_start < np.datetime64(C.END + pd.Timedelta(days=1))
    pick, k_start = pick[keep], k_start[keep]
    K = pd.DataFrame({"_o": -1, "role": "known_abandon", "start": k_start, "chan": _pick(rng, MIX_REPEAT, len(pick)),
                      "person": pick._person.to_numpy(), "acc": pick._acc.to_numpy()})
    # ---------------- anonymous visits with a cart (no purchase)
    n_anon = int(0.5 * len(orders))
    a_day = cal.sample_days(rng, n_anon)
    a_local = cal.days[a_day] + pd.to_timedelta(rng.integers(0, 86400, n_anon), unit="s")
    from .calendar_model import local_to_utc
    A = pd.DataFrame({"_o": -1, "role": "anon_abandon", "start": local_to_utc(a_local),
                      "chan": _pick(rng, {k: v for k, v in R.TRAFFIC_MIX.items()}, n_anon), "person": -1, "acc": -1})
    S = pd.concat([S, K, A], ignore_index=True)
    S["start"] = pd.to_datetime(S.start)
    S["day"] = cal.idx(utc_to_local(S.start))
    S = S[(S.day >= 0) & (S.day < cal.n)].reset_index(drop=True)
    n = len(S)
    so = S._o.to_numpy()
    S["order_number"] = np.where(so >= 0, o.order_number.to_numpy()[np.maximum(so, 0)], None)
    for c in ("source", "medium", "campaign", "ckey", "landing"):
        S[c] = None

    # ---------------- resolve email sessions
    forced_welcome, forced_cart = _resolve_email(rng, S, o, o_ts, recov, t0, cs_i, nl_sub, subs, stop, invalid,
                                                 join_utc, bc_out, job_bi, bc_utm, bc)
    # ---------------- other channels
    todo = S.source.isna().to_numpy()
    S.loc[todo & S.chan.isin(["email_bcast", "email_welcome", "email_cart"]).to_numpy(), "chan"] = "direct"
    for (chan, day), g in S[S.source.isna()].groupby(["chan", "day"]):
        res = opts.get(chan, day)
        if res is None:
            res = opts.get("direct", day)
        olist, p = res
        pick_i = rng.choice(len(olist), len(g), p=p)
        S.loc[g.index, "source"] = [olist[i][0] for i in pick_i]
        S.loc[g.index, "medium"] = [olist[i][1] for i in pick_i]
        S.loc[g.index, "campaign"] = [olist[i][2] for i in pick_i]
        S.loc[g.index, "ckey"] = [olist[i][3] for i in pick_i]
        S.loc[g.index, "landing"] = [opts.landing(rng, olist[i][4]) for i in pick_i]

    # ---------------- device, cookie, user id
    person = S.person.to_numpy()
    known = person >= 0
    pidx = np.maximum(person, 0)
    dev_i = np.where(S.role.to_numpy() == "final", np.where(rng.random(n) < 0.6, 0, rng.integers(0, 3, n)), rng.integers(0, 3, n))
    dev_i = np.minimum(dev_i, n_dev[pidx] - 1)
    dtype_ = np.where(known, dev_type[pidx, dev_i], rng.choice(3, n, p=[0.62, 0.33, 0.05]))
    epoch = (S.day.to_numpy() + offset[pidx, dev_i]) // life[pidx, dev_i]
    ckey_cookie = np.where(known, pidx.astype(np.int64) * 1_000_000 + dev_i * 100_000 + epoch, -(np.arange(n) + 1))
    # guests that are not known customers: one cookie per order
    guest_unknown = (S.acc.to_numpy() < 0) & ~known & (S._o.to_numpy() >= 0)
    ckey_cookie = np.where(guest_unknown, -(10_000_000 + S._o.to_numpy()), ckey_cookie)
    S["device_category"] = np.array(DEVICES)[dtype_]
    S["_cookie"] = ckey_cookie

    role = S.role.to_numpy()
    acc = S.acc.to_numpy()
    has_acc = acc >= 0
    r1, r2 = rng.random(n), rng.random(n)
    logged = np.select([role == "final", role == "cart_abandon", role == "known_abandon", role == "earlier"],
                       [r1 < 0.92, np.ones(n, bool), r1 < 0.7, r1 < 0.3], False) & has_acc
    S["uid_events"] = logged
    S["uid_start"] = logged & np.where(role == "final", r2 < 0.45, r2 < 0.5)
    S["user_id"] = np.where(has_acc, cust.customer_id.to_numpy()[np.maximum(acc, 0)], 0)
    country = np.where(has_acc, pd.Series(cust._country.to_numpy()[np.maximum(acc, 0)]).map(GA4_COUNTRY).to_numpy(), None)
    og = S._o.to_numpy()
    gc = np.where(og >= 0, pd.Series(o._country.to_numpy()[np.maximum(og, 0)]).map(GA4_COUNTRY).to_numpy(), None)
    anon_c = np.array([c for c, _ in ANON_COUNTRIES], dtype=object)[rng.choice(len(ANON_COUNTRIES), n, p=[w for _, w in ANON_COUNTRIES])]
    country = np.where(country == None, np.where(gc == None, anon_c, gc), country)  # noqa: E711
    country[rng.random(n) < 0.01] = "(not set)"
    S["country"] = country

    # ---------------- events
    events, known_abandons = _events(rng, S, o, o_ts, n_lines, cust_sub, stop)
    sess = _session_numbers(rng, S, events)

    # ---------------- export filter: sessions with ecommerce activity, identified users, or cookies that bought
    ecom = events[events.event_name != "session_start"].groupby("_s").size()
    has_ecom = np.zeros(n, bool)
    has_ecom[ecom.index] = True
    ecom_cookies = np.unique(S._cookie.to_numpy()[has_ecom])
    keep = has_ecom | S.uid_events.to_numpy() | np.isin(S._cookie.to_numpy(), ecom_cookies)
    export = events[keep[events._s.to_numpy()]].copy()
    export = _format_events(rng, S, sess, export)

    daily, ads_sessions = _daily_report(rng, cal, S, sess, events, opts, has_ecom)
    forced = {"welcome": forced_welcome, "cart": forced_cart}
    return export, daily, ads_sessions, known_abandons, forced


def local_ts(ts):
    from .calendar_model import local_to_utc
    return local_to_utc([ts])[0]


def _resolve_email(rng, S, o, o_ts, recov, t0, cs_i, nl_sub, subs, stop, invalid, join_utc, bc_out, job_bi, bc_utm, bc):
    """Attach email sessions to real sends and record the clicks SFMC must contain."""
    welcome_start = np.datetime64(local_ts(FLOW_START["welcome"]))
    # --- welcome
    W = S[S.chan == "email_welcome"]
    sub = nl_sub.reindex(W.person.to_numpy()).to_numpy()
    ok = ~np.isnan(sub)
    sub_i = np.where(ok, sub, 0).astype(int)
    ok &= (join_utc[sub_i] >= welcome_start) & ~invalid[sub_i] & (W.start.to_numpy() > join_utc[sub_i] + np.timedelta64(15, "m"))
    ok &= stop[sub_i] > W.start.to_numpy()
    S.loc[W.index[~ok], "chan"] = "email_bcast"
    Wk = W[ok]
    step = np.where(Wk.start.to_numpy() >= join_utc[sub_i[ok]] + np.timedelta64(3, "D") + np.timedelta64(15, "m"), "welcome_2", "welcome_1")
    click_t = Wk.start.to_numpy() - _ns(rng.uniform(1, 4, len(Wk)))
    forced_welcome = pd.DataFrame({"_sub": sub_i[ok], "step": step, "click_t": click_t})
    path = {"welcome_1": "/collections/climbing-shoes", "welcome_2": "/blog/how-to-choose-climbing-shoes"}
    S.loc[Wk.index, ["source", "medium"]] = ["sfmc", "email"]
    S.loc[Wk.index, "campaign"] = step
    S.loc[Wk.index, "ckey"] = ["E:" + s_ for s_ in step]
    S.loc[Wk.index, "landing"] = [path[s_] for s_ in step]

    # --- abandoned cart recoveries (final session of a recovered order)
    F = S[(S.chan == "email_cart") & (S.role == "final")]
    oi = F._o.to_numpy()
    send_t = t0[oi] + _ns(rng.uniform(3600, 3 * 3600, len(F)))
    click_t = F.start.to_numpy() - _ns(rng.uniform(1, 4, len(F)))
    forced_cart = pd.DataFrame({"_sub": cs_i[oi], "send_t": send_t, "click_t": click_t})
    S.loc[F.index, ["source", "medium", "campaign", "ckey", "landing"]] = ["sfmc", "email", "abandoned_cart", "E:abandoned_cart", "/cart"]

    # --- broadcasts: latest newsletter/campaign received in the 14 days before the visit
    E = S[(S.chan == "email_bcast") & (S.person >= 0)].copy()
    sent = bc_out["sent"]
    sp = pd.DataFrame({"person": subs._person.to_numpy()[sent._sub], "_t": sent._t.to_numpy(), "JobID": sent.JobID.to_numpy(),
                       "BatchID": sent.BatchID.to_numpy(), "_sub": sent._sub.to_numpy()})
    sp = sp[sp.person >= 0].sort_values("_t")
    E["_key"] = E.start - pd.Timedelta(minutes=3)
    E["_row"] = E.index
    m = pd.merge_asof(E.sort_values("_key")[["_row", "person", "_key", "start"]], sp, left_on="_key", right_on="_t",
                      by="person", direction="backward", tolerance=pd.Timedelta(days=14))
    m = m[m._t.notna()]
    m = m[stop[m._sub.astype(int)] > m.start.to_numpy()]
    S.loc[E.index[~E.index.isin(m._row)], "chan"] = "direct"
    m["_sub"] = m._sub.astype(int)
    m["_bi"] = m.JobID.map(job_bi)
    m["_link"] = rng.choice(len(LINKS), len(m), p=[l[1] for l in LINKS])
    click_t = m.start.to_numpy() - _ns(rng.uniform(1, 4, len(m)))
    open_t = np.maximum(click_t - _ns(rng.uniform(20, 900, len(m))), m._t.to_numpy() + np.timedelta64(5, "s"))
    bc_out["clicks"] = pd.concat([bc_out["clicks"], pd.DataFrame({"JobID": m.JobID.to_numpy(), "BatchID": m.BatchID.to_numpy(),
                                  "_sub": m._sub.to_numpy(), "_t": click_t, "_link": m._link.to_numpy(), "_bi": m._bi.to_numpy()})],
                                 ignore_index=True)
    bc_out["opens"] = pd.concat([bc_out["opens"], pd.DataFrame({"JobID": m.JobID.to_numpy(), "BatchID": m.BatchID.to_numpy(),
                                 "_sub": m._sub.to_numpy(), "_t": open_t})], ignore_index=True)
    utm = [bc_utm[b] for b in m._bi]
    rows = m._row.to_numpy()
    S.loc[rows, "source"] = [u[0] for u in utm]
    S.loc[rows, "medium"] = [u[1] for u in utm]
    S.loc[rows, "campaign"] = [u[2] for u in utm]
    S.loc[rows, "ckey"] = ["E:" + u[2] for u in utm]
    S.loc[rows, "landing"] = [bc["_paths"].iloc[b][li] for b, li in zip(m._bi, m._link)]
    return forced_welcome, forced_cart


def _events(rng, S, o, o_ts, n_lines, cust_sub, stop):
    n = len(S)
    role = S.role.to_numpy()
    start = S.start.to_numpy()
    oi = np.maximum(S._o.to_numpy(), 0)
    final = role == "final"
    order_t = np.where(final, o_ts[oi], start)
    lines_o = np.where(final, np.minimum(n_lines[o._oi.to_numpy()[oi]], 3), 0)
    n_atc = np.select([final, np.isin(role, ["cart_abandon", "known_abandon", "anon_abandon"]), role == "earlier"],
                      [lines_o, 1 + (rng.random(n) < 0.35), (rng.random(n) < 0.3).astype(int)], 0)
    checkout = np.select([final, role == "cart_abandon", role == "earlier"],
                         [np.ones(n, bool), rng.random(n) < 0.4, rng.random(n) < 0.05], rng.random(n) < 0.3) & (n_atc > 0)
    sid = np.arange(n)
    ev = [pd.DataFrame({"_s": sid, "event_name": "session_start", "_t": start, "value": np.nan})]
    # add_to_cart
    s_atc = np.repeat(sid, n_atc)
    span = (order_t - start)[s_atc] / np.timedelta64(1, "s")
    frac = rng.uniform(0.1, 0.6, len(s_atc))
    t_atc = np.where(final[s_atc], start[s_atc] + _ns(span * frac), start[s_atc] + _ns(rng.uniform(30, 900, len(s_atc))))
    net = o._net.to_numpy()[oi]
    val = np.where(final[s_atc], np.round(net[s_atc] / np.maximum(n_atc[s_atc], 1), 2), np.round(rng.lognormal(np.log(55), 0.6, len(s_atc)), 2))
    ev.append(pd.DataFrame({"_s": s_atc, "event_name": "add_to_cart", "_t": t_atc, "value": val}))
    # begin_checkout
    s_co = sid[checkout]
    span = (order_t - start)[s_co] / np.timedelta64(1, "s")
    t_co = np.where(final[s_co], start[s_co] + _ns(span * rng.uniform(0.7, 0.95, len(s_co))),
                    start[s_co] + _ns(rng.uniform(920, 1500, len(s_co))))
    ev.append(pd.DataFrame({"_s": s_co, "event_name": "begin_checkout", "_t": t_co, "value": np.nan}))
    # purchase (+ some duplicates when the thank-you page is reloaded)
    s_p = sid[final]
    dup = rng.random(len(s_p)) < 0.02
    ev.append(pd.DataFrame({"_s": s_p, "event_name": "purchase", "_t": order_t[s_p], "value": net[s_p]}))
    ev.append(pd.DataFrame({"_s": s_p[dup], "event_name": "purchase", "_t": order_t[s_p[dup]] + _ns(rng.uniform(2, 90, dup.sum())),
                            "value": net[s_p[dup]]}))
    events = pd.concat(ev, ignore_index=True)
    events["_t"] = pd.to_datetime(events._t)
    events = events.sort_values(["_s", "_t"], kind="stable").reset_index(drop=True)

    # Known-user abandoned carts that can trigger the abandoned cart journey
    ka = S[(role == "known_abandon") & S.uid_events.to_numpy()]
    sub = cust_sub.reindex(ka.person.to_numpy()).to_numpy()
    okk = ~np.isnan(sub)
    sub_i = np.where(okk, sub, 0).astype(int)
    last_atc = events[events.event_name == "add_to_cart"].groupby("_s")._t.max()
    t_ka = last_atc.reindex(ka.index).to_numpy()
    okk &= stop[sub_i] > t_ka
    known_abandons = pd.DataFrame({"_sub": sub_i[okk], "_t": t_ka[okk]})
    return events, known_abandons


def _session_numbers(rng, S, events):
    """Cookie ids, session ids and session numbers."""
    order = np.lexsort((S.start.to_numpy(), S._cookie.to_numpy()))
    sn = np.empty(len(S), dtype=int)
    ck = S._cookie.to_numpy()[order]
    first_in_group = np.r_[True, ck[1:] != ck[:-1]]
    grp_start = np.maximum.accumulate(np.where(first_in_group, np.arange(len(ck)), 0))
    sn[order] = np.arange(len(ck)) - grp_start + 1
    cookies, inv = np.unique(S._cookie.to_numpy(), return_inverse=True)
    first_seen = pd.Series(S.start.to_numpy()).groupby(inv).min().to_numpy()
    ids = rng.integers(100_000_000, 2_147_483_647, len(cookies)).astype(str)
    secs = (first_seen.astype("datetime64[s]").astype(np.int64)).astype(str)
    pseudo = np.char.add(np.char.add(ids, "."), secs)
    return pd.DataFrame({"user_pseudo_id": pseudo[inv], "ga_session_number": sn,
                         "ga_session_id": S.start.to_numpy().astype("datetime64[s]").astype(np.int64)})


def _format_events(rng, S, sess, ev):
    s = ev._s.to_numpy()
    is_start = (ev.event_name == "session_start").to_numpy()
    local = utc_to_local(ev._t)
    out = pd.DataFrame({
        "event_date": pd.DatetimeIndex(local).strftime("%Y%m%d"),
        "event_timestamp": ev._t.to_numpy().astype("datetime64[us]").astype(np.int64) + rng.integers(0, 1000, len(ev)),
        "event_name": ev.event_name.to_numpy(),
        "user_pseudo_id": sess.user_pseudo_id.to_numpy()[s],
    })
    uid = np.where(is_start, S.uid_start.to_numpy()[s], S.uid_events.to_numpy()[s])
    out["user_id"] = np.where(uid, S.user_id.to_numpy()[s].astype(str), None)
    out["ga_session_id"] = sess.ga_session_id.to_numpy()[s]
    out["ga_session_number"] = sess.ga_session_number.to_numpy()[s]
    for c in ("source", "medium", "campaign"):
        out[c] = np.where(is_start, S[c].to_numpy()[s], None)
    # landing page with tracking parameters
    src, med, camp = S.source.to_numpy(), S.medium.to_numpy(), S.campaign.to_numpy()
    land = S.landing.to_numpy()
    tagged = ~np.isin(S.chan.to_numpy(), ["organic_search", "direct", "referral", "paid_search"])
    tokens = np.array(["".join(rng.choice(list("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"), 22))
                       for _ in range(5000)])
    gclid = tokens[rng.integers(0, len(tokens), len(S))]
    qs = np.where(tagged, [f"?utm_source={quote(str(a))}&utm_medium={quote(str(b))}&utm_campaign={quote(str(c))}"
                           for a, b, c in zip(src, med, camp)],
                  np.where(S.chan.to_numpy() == "paid_search", np.char.add("?gclid=", gclid), ""))
    page = np.char.add(np.char.add(C.SHOP_DOMAIN, land.astype(str)), qs.astype(str))
    out["page_location"] = np.where(is_start, page[s], None)
    out["device_category"] = S.device_category.to_numpy()[s]
    out["country"] = S.country.to_numpy()[s]
    is_p = (ev.event_name == "purchase").to_numpy()
    out["transaction_id"] = np.where(is_p, S.order_number.to_numpy()[s], None)
    out["value"] = ev.value.round(2).to_numpy()
    out["currency"] = np.where(ev.value.notna(), "EUR", None)
    return out.sort_values("event_timestamp", kind="stable").reset_index(drop=True)


def _daily_report(rng, cal, S, sess, events, opts, has_ecom):
    """GA4 UI-style daily traffic report (all consented sessions) + hidden campaign sessions for ads."""
    n = len(S)
    eng = np.array([R.ENGAGEMENT_RATE.get(c, 0.6) for c in S.chan.map(lambda c: "email" if str(c).startswith("email") else c)])
    engaged = has_ecom | (rng.random(n) < eng)
    cnt = events.groupby(["_s", "event_name"]).size().unstack(fill_value=0).reindex(range(n), fill_value=0)
    rev = events[events.event_name == "purchase"].groupby("_s").value.sum().reindex(range(n), fill_value=0)
    ev_s = pd.DataFrame({
        "day": S.day.to_numpy(), "source": S.source.to_numpy(), "medium": S.medium.to_numpy(), "campaign": S.campaign.to_numpy(),
        "ckey": S.ckey.to_numpy(), "device": S.device_category.to_numpy(), "country": S.country.to_numpy(),
        "sessions": 1, "users": 1, "new_users": (sess.ga_session_number.to_numpy() == 1).astype(int),
        "engaged": engaged.astype(int), "atc": cnt.get("add_to_cart", 0).to_numpy(),
        "checkouts": cnt.get("begin_checkout", 0).to_numpy(), "purchases": cnt.get("purchase", 0).to_numpy(),
        "revenue": rev.to_numpy(), "final_purchase": (S.role.to_numpy() == "final").astype(int)})

    # Anonymous traffic without ecommerce activity
    purchases_day = ev_s.groupby("day").final_purchase.sum().reindex(range(cal.n), fill_value=0).to_numpy()
    cr = 0.019 * cal.event ** 0.35
    total = np.round(purchases_day / cr * rng.lognormal(0, 0.04, cal.n)).astype(int)
    ev_day = ev_s.groupby("day").size().reindex(range(cal.n), fill_value=0).to_numpy()
    anon = np.maximum(total - ev_day, 0)
    dev_p = np.array([0.62, 0.33, 0.05])
    cty = [c for c, _ in ANON_COUNTRIES]
    cty_p = np.array([w for _, w in ANON_COUNTRIES])
    parts = []
    for d in range(cal.n):
        cells, probs = [], []
        for chan, share in R.TRAFFIC_MIX.items():
            res = opts.get(chan, d)
            if res is None:
                continue
            olist, p = res
            for oo, pp in zip(olist, p):
                cells.append((oo[0], oo[1], oo[2], oo[3], chan))
                probs.append(share * pp)
        probs = np.array(probs)
        full = np.outer(np.outer(probs, dev_p).ravel(), cty_p).ravel()
        counts = rng.multinomial(anon[d], full / full.sum())
        nz = np.nonzero(counts)[0]
        ci, rest = np.divmod(nz, len(dev_p) * len(cty))
        di, ki = np.divmod(rest, len(cty))
        sc = counts[nz]
        ch = np.array([cells[i][4] for i in ci])
        er = np.array([R.ENGAGEMENT_RATE[c] for c in ch])
        parts.append(pd.DataFrame({
            "day": d, "source": [cells[i][0] for i in ci], "medium": [cells[i][1] for i in ci],
            "campaign": [cells[i][2] for i in ci], "ckey": [cells[i][3] for i in ci],
            "device": np.array(DEVICES)[di], "country": np.array(cty)[ki], "sessions": sc,
            "users": np.maximum(1, np.round(sc * rng.uniform(0.78, 0.9, len(sc)))).astype(int),
            "new_users": np.round(sc * rng.uniform(0.38, 0.55, len(sc))).astype(int),
            "engaged": rng.binomial(sc, er), "atc": 0, "checkouts": 0, "purchases": 0, "revenue": 0.0, "final_purchase": 0}))
    allx = pd.concat([ev_s] + parts, ignore_index=True)
    allx["ckey"] = allx.ckey.fillna("")

    ads_sessions = allx.groupby(["day", "ckey"], as_index=False)[["sessions", "final_purchase", "revenue"]].sum()
    ads_sessions = ads_sessions[ads_sessions.ckey != ""]

    g = allx.groupby(["day", "source", "medium", "campaign", "device", "country"], as_index=False)[
        ["sessions", "users", "new_users", "engaged", "atc", "checkouts", "purchases", "revenue"]].sum()
    g["users"] = np.minimum(g.users, g.sessions)
    g["new_users"] = np.minimum(g.new_users, g.users)
    daily = pd.DataFrame({
        "Date": cal.days[g.day.to_numpy()].strftime("%Y%m%d"),
        "Session source / medium": g.source + " / " + g.medium,
        "Session campaign": g.campaign,
        "Device category": g.device,
        "Country": g.country,
        "Sessions": g.sessions, "Total users": g.users, "New users": g.new_users, "Engaged sessions": g.engaged,
        "Add to carts": g.atc, "Checkouts": g.checkouts, "Ecommerce purchases": g.purchases,
        "Purchase revenue": g.revenue.round(2)})
    daily = daily.sort_values(["Date", "Sessions"], ascending=[True, False], kind="stable").reset_index(drop=True)
    return daily, ads_sessions
