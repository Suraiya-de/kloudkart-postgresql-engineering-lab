# Course files

Supplied with the lab and kept exactly as shipped. Do not edit them: `race_test.py` must run unmodified, and the SHA-256 hashes below let anyone confirm that.

| File | Purpose | SHA-256 |
|---|---|---|
| `schema.sql` | Kloud Kart's schema as it exists today. Drops and recreates the six tables. | `f23c11f464121cf1baa2f36732b03e9b15832f19f69f85a4cb6623a509ac16d9` |
| `load.sql` | Loads the six CSV files from `data/` with client-side `\copy`. | `c0432f353e71611169ea0cac62a523f7cd2727867cd567c6de3081c8ce5f2e6a` |
| `race_test.py` | The concurrency test `place_order()` must pass. | `5f12a6697400dee3876dfa33a03fbdcc1dc906f665f3c0a6aaeffe73cdb27d00` |

Check them with `sha256sum course/*.sql course/*.py` (macOS: `shasum -a 256`; PowerShell: `Get-FileHash course\*`).

## Data

The six CSV files (`categories.csv`, `products.csv`, `customers.csv`, `orders.csv`, `order_items.csv`, `inventory_log.csv`) contain customer names, emails and phone numbers, so they are not in the repository. Copy them from the course bundle into `course/data/`, which `.gitignore` excludes. `load.sql` reads them from there.
