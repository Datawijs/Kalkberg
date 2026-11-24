"""Demand calendar: growth, seasonality, weekdays, Black Friday, sales periods, prices."""
import numpy as np
import pandas as pd

from . import config as C

BLACK_FRIDAYS = [pd.Timestamp("2023-11-24"), pd.Timestamp("2024-11-29"), pd.Timestamp("2025-11-28")]
MONTH_FACTOR = {1: 1.00, 2: 0.85, 3: 1.00, 4: 1.05, 5: 0.95, 6: 0.80,
                7: 0.72, 8: 0.75, 9: 1.05, 10: 1.10, 11: 1.20, 12: 1.25}
WEEKDAY_FACTOR = {0: 1.00, 1: 0.95, 2: 0.95, 3: 1.00, 4: 0.92, 5: 0.95, 6: 1.18}

# Hour-of-day distribution of orders/sessions (local time)
HOUR_WEIGHTS = np.array([1.0, 0.6, 0.3, 0.2, 0.2, 0.3, 0.8, 1.8, 3.0, 3.8, 4.2, 4.6,
                         5.5, 5.4, 4.6, 4.4, 4.5, 4.9, 5.4, 6.4, 7.2, 7.0, 5.2, 2.6])
HOUR_WEIGHTS = HOUR_WEIGHTS / HOUR_WEIGHTS.sum()


class Calendar:
    def __init__(self):
        self.days = pd.date_range(C.START, C.END, freq="D")
        self.n = len(self.days)
        t = np.arange(self.n) / 365.25
        # Startup ramp (webshop launched on START) + yearly growth
        growth = (1 - 0.62 * np.exp(-t / 0.45)) * 1.20 ** t
        month = np.array([MONTH_FACTOR[m] for m in self.days.month])
        weekday = np.array([WEEKDAY_FACTOR[d] for d in self.days.dayofweek])
        self.event = self._event_factor()
        self.weight = growth * month * weekday * self.event          # total demand (guests, traffic)
        season = month * weekday * self.event
        # New-customer acquisition: short launch ramp, then slowly flattening
        acq = (1 - 0.45 * np.exp(-t / 0.25)) * 0.93 ** t * season
        self.cum = np.concatenate([[0.0], np.cumsum(self.weight)])
        self.cum_season = np.concatenate([[0.0], np.cumsum(season)])   # repeat orders (growth comes from the base)
        self.cum_acq = np.concatenate([[0.0], np.cumsum(acq)])
        self.promo = self._promo_matrix()

    # ------------------------------------------------------------------
    def idx(self, ts):
        """Day index for timestamps (vectorised)."""
        return ((pd.DatetimeIndex(ts).normalize() - C.START).days).to_numpy()

    def _event_factor(self):
        f = np.ones(self.n)
        d = self.days

        def bump(start, end, factor):
            mask = (d >= pd.Timestamp(start)) & (d <= pd.Timestamp(end))
            f[mask] *= factor

        for bf in BLACK_FRIDAYS:
            bump(bf - pd.Timedelta(days=7), bf - pd.Timedelta(days=1), 1.35)
            bump(bf, bf, 3.2)
            bump(bf + pd.Timedelta(days=1), bf + pd.Timedelta(days=2), 1.9)
            bump(bf + pd.Timedelta(days=3), bf + pd.Timedelta(days=3), 2.4)   # Cyber Monday
        for y in (2023, 2024, 2025):
            bump(f"{y}-12-01", f"{y}-12-18", 1.25)
            bump(f"{y}-12-19", f"{y}-12-23", 0.90)
            bump(f"{y}-12-24", f"{y}-12-26", 0.45)
            bump(f"{y}-12-27", f"{y}-12-31", 0.85)
        for y in (2024, 2025, 2026):
            bump(f"{y}-01-02", f"{y}-01-15", 1.30)      # January sale
            bump(f"{y}-07-01", f"{y}-07-03", 1.80)      # summer sale launch
            bump(f"{y}-07-04", f"{y}-07-21", 1.25)
        for y in (2025, 2026):
            bump(f"{y}-03-20", f"{y}-04-05", 1.15)      # spring outdoor promo
        return f

    def _promo_matrix(self):
        """Automatic discount % per day x category (no code needed)."""
        from .reference import CATEGORIES
        names = [c[0] for c in CATEGORIES]
        p = np.zeros((self.n, len(names)))
        d = self.days

        def promo(start, end, pct_by_cat):
            mask = (d >= pd.Timestamp(start)) & (d <= pd.Timestamp(end))
            for cat, pct in pct_by_cat.items():
                p[mask, names.index(cat)] = pct

        no_promo = {"Gift cards", "Books & guides"}
        for bf in BLACK_FRIDAYS:
            pct = {c: (0.25 if c in ("Climbing shoes", "Crash pads") else 0.15) for c in names if c not in no_promo}
            promo(bf - pd.Timedelta(days=3), bf + pd.Timedelta(days=3), pct)
        for y in (2024, 2025, 2026):
            promo(f"{y}-01-02", f"{y}-01-15", {"Clothing": 0.20, "Climbing shoes": 0.15})
            promo(f"{y}-07-01", f"{y}-07-21", {"Clothing": 0.30, "Climbing shoes": 0.20, "Chalk bags & buckets": 0.20})
        for y in (2025, 2026):
            promo(f"{y}-03-20", f"{y}-04-05", {"Crash pads": 0.15, "Ropes": 0.15})
        return p

    @staticmethod
    def price_index(dates):
        """List price level relative to the current (2026) price list. Prices change on 15 January."""
        dates = pd.DatetimeIndex(dates)
        y = np.where(dates < pd.Timestamp("2024-01-15"), 2023,
             np.where(dates < pd.Timestamp("2025-01-15"), 2024,
             np.where(dates < pd.Timestamp("2026-01-15"), 2025, 2026)))
        return np.select([y == 2023, y == 2024, y == 2025], [0.92, 0.95, 0.98], 1.0)

    def sample_days(self, rng, n, lo=None, hi=None, kind="total"):
        """Sample day indices proportional to demand, optionally within [lo, hi) per row."""
        cum = {"total": self.cum, "season": self.cum_season, "acq": self.cum_acq}[kind]
        lo = np.zeros(n, dtype=int) if lo is None else np.asarray(lo)
        hi = np.full(n, self.n) if hi is None else np.asarray(hi)
        u = cum[lo] + rng.random(n) * (cum[hi] - cum[lo])
        return np.clip(np.searchsorted(cum, u, side="right") - 1, lo, hi - 1)


def sample_time_of_day(rng, n):
    """Seconds after midnight, following the hour-of-day pattern."""
    hours = rng.choice(24, size=n, p=HOUR_WEIGHTS)
    return hours * 3600 + rng.integers(0, 3600, size=n)


def local_to_utc(local):
    """Europe/Brussels naive timestamps -> UTC naive timestamps."""
    s = pd.Series(pd.DatetimeIndex(local))
    loc = s.dt.tz_localize("Europe/Brussels", ambiguous=np.zeros(len(s), dtype=bool), nonexistent="shift_forward")
    return loc.dt.tz_convert("UTC").dt.tz_localize(None).to_numpy()


def utc_to_local(utc):
    s = pd.Series(pd.DatetimeIndex(utc))
    return s.dt.tz_localize("UTC").dt.tz_convert("Europe/Brussels").dt.tz_localize(None).to_numpy()


def us_datetime_text(ts):
    """Format timestamps as 'M/d/yyyy h:mm:ss AM' (platform independent, vectorised)."""
    s = pd.Series(pd.DatetimeIndex(ts))
    h = s.dt.hour
    h12 = ((h + 11) % 12) + 1
    ampm = np.where(h < 12, "AM", "PM")
    return (s.dt.month.astype(str) + "/" + s.dt.day.astype(str) + "/" + s.dt.year.astype(str) + " "
            + h12.astype(str) + ":" + s.dt.minute.astype(str).str.zfill(2) + ":"
            + s.dt.second.astype(str).str.zfill(2) + " " + ampm).to_numpy()
