"""Flash-sale load test: many buyers, one product, every order expected to succeed.

The course race_test.py proves correctness (exactly one winner for the last unit,
50 of 400 attempts sold). This script measures the shape the brief warns about:
about 400 orders in ten seconds on a single product, all of which succeed, so
every buyer queues on the same product row.

Usage, with the Compose setup in the README:
    DATABASE_URL=postgresql://postgres:<password>@127.0.0.1:5433/kloudkart_lab \
        python scripts/flash_sale_benchmark.py [--buyers 400]

The script creates one fixture product (ID 999400) and removes it, with its
orders and stock movements, before and after the run. The database needs
max_connections above the number of buyers.
"""

from __future__ import annotations

import argparse
import os
import sys
import threading
import time

import psycopg2

FIXTURE_PRODUCT_ID = 999_400
FIXTURE_NAME = "FLASH SALE BENCHMARK FIXTURE"


def place_one_order(dsn: str, customer_id: int, barrier: threading.Barrier,
                    results: list, results_lock: threading.Lock) -> None:
    """Open a connection, wait for every buyer, then place one order."""
    try:
        conn = psycopg2.connect(dsn)
    except psycopg2.Error as exc:
        barrier.abort()
        with results_lock:
            results.append((None, repr(exc), 0.0))
        return

    conn.autocommit = True
    try:
        barrier.wait()
        started = time.perf_counter()
        with conn.cursor() as cur:
            cur.execute(
                "SELECT success, message FROM place_order(%s, %s, 1)",
                (customer_id, FIXTURE_PRODUCT_ID),
            )
            success, message = cur.fetchone()
        elapsed = time.perf_counter() - started
        with results_lock:
            results.append((success, message, elapsed))
    except (psycopg2.Error, threading.BrokenBarrierError) as exc:
        with results_lock:
            results.append((None, repr(exc), 0.0))
    finally:
        conn.close()


def remove_fixture(dsn: str) -> None:
    """Delete the fixture product and every order and movement made for it."""
    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute("SELECT DISTINCT order_id FROM order_items WHERE product_id = %s",
                    (FIXTURE_PRODUCT_ID,))
        order_ids = [row[0] for row in cur.fetchall()]
        cur.execute("DELETE FROM order_items WHERE product_id = %s",
                    (FIXTURE_PRODUCT_ID,))
        cur.execute("DELETE FROM orders WHERE order_id = ANY(%s)", (order_ids,))
        cur.execute("DELETE FROM inventory_log WHERE product_id = %s",
                    (FIXTURE_PRODUCT_ID,))
        cur.execute("DELETE FROM products WHERE product_id = %s",
                    (FIXTURE_PRODUCT_ID,))


def create_fixture(dsn: str, units: int) -> int:
    """Create the fixture product and return the customer who will buy it."""
    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO products (product_id, product_name, category_id, price,"
            " stock_quantity, created_at) VALUES (%s, %s, NULL, 100.00, %s, now())",
            (FIXTURE_PRODUCT_ID, FIXTURE_NAME, units),
        )
        cur.execute("SELECT MIN(customer_id) FROM customers")
        return cur.fetchone()[0]


def read_outcome(dsn: str) -> tuple[int, int, int]:
    """Return (final stock, inventory_log rows, orders) for the fixture."""
    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute("SELECT stock_quantity FROM products WHERE product_id = %s",
                    (FIXTURE_PRODUCT_ID,))
        final_stock = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM inventory_log WHERE product_id = %s",
                    (FIXTURE_PRODUCT_ID,))
        log_rows = cur.fetchone()[0]
        cur.execute("SELECT COUNT(DISTINCT order_id) FROM order_items"
                    " WHERE product_id = %s", (FIXTURE_PRODUCT_ID,))
        orders = cur.fetchone()[0]
    return final_stock, log_rows, orders


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--buyers", type=int, default=400,
                        help="concurrent buyers and units in stock (default 400)")
    args = parser.parse_args()

    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        sys.exit("Set DATABASE_URL, e.g. "
                 "postgresql://postgres:<password>@127.0.0.1:5433/kloudkart_lab")

    remove_fixture(dsn)
    try:
        customer_id = create_fixture(dsn, args.buyers)
        released_at: list[float] = []
        barrier = threading.Barrier(
            args.buyers, action=lambda: released_at.append(time.perf_counter())
        )
        results: list = []
        results_lock = threading.Lock()

        threads = [
            threading.Thread(target=place_one_order,
                             args=(dsn, customer_id, barrier, results, results_lock))
            for _ in range(args.buyers)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        finished_at = time.perf_counter()

        final_stock, log_rows, orders = read_outcome(dsn)
    finally:
        remove_fixture(dsn)

    sold = sum(1 for success, _, _ in results if success)
    refused = sum(1 for success, _, _ in results if success is False)
    errored = sum(1 for success, _, _ in results if success is None)
    latencies = sorted(elapsed for success, _, elapsed in results if success)

    print(f"buyers={args.buyers} units={args.buyers} sold={sold} "
          f"refused={refused} errored={errored}")
    print(f"final stock={final_stock} inventory_log rows={log_rows} orders={orders}")
    if released_at:
        print(f"wall clock from barrier release={finished_at - released_at[0]:.2f}s")
    if latencies:
        median = latencies[len(latencies) // 2]
        p95 = latencies[max(int(len(latencies) * 0.95) - 1, 0)]
        print(f"per-order latency: median={median:.3f}s p95={p95:.3f}s "
              f"max={latencies[-1]:.3f}s")

    passed = (sold == args.buyers and errored == 0 and final_stock == 0
              and log_rows == args.buyers and orders == args.buyers)
    print("PASSED" if passed else "FAILED")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
