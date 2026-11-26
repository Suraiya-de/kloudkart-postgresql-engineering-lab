
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
BEGIN
    v_reason := LOWER(TRIM(p_reason));

    IF p_product_id IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, NULL::integer,
            NULL::integer, NULL::bigint, 'Product ID is required';
        RETURN;
    END IF;

    IF p_change_qty IS NULL OR v_reason IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, NULL::integer,
            NULL::integer, NULL::bigint,
            'Quantity and reason are required';
        RETURN;
    END IF;

    IF v_reason NOT IN (
        'restock', 'return', 'correction', 'damage', 'stock_take'
    ) THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, NULL::integer,
            NULL::integer, NULL::bigint, 'Invalid movement reason';
        RETURN;
    END IF;

    IF p_note IS NULL OR TRIM(p_note) = '' THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, NULL::integer,
            NULL::integer, NULL::bigint,
            'An explanatory note is required';
        RETURN;
    END IF;

    IF v_reason IN ('restock', 'return') AND p_change_qty <= 0 THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, NULL::integer,
            NULL::integer, NULL::bigint,
            'Restocks and returns must increase stock';
        RETURN;
    END IF;

    IF v_reason = 'damage' AND p_change_qty >= 0 THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, NULL::integer,
            NULL::integer, NULL::bigint,
            'Damage must decrease stock';
        RETURN;
    END IF;

    IF v_reason = 'correction' AND p_change_qty = 0 THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, NULL::integer,
            NULL::integer, NULL::bigint,
            'Correction quantity cannot be zero';
        RETURN;
    END IF;

    IF v_reason = 'stock_take' AND p_change_qty <> 0 THEN
        RETURN QUERY SELECT FALSE, NULL::bigint, NULL::integer,
            NULL::integer, NULL::bigint,
            'Stock-take entries must have zero quantity';
        RETURN;
    END IF;

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
            NULL::integer, NULL::bigint,
            'Product stock quantity is NULL';
        RETURN;
    END IF;

    v_new_stock := v_previous_stock::bigint + p_change_qty;

    IF v_new_stock < 0 OR v_new_stock > 2147483647 THEN
        RETURN QUERY SELECT FALSE, p_product_id, v_previous_stock,
            NULL::integer, NULL::bigint,
            'Movement would produce an invalid stock quantity';
        RETURN;
    END IF;

    UPDATE public.products
    SET stock_quantity = v_new_stock::integer
    WHERE products.product_id = p_product_id;

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
        TRIM(p_note)
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
