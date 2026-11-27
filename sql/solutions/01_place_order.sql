-- ============================================================
-- Kloud Kart: Requirement 1
-- Concurrency-safe order placement
--
-- Input:    the course schema and data, loaded fresh.
-- Produces: ID sequences for orders, order_items and inventory_log;
--           a non-negative stock constraint for new writes;
--           public.place_order(bigint, bigint, integer).
-- Asserts:  race_test.py passes unmodified (see
--           docs/validation_evidence.md).
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. ID sequences.
--    The supplied tables have primary keys but no generators.
-- ------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS public.orders_order_id_seq
    AS integer;

CREATE SEQUENCE IF NOT EXISTS public.order_items_order_item_id_seq
    AS integer;

CREATE SEQUENCE IF NOT EXISTS public.inventory_log_log_id_seq
    AS integer;

ALTER TABLE public.orders
    ALTER COLUMN order_id
    SET DEFAULT nextval('public.orders_order_id_seq');

ALTER TABLE public.order_items
    ALTER COLUMN order_item_id
    SET DEFAULT nextval('public.order_items_order_item_id_seq');

ALTER TABLE public.inventory_log
    ALTER COLUMN log_id
    SET DEFAULT nextval('public.inventory_log_log_id_seq');

ALTER SEQUENCE public.orders_order_id_seq
    OWNED BY public.orders.order_id;

ALTER SEQUENCE public.order_items_order_item_id_seq
    OWNED BY public.order_items.order_item_id;

ALTER SEQUENCE public.inventory_log_log_id_seq
    OWNED BY public.inventory_log.log_id;

-- Start each sequence after the highest existing ID.
SELECT setval(
    'public.orders_order_id_seq',
    COALESCE(MAX(order_id), 1),
    COUNT(*) > 0
)
FROM public.orders;

SELECT setval(
    'public.order_items_order_item_id_seq',
    COALESCE(MAX(order_item_id), 1),
    COUNT(*) > 0
)
FROM public.order_items;

SELECT setval(
    'public.inventory_log_log_id_seq',
    COALESCE(MAX(log_id), 1),
    COUNT(*) > 0
)
FROM public.inventory_log;

-- ------------------------------------------------------------
-- 2. Backstop: stock can never be written below zero.
--    NOT VALID enforces the rule on every new insert or update
--    without rejecting the 14 historical negative balances,
--    which are evidence of past overselling and must be
--    reconciled, not overwritten (see the data diagnosis).
-- ------------------------------------------------------------

ALTER TABLE public.products
    DROP CONSTRAINT IF EXISTS products_stock_non_negative;

ALTER TABLE public.products
    ADD CONSTRAINT products_stock_non_negative
    CHECK (stock_quantity >= 0) NOT VALID;

-- ------------------------------------------------------------
-- 3. Order placement.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.place_order(
    p_customer_id bigint,
    p_product_id bigint,
    p_quantity integer
)
RETURNS TABLE (
    success boolean,
    order_id bigint,
    message text
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_price numeric(12,2);
    v_order_id bigint;
    v_stock_updated boolean;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, 'Invalid quantity';
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.customers c
        WHERE c.customer_id = p_customer_id
    ) THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, 'Customer not found';
        RETURN;
    END IF;

    SELECT p.price
    INTO v_price
    FROM public.products p
    WHERE p.product_id = p_product_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, 'Product not found';
        RETURN;
    END IF;

    IF v_price IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, 'Product price is missing';
        RETURN;
    END IF;

    -- --------------------------------------------------------
    -- Concurrency control.
    --
    -- The stock check and the deduction are one statement. The
    -- UPDATE takes the product's row lock; a competing buyer
    -- waits for it, then PostgreSQL re-evaluates the WHERE
    -- clause against the committed stock (READ COMMITTED
    -- re-check). The loser therefore matches no row and is told
    -- "out of stock" instead of receiving an error.
    --
    -- The transaction-local flag tells the audit trigger
    -- (solution 04) that this function writes its own
    -- inventory_log entry.
    -- --------------------------------------------------------

    PERFORM set_config('kloudkart.stock_change_logged', 'on', true);

    UPDATE public.products
    SET stock_quantity = stock_quantity - p_quantity
    WHERE product_id = p_product_id
      AND stock_quantity >= p_quantity
    RETURNING price INTO v_price;

    v_stock_updated := FOUND;

    PERFORM set_config('kloudkart.stock_change_logged', 'off', true);

    IF NOT v_stock_updated THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, 'Out of stock';
        RETURN;
    END IF;

    INSERT INTO public.orders (
        customer_id,
        order_date,
        status,
        total_amount
    )
    VALUES (
        p_customer_id::integer,
        CURRENT_TIMESTAMP,
        'pending',
        v_price * p_quantity
    )
    RETURNING orders.order_id INTO v_order_id;

    INSERT INTO public.order_items (
        order_id,
        product_id,
        quantity,
        unit_price
    )
    VALUES (
        v_order_id,
        p_product_id::integer,
        p_quantity,
        v_price
    );

    -- A negative change_qty records stock leaving inventory.
    INSERT INTO public.inventory_log (
        product_id,
        change_qty,
        reason,
        created_at,
        note
    )
    VALUES (
        p_product_id::integer,
        -p_quantity,
        'sale',
        CURRENT_TIMESTAMP,
        'Stock deducted for order ' || v_order_id
    );

    RETURN QUERY SELECT TRUE, v_order_id, 'Order placed successfully';
END;
$$;

COMMIT;
