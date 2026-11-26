# 0005: The channel of an order, and attribution on GA4 sessions

**Status:** accepted

## Context

Almost every marketing question needs a channel per order: revenue per channel, CAC, lifetime value per acquisition channel, affiliate and influencer profitability. The sources disagree about it:

- The ad platforms each claim conversions by their own rules, and the claims overlap (X-01).
- GA4 knows the sessions before an order, but only for the 82% of orders with cookie consent (GA-06), and only sessions with shopping activity (GA-08).
- Influencer and affiliate orders carry a discount code, which is also what the partner is paid for.

*context.md* also asks to compare attribution models (PM3), so one channel per order is not enough on its own.

## Options considered

1. **The platforms' own conversions.** They overlap and can't be added up: rejected for anything but a side-by-side comparison (`fct_ad_performance`).
2. **GA4 last click only.** Simple and standard, but it ignores discount codes, and 18% of the orders would have no channel at all.
3. **Discount code first, then the last non-direct GA4 click, then direct, else unattributed**, plus a touchpoint table with weights for four attribution models.

## Decision

Option 3.

- `fct_orders.order_channel_key` follows the order of priority above. The code- and click-based views are kept too (`code_channel_key`, `last_click_channel_key`).
- `fct_order_touchpoints` holds every order's journey: sessions of the same person or browser, at most 30 days before the order and after the previous one, with first-click, last-click, linear and position-based weights.
- An order without sessions gets one *no session* touchpoint with its own channel, so the weights of every order add up to 1 in every model.

## Consequences

- Revenue per channel always adds up to total revenue, in every view and every model. The untracked part is visible as *unattributed* (16,0% of orders) instead of being spread over the other channels.
- An influencer or affiliate order counts for the partner even when the customer clicked a Google ad first. That matches how the partner is paid, but it means paid search gets slightly less credit than in GA4's own reports.
- Journeys are a lower bound (only sessions GA4 recorded), which is mentioned as a warning label in the report.
- The lookback window (30 days) is a variable in `dbt_project.yml`, so it can be changed in one place.
