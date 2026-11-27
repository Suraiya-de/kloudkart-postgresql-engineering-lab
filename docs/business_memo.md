# Memo

**To:** Nana Adjei, Operations
**From:** Database Engineering
**Date:** 27 November 2026
**Subject:** Overselling, the Monday report, and what your data is telling you

## What is fixed

**Overselling.** When two customers try to buy the last unit at the same moment, one gets it and the other is told "out of stock" straight away. We tested this 75 times, and in a simulated flash sale with 400 customers buying one product at once: every unit was sold exactly once and all 400 orders went through in under five seconds. Stock can no longer drop below zero, whatever tries to change it.

Neither answer you were given would have fixed things on its own. Triggers alone check stock in a way two buyers can still pass together. A bigger server would still take hours, because the report was slow in how it was written. Both fixes run on your current server at no extra cost.

**The Monday report.** It now covers every customer: total spent, number of orders, spend in each of the last 12 months, a running total and a ranking, in under two seconds on a laptop. The running total always ends on the customer's total spent, so Adwoa can see at a glance that the figures agree.

**Low stock.** One report shows low-stock counts for every category, rolled up through every level (Electronics, Phones, Phone Accessories, Cases), in a fraction of a second. Products with no category appear on their own line.

**The trail.** Every sale, restock, return, correction and write-off is recorded with its reason. A stock figure changed any other way is now recorded too, with the account that changed it.

**Extra: a Monday health check.** One list shows each known data problem and how many records it affects, so new problems are spotted the week they appear.

## What we found

1. **Stock figures that disagree with their own history.** 144 products, 2,553 units in total. Forty-nine are already low on stock, where a wrong count leads straight to overselling.
2. **"Complete" and "completed".** About 22,000 sales were recorded as "complete". Ignoring them would under-report customer spending by a fifth and get 24 of your top 100 customers wrong. We have counted them as sales.
3. **Order totals that disagree with their items.** 2,426 orders, partly from items entered twice and six orders keyed as 999 or 9,999 units instead of one.
4. **Stock below zero on 14 products.** For 13 of them the records show exactly how it happened: units sold that did not exist, the overselling you described.
5. **Smaller issues.** 210 orders with no customer on file, 15 orders dated in the future, and 533 customers registered more than once.

## What we recommend next

1. Count the 144 mismatched products and the 14 below zero, and record each correction through the new process.
2. Confirm that "complete" means "completed", then use one set of status names everywhere.
3. Agree with finance whether revenue is the order total or the sum of its items.
4. Before the first flash sale, have your developers set the website to serve many shoppers through a small, fixed number of links to the stock system, so a rush of buyers cannot overload it.

## What we cannot stand behind yet

- **Which figure is right** for the 144 products and 2,426 orders. Only a stock count and payment records can settle it.
- **"Complete" meaning "completed."** The evidence is strong, but it is our judgement. If wrong, the report overstates spend by 68 million.
- **Flash-sale day itself.** Tested on a laptop, not your live shop, and recommendation 4 must be in place first.
- **Adwoa's original report.** We did not have it, so the speed comparison is against a typical version, not hers.
