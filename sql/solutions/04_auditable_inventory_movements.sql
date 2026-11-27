-- ============================================================
-- Kloud Kart: Requirement 4
-- Auditable inventory movements
--
-- Input:    solution 01 (inventory_log ID sequence).
-- Produces: public.record_inventory_movement(...) for restocks,
--           returns, corrections, damage and stock-takes;
--           a safety-net trigger that logs any stock change made
--           outside the inventory functions.
-- Asserts:  every update to an existing product's stock_quantity
--           leaves an inventory_log row; a failed movement leaves
--           neither a stock change nor a log row (see
--           docs/validation_evidence.md). Opening stock on a new
--           product and deleted products are not logged.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Controlled movements other than sales.
--    Sales are recorded by place_order() (solution 01).
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_inventory_movement(
    p_product_id bigint,
    p_change_qty integer,
    p_reason text,
    p_note text
)
RETURNS TABLE (
    success boolean,
    product_id bigint,
    previous_stock integer,
    new_stock integer,
    log_id bigint,
    message text
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_previous_stock integer;
    v_new_stock bigint;
    v_reason text;
    v_log_id bigint;
    v_error text;
BEGIN
    v_reason := LOWER(BTRIM(p_reason));

    v_error := CASE
        WHEN p_product_id IS NULL
            THEN 'Product ID is required'
        WHEN p_change_qty IS NULL OR v_reason IS NULL
            THEN 'Quantity and reason are required'
        WHEN v_reason NOT IN (
            'restock', 'return', 'correction', 'damage', 'stock_take'
        )
            THEN 'Invalid movement reason'
        WHEN p_note IS NULL OR BTRIM(p_note) = ''
            THEN 'An explanatory note is required'
        WHEN v_reason IN ('restock', 'return') AND p_change_qty <= 0
            THEN 'Restocks and returns must increase stock'
        WHEN v_reason = 'damage' AND p_change_qty >= 0
            THEN 'Damage must decrease stock'
        WHEN v_reason = 'correction' AND p_change_qty = 0
            THEN 'Correction quantity cannot be zero'
        WHEN v_reason = 'stock_take' AND p_change_qty <> 0
            THEN 'Stock-take entries must have zero quantity'
    END;

    IF v_error IS NOT NULL THEN
        RETURN QUERY SELECT FALSE, p_product_id, NULL::integer,
            NULL::integer, NULL::bigint, v_error;
        RETURN;
    END IF;

    -- Lock the product row so concurrent movements and sales
    -- for the same product are applied one at a time.
    SELECT p.stock_quantity
    INTO v_previous_stock
    FROM public.products p
    WHERE p.product_id = p_product_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, p_product_id, NULL::integer,
            NULL::integer, NULL::bigint, 'Product not found';
        RETURN;
    END IF;

    IF v_previous_stock IS NULL THEN
        RETURN QUERY SELECT FALSE, p_product_id, NULL::integer,
            NULL::integer, NULL::bigint, 'Product stock quantity is NULL';
        RETURN;
    END IF;

    v_new_stock := v_previous_stock::bigint + p_change_qty;

    IF v_new_stock < 0 OR v_new_stock > 2147483647 THEN
        RETURN QUERY SELECT FALSE, p_product_id, v_previous_stock,
            NULL::integer, NULL::bigint,
            'Movement would produce an invalid stock quantity';
        RETURN;
    END IF;

    -- This function writes its own log entry; tell the audit
    -- trigger not to add a second one.
    PERFORM set_config('kloudkart.stock_change_logged', 'on', true);

    UPDATE public.products
    SET stock_quantity = v_new_stock::integer
    WHERE products.product_id = p_product_id;

    PERFORM set_config('kloudkart.stock_change_logged', 'off', true);

    INSERT INTO public.inventory_log (
        product_id,
        change_qty,
        reason,
        created_at,
        note
    )
    VALUES (
        p_product_id::integer,
        p_change_qty,
        v_reason,
        CURRENT_TIMESTAMP,
        BTRIM(p_note)
    )
    RETURNING inventory_log.log_id INTO v_log_id;

    RETURN QUERY SELECT
        TRUE,
        p_product_id,
        v_previous_stock,
        v_new_stock::integer,
        v_log_id,
        'Inventory movement recorded';
END;
$$;

-- ------------------------------------------------------------
-- 2. Safety net for stock changes made any other way.
--    A direct UPDATE of stock_quantity (a script, an admin tool,
--    a future application path) is still allowed, but it is
--    written to inventory_log with reason 'unlogged_update', the
--    database user and the before/after values. This closes the
--    gap that let 144 products drift from their movement ledger.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.log_unrecorded_stock_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF COALESCE(
        current_setting('kloudkart.stock_change_logged', true),
        'off'
    ) <> 'on' THEN
        INSERT INTO public.inventory_log (
            product_id,
            change_qty,
            reason,
            created_at,
            note
        )
        VALUES (
            NEW.product_id,
            COALESCE(NEW.stock_quantity, 0) - COALESCE(OLD.stock_quantity, 0),
            'unlogged_update',
            CURRENT_TIMESTAMP,
            format(
                'Direct stock update by %s outside the inventory functions: %s -> %s',
                current_user,
                OLD.stock_quantity,
                NEW.stock_quantity
            )
        );
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_stock_audit ON public.products;

CREATE TRIGGER trg_products_stock_audit
AFTER UPDATE OF stock_quantity ON public.products
FOR EACH ROW
WHEN (OLD.stock_quantity IS DISTINCT FROM NEW.stock_quantity)
EXECUTE FUNCTION public.log_unrecorded_stock_change();

COMMIT;
