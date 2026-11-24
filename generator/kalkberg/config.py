"""Global settings for the Kalkberg data generator.

Change the values here to generate a bigger/smaller dataset.
Same SEED + same settings = exactly the same data on every run.
"""
from pathlib import Path

import pandas as pd

SEED = 20231101

# Period covered by the data (inclusive). The webshop launched on START.
START = pd.Timestamp("2023-11-01")
END = pd.Timestamp("2026-10-31")

# Volumes
N_CUSTOMERS = 100_000          # customer accounts (excluding duplicates and test accounts)
TARGET_ORDERS = 400_000        # approximate number of orders
GUEST_ORDER_SHARE = 0.06       # share of orders placed without an account
N_NEWSLETTER_ONLY = 30_000     # newsletter subscribers who never created an account
N_TEST_ACCOUNTS = 35

# Business events (these are "known" to the business and documented in the README)
PLATFORM_MIGRATION = pd.Timestamp("2024-09-02")   # webshop moved to a new e-commerce platform
SEGMENTATION_START = pd.Timestamp("2025-03-01")   # newsletters only sent to engaged subscribers
META_AGENCY_SWITCH = pd.Timestamp("2025-02-01")   # new agency took over Meta Ads
PMAX_SWITCH = pd.Timestamp("2025-02-01")          # Google Shopping replaced by Performance Max

SHOP_DOMAIN = "https://www.kalkberg.example"

OUTPUT_DIR = Path(__file__).resolve().parents[2] / "data"
