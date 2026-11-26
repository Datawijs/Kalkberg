# Step 2: Profiling, what is wrong with the raw data?

## What

Before we clean anything, we find out what the bronze data really looks like. Every problem we find goes into an **issue register**: what the problem is, the query that proves it, which business questions it affects, and what we decide to do about it.

The register is the bridge between bronze and silver. Every transformation in silver must point back to an issue in this register, and every issue must have a decision.

> [!NOTE]
> The README states that there is deliberately no list of data problems. We work as we would on a real project: we don't look at how the data was generated, and an issue only goes into the register when a query on the data proves it.

## How

We profile in rounds: first broad and generic, then targeted, then a few follow-ups for questions the targeted round raised.

| Round | Script | Results |
| --- | --- | --- |
| 1. Generic profile of every column | [`01-profile-all-tables.sql`](../profiling/01-profile-all-tables.sql) | [`results/round-1/`](../profiling/results/round-1/) |
| 2. Targeted checks, one question per check | [`02-run-targeted-checks.sql`](../profiling/02-run-targeted-checks.sql) | [`results/round-2/`](../profiling/results/round-2/) |
| 3. Follow-ups on open questions from round 2 | [`03-run-follow-up-checks.sql`](../profiling/03-run-follow-up-checks.sql) | [`results/round-3/`](../profiling/results/round-3/) |

All scripts are run from the project folder, for example:

```powershell
psql -h localhost -U [username] -d kalkberg -f profiling/01-profile-all-tables.sql
```

### Round 1: a generic profile of every column

Round 1 runs the same checks on every column of every bronze table, without any assumptions about what the data should contain.

| Level | What is measured | What it helps us find |
| --- | --- | --- |
| Table | Row count, exact duplicate rows | Rows that were exported or loaded twice |
| Column | Empty values (`NULL` and `''`) | Missing data, optional fields that are always empty |
| Column | Distinct values, min/max, shortest and longest value | Keys that are not unique, values outside the expected range, cut-off text |
| Column | Leading/trailing spaces, upper- and lowercase letters | The same value written in several ways |
| Column | How many values look like an integer, a decimal with a point or a comma, an ISO date or timestamp, or another date notation | Text columns with more than one notation, and whether they can be converted to a type |
| Value | The 25 most frequent values per column, with their share | Placeholder values, unexpected categories, values that dominate a column |

The checks are implemented once, as a stored procedure ([`profiling/00-create-profiling-objects.sql`](../profiling/00-create-profiling-objects.sql)) that loops over all tables and columns. The results are stored in a separate `profiling` schema and exported to CSV. The whole run took about 9 minutes, mostly spent on the large GA4 and Marketing Cloud tables.

![Terminal output of round 1: one "profiled in" line per bronze table, from a few seconds for the shop tables to about 2,5 minutes for ga4.events and sfmc.sent, a total time of 8 minutes 52 seconds, and the three COPY lines of the export (20, 211 and 3.376 rows)](img/02-profiling-run.png)

#### What round 1 showed

Round 1 found no exact duplicate rows in any table, but it gave plenty of signals. A signal is not yet an issue: some can be explained, and for most we still need to know *how big* the problem is. Each signal is followed up by one or more checks in round 2.

| Source | Signal in round 1 | Evidence (round 1) | Round 2 check |
| --- | --- | --- | --- |
| ads | 4 rows in the Google Ads report where `day` is not a date | `day`: 5.465 of 5.469 values are ISO dates, max value `Total: Shopping`; `campaign` has the value `--` | `ads_01` |
| ads | Google Ads numbers contain thousands separators | `cost` min `1,000.25`; 5.456 `impressions` match the "comma" pattern (`1,028`) | `ads_02` |
| ads | Meta rows without purchases | `purchases`: 6 empty values | `ads_04` |
| ga4 | The same traffic source is written in many ways | `source`: `facebook`, `Facebook`, `fb`, `meta`, `ig`, `instagram`, `sfmc`, `SFMC`, …; `medium`: `paid-social`, `paid_social`, `paidsocial`, `email`, `Email`, `aff`, … | `ga4_08` |
| ga4 | Campaign names in two styles, and an unfilled template | `Retargeting - Viewed or ATC 14d` and `retargeting_viewed_or_atc_14d`; `{{campaign.name}}` on 22.362 daily traffic rows | `ga4_08`, `sfmc_10` |
| ga4 | Traffic from countries Kalkberg doesn't ship to | `country`: `United States`, `United Kingdom` and `(not set)` together on about 26% of daily traffic rows | `ga4_09` |
| ga4 | `event_date` goes one day past the data period | `event_date` max `20261101` | `ga4_02` |
| ga4 | More purchase events than transactions | 335.646 purchase events, 329.078 distinct `transaction_id`s | `ga4_03` |
| ga4 | `user_id` looks like the shop's `customer_id` | Same range (100001 to 201535) | `ga4_07` |
| shop, ga4 | Two order number formats | `KB-24-000001` and `KB159140`, in both `orders.order_number` and `events.transaction_id` | `shop_11`, `ga4_04`, `ga4_05` |
| sfmc | Timestamps in US notation, time zone unknown | All 11 timestamp columns match `M/D/YYYY h:mm:ss AM/PM` | `sfmc_01` to `sfmc_03` |
| sfmc | More subscriber records than people | 94.497 subscribers, 93.301 distinct keys, 89.843 distinct emails; the key is sometimes a number, sometimes an email address | `sfmc_04`, `sfmc_05`, `x_02` |
| sfmc | Typos in email domains | `gmial.com` (364), `hotmial.com` (73), `icloud.co` (72), `outlok.com` (70), `telnet.be` (65) | `sfmc_06` |
| sfmc | Many repeated opens | 740.384 of 3.300.814 opens are not unique; the subscribers with the most opens are mostly `icloud.com` addresses | `sfmc_08`, `sfmc_09` |
| shop | Countries in many notations | `customers.country_code`: 28 distinct values (`BE`, `Belgium`, `België`, `Belgique`, `be`, …); `orders.shipping_country`: 10 | `shop_01` |
| shop | Emails with uppercase letters, possibly the same person twice | 3.325 emails contain uppercase letters, and the unique constraint on `email` is case-sensitive | `shop_02` to `shop_04` |
| shop | Names written inconsistently | `first_name`: 1.034 with leading/trailing spaces; values like `adrien` and `ZIMMERMANN` | `shop_08` |
| shop | Phone numbers in several notations | 70.025 distinct values, 30.458 empty, mixed notations | `shop_09` |
| shop | Placeholder and impossible birth dates | `1900-01-01` on 1.010 customers; max `2026-10-28` | `shop_10` |
| shop | Possible test data | `last_name` value `Account`; discount code `TEST100` (71 orders); payment method `Manual` (101 orders); `order_total` min `0.00` | `shop_05` to `shop_07` |
| shop | Discount codes in several notations | 17 distinct values, such as `WELCOME10`, `welcome10`, `Welcome10`, and `WELCOME10` with a leading space | `shop_17` |
| shop | Catalogue gaps | 39 variants without `unit_cost`; 343 distinct names for 346 products, 2 with a trailing space | `shop_21`, `shop_22` |

Round 1 can't show everything. *context.md* asks whether the platform migration on 02/09/2024 changed anything in the data, and whether the sources agree with each other. Those questions need checks that combine columns and tables (`shop_12` to `shop_14`, `x_01`).

### Round 2: targeted checks

Round 2 checks one question at a time, using what we now know about the data. Each check is a view in the `profiling` schema, grouped per source in [`profiling/checks/`](../profiling/checks/):

| File | Checks | Examples of questions |
| --- | --- | --- |
| [`shop.sql`](../profiling/checks/shop.sql) | `shop_01` to `shop_22` | Do several accounts belong to the same person? Do order amounts add up? Did the order timestamps change at the migration? Are influencer codes used outside the contract period? |
| [`ads.sql`](../profiling/checks/ads.sql) | `ads_01` to `ads_05` | What is one row in each report? Which number notations are used? Are there gaps in a campaign's period? |
| [`ga4.sql`](../profiling/checks/ga4.sql) | `ga4_01` to `ga4_10` | Which share of shop orders can be found in GA4? Are purchases counted twice? Which shop amount is the GA4 purchase value? |
| [`sfmc.sql`](../profiling/checks/sfmc.sql) | `sfmc_01` to `sfmc_10` | In which time zone are the timestamps? Are duplicate subscribers the same person? Which opens come from machines rather than people? |
| [`cross_source.sql`](../profiling/checks/cross_source.sql) | `x_01`, `x_02` | Do the shop, GA4, Google Ads and Meta agree on orders and revenue per month? How do customers link to subscribers? |

Every view has a comment with the question it answers, so the checks are also easy to browse in a database tool. The runner exports each view to its own CSV file. The Marketing Cloud checks are the slowest, because they read and compare millions of timestamps.

Two checks deserve a closer look, because they turned a vague suspicion into hard evidence.

**The platform migration changed the time zone of the shop's timestamps.** For every order that GA4 also recorded, we compared the shop's timestamp with GA4's, which is always in UTC (`shop_12`). Until August 2024 the shop is 1 hour ahead of UTC in winter and 2 hours in summer: Belgian local time. From September 2024 the difference is 0, every single month: UTC. The hour-of-day profile confirms it (`shop_13`): the evening peak in orders moves from 20:00–21:00 to 18:00–19:00 after the migration, while customers obviously didn't change their habits overnight.

**Marketing Cloud writes its timestamps 6 hours behind UTC, all year round.** We matched email clicks with GA4 sessions from email by the same customer within 12 hours (`sfmc_03`). In every month, the large majority of pairs is exactly 6 hours apart, in summer and in winter. Marketing Cloud uses a fixed UTC−6 without summer time. That explains why newsletters seem to be delivered between 02:00 and 04:00 (`sfmc_02`): that's between 09:00 and 12:00 in Belgium, depending on summer or winter time.

### Round 3: follow-up checks

Round 2 left six questions open: findings that were clearly real, but where we couldn't decide what to do until we understood them. Round 3 ([`checks/follow_up.sql`](../profiling/checks/follow_up.sql)) checks them one by one; the answers are listed under [Questions answered in round 3](#questions-answered-in-round-3) below.

Round 3 is a good example of why you don't decide too early. Three of the six "problems" turned out to be no problem at all: rounding differences of a few cents, a purchase value that is consistent once you know free shipping exists, and "duplicate" sends that are in fact automated emails going out repeatedly. Fixing them after round 2 would have broken correct data.

## Why

### Why profile before cleaning

If you start cleaning straight away, you only fix the problems you happen to notice, and you fix them in the place where you notice them, often a report. Profiling first gives a complete picture. It lets us decide per problem whether to fix it, flag it, or accept it, and it lets us explain to the business which numbers need a warning label.

### Why a generic first round

A generic profile has no blind spots caused by our own expectations: it runs the same checks on every column, including the ones we would never think of looking at. The targeted round only works well once you know where to look.

### Why a stored procedure and a separate schema

| Choice | Reason |
| --- | --- |
| One procedure for all tables | The checks are written and reviewed once and are identical for every column. Adding a table to bronze needs no extra profiling code. |
| Format checks with regular expressions instead of casting | A failed cast stops the query at the first bad value. Counting matches per format shows *how many* values use each notation, which is exactly what we need to decide how to convert them in silver. |
| A `profiling` schema | Bronze stays read-only. The profiling schema is a workbench, not a medallion layer: nothing downstream reads from it, and it can be dropped at any time. |
| Results exported to CSV in the repository | The evidence behind every issue stays available next to the documentation, also for readers without a database. The CSV files are machine output, so they keep the database notation (ISO dates, decimal point). |
| Commit after every table | Profiling the large tables takes time. If the run is interrupted, the finished tables don't have to be done again. |

### Why the targeted checks are views

| Choice | Reason |
| --- | --- |
| One view per question | Each check can be read, run and discussed on its own. The evidence for an issue is then a single, named query. |
| Recreated on every run | The runner drops and recreates the views, so a changed check never runs in an old version. |
| Thousands separators simply removed, no other cleaning | The cross-source comparison only needs to be roughly right to show where sources disagree. The real conversion rules are decided in silver, based on this register. |
| Marketing Cloud timestamps read "as written" | We don't assume a time zone, because finding it is one of the checks. The helper function `profiling.sfmc_timestamp` reads the clock time exactly as Marketing Cloud wrote it, whatever the time zone of the database session. |
| Time zones proven by comparing sources | A time zone can't be seen in a single timestamp. Comparing the same moment as recorded by two systems, one of which is known to use UTC (GA4), turns an assumption into evidence. |

## Issue register

**Decisions** use five words:

| Decision | Meaning |
| --- | --- |
| **Fix** | Corrected in silver. The correction is tested. |
| **Flag** | Kept as it is, but marked, so reports can show or exclude it and explain it with a warning label. |
| **Exclude** | Removed from reporting in silver or gold. |
| **Accept** | No action needed, but documented so nobody is surprised. |

**Affects** refers to the questions in [context.md](../context.md): **M** = Management, **PM** = Performance marketing, **E** = Email and CRM, **C** = Customers and products, **F** = Finance, **D** = Data and trust. *PM3* is the third question of Performance marketing.

### Webshop (shop)

| ID | Issue | Evidence | Affects | Decision |
| --- | --- | --- | --- | --- |
| SH-01 | **Country in 28 notations.** Customers use ISO codes, English, Dutch, French and German names, in upper- and lowercase (`BE`, `Belgium`, `België`, `Belgique`, `be`, …). Shipping countries use ISO codes and English names. | `shop_01` | C10, PM10 | **Fix**: map every notation to the ISO code (BE, NL, FR, DE, LU) with a mapping table; test that only those five remain. |
| SH-02 | **Time zone changed at the platform migration.** Timestamps before 02/09/2024 are Belgian local time, from 02/09/2024 they are UTC. Applies to orders and customer accounts. | `shop_12`, `shop_13` | M1, M7, C1, C2, D3 and every time-of-day or day-boundary analysis | **Fix**: interpret timestamps before the migration as Europe/Brussels and after it as UTC. Store one UTC timestamp plus the Belgian local date and time. |
| SH-03 | **Return timestamps have no daily rhythm.** Every hour of the day has about 4% of the return requests, before and after the migration. The time of day carries no information. | `shop_13` | F4 | **Accept**: use the date of a return only, never the time. Durations are counted in days. |
| SH-04 | **Two order number formats.** `KB100001` to `KB159140` on the old platform (up to 01/09/2024), `KB-24-000001` and on (year + number) on the new platform. Both are unique, and GA4 uses the same numbers. | `shop_11`, `ga4_05` | D3 | **Accept**: keep `order_number` as the business key. Add the platform (old/new) as an attribute. |
| SH-05 | **Test data in production.** 35 test customers: first names like *Test*, *QA* and *Test Klant*, emails like `test+N@kalkberg.example` and `qa.kalkberg+N@gmail.com`. All 101 orders paid with `Manual` are test orders: they include all 71 `TEST100` orders and all 68 orders with a total of 0,00, and every one of them belongs to a test customer. Round 2 found 31 test customers; round 3 showed that the remaining `Manual` orders come from 4 more QA accounts (`QA Order`, `qa.kalkberg+N@gmail.com`). | `shop_05` to `shop_07`, `f_03` | Every count of customers, orders and revenue | **Exclude**: mark customers as test on their name or email pattern, and orders as test when the customer is a test customer or the payment method is `Manual`. Leave both out of gold. |
| SH-06 | **Duplicate accounts.** 376 accounts share an email address with another account once uppercase is ignored (the shop's uniqueness check is case-sensitive). 1.093 people have 2 accounts with the same name, birth date and postal code, usually with an email that only differs in case or has an extra number. | `shop_02` to `shop_04` | C1, C2, M1, M4, M5, M6 | **Fix**: build a *person* key in silver. Match on the normalised email first, then on name + birth date + postal code (placeholder birth dates excluded). Keep the account ids for traceability. |
| SH-07 | **Guest orders are not always new customers.** 24.000 orders were placed without an account, by 23.755 email addresses. 7.077 of those orders (6.832 email addresses) come from people who also have an account. | `shop_16` | C9, M1, M5 | **Fix**: link guest orders to the same person key via the normalised email (see SH-06). |
| SH-08 | **Names written inconsistently.** 1.034 first names with leading or trailing spaces; about 1.600 first and last names in all lowercase and 2.000 to 2.500 in all uppercase. | `shop_08` | None (display only) | **Fix**: trim spaces. Names are personal data and aren't needed in reports, so they don't go to gold. |
| SH-09 | **Phone numbers in 15 notations**, 30.458 empty. | `shop_09` | None | **Accept**: not used in any analysis and not carried to gold. |
| SH-10 | **Placeholder and impossible birth dates.** 1.010 customers born on 01/01/1900; 291 younger than 14 at sign-up (birth dates between 2023 and 2026); 3 born after their account was created. 25.042 are empty. | `shop_10` | SH-06 matching; any age analysis | **Fix**: set placeholder and impossible birth dates to empty. |
| SH-11 | **Discount codes in several notations.** `WELCOME10` appears in 4 notations (including one with a leading space), every influencer code also in lowercase. | `shop_17` | F3, PM7, PM8 | **Fix**: trim and uppercase every code before using it. |
| SH-12 | **Rounding differences in order totals.** For 808 orders, `order_total` is not exactly `subtotal - discount_total + shipping_fee`: it is 1 to 5 cents lower or 1 to 2 cents higher. The differences occur in every period, payment method and status, with or without a discount code. Everywhere else, `subtotal` is the sum of quantity × price and `discount_total` the sum of the line discounts. | `shop_15`, `f_01`, `f_02` | M1, F2 | **Accept**: `order_total` is what the customer paid, so it stays the revenue amount. Silver tests that the difference is never more than 0,05. |
| SH-13 | **Duplicate products.** 5 pairs of products with the same name: 2 pairs only differ by a trailing space, 3 have exactly the same name. 3 variants were sold before their product's launch date. | `shop_21`, `shop_22` | C4, C6 | **Fix**: trim product names. Keep both products of a pair (each has its own sales history), and report on the cleaned name where it matters. **Accept** the 3 early sales. |
| SH-14 | **Variants without a purchase cost.** 39 variants have no `unit_cost`, mostly sizes of climbing shoes; for most of them the other sizes of the same product do have a cost. | `shop_21`, `shop_22` | C6, F2 | **Fix**: use the median cost of the other sizes of the same product, and mark the cost as estimated. Products without any known cost keep an unknown margin. |

### Ad platforms (ads)

| ID | Issue | Evidence | Affects | Decision |
| --- | --- | --- | --- | --- |
| AD-01 | **Total rows in the Google Ads export.** 4 rows (`Total: Account`, `Total: Search`, `Total: Shopping`, `Total: Performance Max`) sit between the daily data. Summing the report would count all spend twice. | `ads_01` | M3, M4, PM1, F1 | **Exclude**: keep only rows where `day` is a date. |
| AD-02 | **Google Ads numbers in US notation with thousands separators**, such as `1,000.25` and `1,028`: in `cost` (167 values), `impressions` (5.456), `clicks` (1.345) and `conv_value` (2.944). | `ads_02` | M3, PM1, F1 | **Fix**: remove the thousands separator, then convert with the decimal point. |
| AD-03 | **Meta purchases missing on 6 days**, while the purchase value on those days is not 0. | `ads_04` | PM1 | **Flag**: keep as unknown, don't replace with 0. |
| AD-04 | **Meta ad set names are not unique**: 4 ad set names are used in more than one campaign. | `ads_03` | PM1, PM6 | **Accept**: identify an ad set by campaign + ad set name. |

### Google Analytics 4 (ga4)

| ID | Issue | Evidence | Affects | Decision |
| --- | --- | --- | --- | --- |
| GA-01 | **The same traffic source in many spellings.** 46 source/medium combinations for about 10 real channels. Meta alone appears as `facebook`, `Facebook`, `fb`, `ig`, `instagram` and `meta`, with medium `cpc`, `paid-social`, `paid_social`, `paidsocial` or `social`; email as `sfmc`, `SFMC` or `newsletter` with `email` or `Email`; also `influencer`/`Influencer` and `affiliate`/`aff`. | `ga4_08`, `sfmc_10` | PM1 to PM3, PM7, PM8, M4, M6, D5 | **Fix**: a channel mapping table from source, medium and campaign to one channel list, shared with the budget (`dim_channel`). |
| GA-02 | **Two naming styles for Meta campaigns.** Until 31/01/2025 campaigns are tagged in snake_case (`retargeting_viewed_or_atc_14d`), from 01/02/2025, when the new agency started, mostly with the exact Meta campaign name. Influencer `lena.sends` is also tagged as `lena_sends`. | `ga4_08` | PM3, PM6, PM7 | **Fix**: map both styles to the campaign name used in Meta, in the same mapping table. |
| GA-03 | **Unfilled campaign template.** 49.754 Meta sessions have the campaign `{{campaign.name}}`, all from 01/02/2025 onwards: the new agency's dynamic URL parameter didn't work on part of the ads. | `ga4_08` | PM3, PM6 | **Flag**: the channel is still known (paid social); the campaign becomes *Unknown (template not filled)*. |
| GA-04 | **Traffic from the United States and the United Kingdom without any purchase**: 973.695 sessions (5,8% of all sessions in the traffic report), 0 purchases, slightly lower engagement. Kalkberg doesn't ship there. `(not set)` has 333.600 sessions and does convert (0,99%). | `ga4_09` | PM10, conversion rates in general | **Exclude** US and UK from conversion rates and traffic KPIs, show them separately. **Accept** `(not set)` as country *Unknown*. |
| GA-05 | **Purchases sent twice.** 6.568 transactions have 2 purchase events, from the same device and session, with the same value, mostly within a minute (probably a reload of the confirmation page). The traffic report counts the duplicates too. | `ga4_03`, `ga4_10` | PM2, D1 | **Fix**: keep one purchase per `transaction_id`. Take GA4 purchases and revenue from the deduplicated events, not from the traffic report. |
| GA-06 | **GA4 sees about 82% of the shop's orders**, every month, before and after the migration. That fits the cookie consent described in *context.md*. | `ga4_04` | PM2, PM3, D1, D2 | **Flag**: the shop is the source of truth for orders and revenue. GA4 is used for behaviour and channel *shares*, with a warning label. |
| GA-07 | **The GA4 purchase value excludes shipping.** At first sight it had two definitions (equal to `order_total` for 185.376 transactions, to `order_total - shipping_fee` for 143.059). Round 3 showed that every transaction where it equals `order_total` had free shipping: the value is always the order total without shipping. The 1% that matches neither is explained by the rounding differences of SH-12. | `ga4_06`, `f_04` | D1, PM2 | **Accept**: when comparing with GA4, compare with the shop's revenue *without* shipping. |
| GA-08 | **The event export is not all traffic.** It only contains 4 events (`session_start`, `add_to_cart`, `begin_checkout`, `purchase`) and about 20 times fewer sessions than the traffic report, while the number of purchases is the same. It looks like an export of sessions with shopping activity only. | `ga4_01`, `ga4_10` | PM4, PM10 | **Accept**, with a warning: sessions and conversion rates come from the traffic report; journeys and attribution come from the events, and only cover sessions with shopping activity. |

### Marketing Cloud (sfmc)

| ID | Issue | Evidence | Affects | Decision |
| --- | --- | --- | --- | --- |
| MC-01 | **Timestamps in US notation** `M/D/YYYY h:mm:ss AM/PM` in all 11 timestamp columns (the second number goes above 12, the first never does). | `sfmc_01` | All email questions | **Fix**: read with the explicit US format. |
| MC-02 | **Timestamps 6 hours behind UTC, all year round** (fixed UTC−6, no summer time). | `sfmc_02`, `sfmc_03` | E4, E8, D4 | **Fix**: add 6 hours to get UTC, then convert to Belgian time like every other source. |
| MC-03 | **More subscriber records than people.** 94.497 records for 89.582 email addresses. For 3.230 addresses there is one record keyed on the customer number and a second one with another key: the person subscribed twice. | `sfmc_04`, `sfmc_05` | E1, E7 | **Fix**: count people, not records: one person per normalised email address. A person counts as reachable when at least one of their records is active. |
| MC-04 | **Three kinds of subscriber key.** 41.654 keys are a shop customer number (all of them exist in the shop), 22.006 are an email address, and 30.837 follow the pattern two letters, hyphen, six digits (such as `NL-100022`). The numbers in that last kind are not customer numbers: they are newsletter sign-ups without a shop account. 5.889 of those email addresses do appear in the shop. | `sfmc_04`, `f_06` | E7, D4 | **Accept**: the key can't be used to link to the shop. Link subscribers to customers by person, through the normalised email address (see MC-03 and X-02). |
| MC-05 | **Typos in email domains**: `gmial.com`, `hotmial.com`, `icloud.co`, `outlok.com` and `telnet.be`. 644 subscribers (exactly the ones with status *Held*) and 1.034 shop customers. Every send to these addresses bounces. | `sfmc_06`, `sfmc_09` | E1 | **Flag**: don't correct email addresses (we can't be sure what was meant), but report them as undeliverable. Recommendation for the business: validate email addresses at sign-up. |
| MC-06 | **Machine opens.** `icloud.com` addresses have an open rate of 88,4%, against 52% to 58% for every other domain, while their click rate is normal. This is typical for Apple Mail Privacy Protection, which opens every email automatically. | `sfmc_09`, `sfmc_08` | E2, E5, E6 | **Flag**: report opens with and without `icloud.com`, and use clicks as the main engagement measure. |
| MC-07 | **Repeated sends of journey emails.** For 63.488 combinations of email job and subscriber there is more than one send row. All of them are automated journey emails (*TriggeredSend*), almost always sent on different days, up to 57 times to the same person. An abandoned-cart email, for example, is one job that goes out every time someone leaves a cart. These are real, separate sends, not duplicates. | `sfmc_07`, `f_05` | E2, E3, E5 | **Accept**: one send is identified by job, subscriber *and* send time. Opens and clicks are linked to the send that came just before them. |

### Across sources

| ID | Issue | Evidence | Affects | Decision |
| --- | --- | --- | --- | --- |
| X-01 | **Every platform tells a different story.** In October 2026, for example: 15.803 orders in the shop, 12.891 in GA4, 2.544 conversions in Google Ads and 3.033 purchases in Meta. The ad platforms only count conversions they attribute to themselves, with their own rules, and those overlap. | `x_01` | PM2, D1, F7 | **Flag**: the shop is the source of truth. Platform numbers are shown next to it, never added up, with a warning label. |
| X-02 | **Subscribers who did not opt in.** 3.404 shop customers have a Marketing Cloud subscription with the same email address, while `marketing_opt_in` in the shop is false. 41.654 customers link by customer number, another 18.252 only by email address. | `x_02` | E7 | **Fix**: link customers and subscribers by person (normalised email address). **Flag** the opt-in mismatch for the business. |

## Checked, and in order

Just as useful as the issues: what we checked and found to be fine. Silver can rely on these without extra fixes.

| Check | Result | Evidence |
| --- | --- | --- |
| Exact duplicate rows | None, in any table | Round 1 |
| Returns versus their order lines | Never more returned than ordered, never more refunded than paid, never received before requested or requested before the order | `shop_20` |
| Order status versus returns | Refunded and partially refunded orders always have returns; completed orders with returns are rejected or still in transit (refund 0,00) | `shop_18` |
| Orders versus account creation | No order was placed before the customer's account was created | `shop_14` |
| Open orders | The 1.513 *processing* and 2.057 *shipped* orders were all placed in the last month of the data | `shop_19` |
| Influencer codes versus contracts | Codes are never used before the contract starts, and never later than 14 days after it ends. That confirms the rule in the contracts sheet. | `shop_17` |
| GA4 transactions versus shop orders | Every GA4 transaction exists in the shop | `ga4_05` |
| GA4 `user_id` | Always an existing shop customer number | `ga4_07` |
| GA4 `event_date` | The Belgian date of the event (97.628 events fall on another date in UTC) | `ga4_02` |
| GA4 traffic source | Only filled on `session_start`; other events get it through their session | `ga4_01` |
| GA4 logged-in customers | `user_id` is filled from the first month of data | `f_07` |
| Ad reports | One row per day and campaign (Google) or per day, campaign and ad set (Meta); no gaps in any campaign's period | `ads_03`, `ads_05` |
| Campaign changes | Google Shopping stops on 31/01/2025 and Performance Max starts on 01/02/2025; the Meta campaign structure changes around the agency switch. Both match *context.md*. | `ads_05` |
| Marketing Cloud links | Every send, open and click points to an existing job and subscriber; statuses match the unsubscribe events. Only 24 clicks have no open (normal when images are blocked). | `sfmc_07` |

## Questions answered in round 3

| Issue | Question after round 2 | Answer from round 3 | Check |
| --- | --- | --- | --- |
| SH-05 | Are the `Manual` orders without a test customer test orders as well? | Yes. They belong to 4 QA accounts that the first test rule missed, because their email address is on gmail.com. | `f_03` |
| SH-12 | What do the 808 orders whose total doesn't add up have in common? | Nothing, except that the difference is never more than a few cents: rounding. | `f_01`, `f_02` |
| GA-07 | Does the GA4 purchase value include shipping in some periods and not in others? | No, it never includes shipping. Where it equals the order total, shipping was free. | `f_04` |
| MC-04 | What are the subscriber keys that are neither a customer number nor an email address? | Newsletter sign-ups without a shop account, with keys like `NL-100022`. | `f_06` |
| MC-07 | What differs between duplicate send rows? | The send time: they are automated journey emails sent to the same person on different days. | `f_05` |
| — | From when does GA4 know the logged-in customer (`user_id`)? Email clicks could only be matched to GA4 sessions from September 2024. | From the start: every month, about 1 in 4 sessions and 5 in 6 purchases have a `user_id`. The September 2024 limit comes from Marketing Cloud, where only part of the subscribers carry a customer number as key. Linking subscribers to customers by email address (MC-03, X-02) removes that limit. | `f_07` |

## What this means for silver

The register gives silver a clear list of work. In broad lines:

- **One way of writing everything**: countries, discount codes, numbers and timestamps get one notation and one time zone (SH-01, SH-02, SH-11, AD-02, MC-01, MC-02).
- **People instead of records**: one person key across shop accounts, guest orders and Marketing Cloud subscribers (SH-06, SH-07, MC-03, MC-04, X-02).
- **One channel list**: every source, medium and campaign spelling mapped to one channel and campaign, shared with the budget (GA-01 to GA-03).
- **Remove what isn't real**: test data, total rows and duplicate purchases (SH-05, AD-01, GA-05).
- **Mark what can't be fully trusted**: machine opens, GA4 coverage, platform conversions, traffic from countries without deliveries (MC-06, GA-04, GA-06, X-01). These become the warning labels on the dashboard that *context.md* asks for (D6).

## Next step

Step 3: building the silver layer with dbt, issue by issue.
