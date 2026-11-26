# 0004: One person key across shop accounts, guest orders and subscribers

**Status:** accepted

## Context

Many questions in *context.md* are about **people**: new versus returning customers, CAC, lifetime value, retention, and how many subscribers are customers. The sources only know **records**:

- The shop has accounts, and some people have two (SH-06): with an email that only differs in case, or with another email but the same name, birth date and postal code.
- 7.077 of the 24.000 guest orders come from people who also have an account (SH-07).
- Marketing Cloud has more subscriber records than people (MC-03), and its subscriber key is a customer number, an email address or a sign-up key (MC-04).

Counting records instead of people overstates the number of new customers and understates retention.

## Options considered

1. **The shop account as the customer.** Simple, but every duplicate account is a "new customer", guest orders have no customer at all, and subscribers only link through the subscriber key, which works for less than half of them.
2. **The normalised email address as the person.** It covers guests and subscribers, but misses the people who created a second account with another email address.
3. **Connected components over email and identity.** Accounts are linked when they share a normalised email address *or* the same first name, last name, real birth date and postal code. Every group of linked accounts is one person. Guest orders and subscriber records join that person through their email address; without a matching account, the email address itself is the person.
4. **Fuzzy matching** (similar names, edit distance on email addresses). It finds more, but it also merges different people, and every merge is hard to explain or undo.

## Decision

Option 3, built in `silver.person_identities` and `silver.persons`. The person key is an MD5 hash of the anchor (the lowest customer id in the group, or the email address), so it contains no personal data.

## Consequences

- Every account, order, subscriber record and logged-in GA4 session carries a `person_key`, so gold can count people with one `count(DISTINCT person_key)`.
- Placeholder birth dates are not used for matching (SH-10), so the 1.010 customers born "on 01/01/1900" are not merged.
- A person keeps the same key as long as their lowest customer id stays the same, which is true when the data is rebuilt from the same sources. Adding a new account to an existing person doesn't change the key; linking two existing groups through a new account changes the key of one of them. For a reporting model that is rebuilt from scratch, that's acceptable.
- Email typos (MC-05) are not corrected, so `jan@gmial.com` and `jan@gmail.com` stay two people unless the shop links them through name and birth date.
- The rule is deliberately conservative: it would rather miss a duplicate than merge two different people.
