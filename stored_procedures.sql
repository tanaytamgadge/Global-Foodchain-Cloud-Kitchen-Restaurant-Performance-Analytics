-- Create order procedure
CREATE OR REPLACE PROCEDURE create_order(
    p_customer_id UUID,
    p_restaurant_id UUID,
    p_items JSONB,
    p_special_instructions TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id UUID;
    v_total_amount NUMERIC(10,2) := 0;
    v_item JSONB;
    v_menu_item_id UUID;
    v_unit_price NUMERIC(10,2);
BEGIN
    -- Calculate total amount and validate items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT id, price INTO v_menu_item_id, v_unit_price
        FROM menu_items
        WHERE id = (v_item->>'menu_item_id')::UUID
        AND restaurant_id = p_restaurant_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invalid menu item ID: %', v_item->>'menu_item_id';
        END IF;

        v_total_amount := v_total_amount + (v_unit_price * (v_item->>'quantity')::INTEGER);
    END LOOP;

    -- Create order
    INSERT INTO orders (
        customer_id,
        restaurant_id,
        order_time,
        status,
        total_amount,
        payment_status,
        special_instructions
    ) VALUES (
        p_customer_id,
        p_restaurant_id,
        CURRENT_TIMESTAMP,
        'pending',
        v_total_amount,
        'pending',
        p_special_instructions
    ) RETURNING id INTO v_order_id;

    -- Create order items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        INSERT INTO order_items (
            order_id,
            menu_item_id,
            quantity,
            unit_price,
            special_instructions,
            status
        ) VALUES (
            v_order_id,
            (v_item->>'menu_item_id')::UUID,
            (v_item->>'quantity')::INTEGER,
            (SELECT price FROM menu_items WHERE id = (v_item->>'menu_item_id')::UUID),
            v_item->>'special_instructions',
            'pending'
        );
    END LOOP;

    -- Update inventory
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        UPDATE inventory_items
        SET quantity = quantity - (v_item->>'quantity')::INTEGER
        WHERE restaurant_id = p_restaurant_id
        AND id IN (
            SELECT inventory_item_id 
            FROM menu_item_ingredients 
            WHERE menu_item_id = (v_item->>'menu_item_id')::UUID
        );
    END LOOP;
END;
$$;

-- Update order status procedure
CREATE OR REPLACE PROCEDURE update_order_status(
    p_order_id UUID,
    p_status VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Validate status transition
    IF NOT EXISTS (
        SELECT 1 FROM orders 
        WHERE id = p_order_id 
        AND status IN (
            CASE p_status
                WHEN 'confirmed' THEN 'pending'
                WHEN 'preparing' THEN 'confirmed'
                WHEN 'ready' THEN 'preparing'
                WHEN 'in_delivery' THEN 'ready'
                WHEN 'delivered' THEN 'in_delivery'
                WHEN 'cancelled' THEN 'pending,confirmed,preparing'
            END
        )
    ) THEN
        RAISE EXCEPTION 'Invalid status transition for order %', p_order_id;
    END IF;

    -- Update order status
    UPDATE orders 
    SET status = p_status,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_order_id;

    -- Handle cancellation
    IF p_status = 'cancelled' THEN
        -- Restore inventory
        UPDATE inventory_items ii
        SET quantity = quantity + oi.quantity
        FROM order_items oi
        JOIN menu_item_ingredients mii ON mii.menu_item_id = oi.menu_item_id
        WHERE oi.order_id = p_order_id
        AND ii.id = mii.inventory_item_id;

        -- Update order items status
        UPDATE order_items
        SET status = 'cancelled'
        WHERE order_id = p_order_id;
    END IF;
END;
$$;

-- Calculate revenue procedure
CREATE OR REPLACE PROCEDURE calculate_daily_revenue(
    p_restaurant_id UUID,
    p_date DATE,
    OUT total_revenue NUMERIC(10,2),
    OUT order_count INTEGER,
    OUT avg_order_value NUMERIC(10,2)
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT 
        COALESCE(SUM(total_amount), 0),
        COUNT(*),
        COALESCE(AVG(total_amount), 0)
    INTO total_revenue, order_count, avg_order_value
    FROM orders
    WHERE restaurant_id = p_restaurant_id
    AND DATE(order_time) = p_date
    AND status = 'delivered';
END;
$$;

-- Process inventory reorder
CREATE OR REPLACE PROCEDURE process_inventory_reorder(
    p_restaurant_id UUID
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_item RECORD;
    v_order_quantity NUMERIC(10,2);
BEGIN
    FOR v_item IN 
        SELECT * FROM inventory_items 
        WHERE restaurant_id = p_restaurant_id
        AND quantity <= reorder_level
    LOOP
        -- Calculate order quantity
        v_order_quantity := (v_item.reorder_level * 2) - v_item.quantity;
        
        -- Insert into purchase orders
        INSERT INTO purchase_orders (
            restaurant_id,
            inventory_item_id,
            quantity,
            status,
            expected_delivery_date
        ) VALUES (
            p_restaurant_id,
            v_item.id,
            v_order_quantity,
            'pending',
            CURRENT_DATE + INTERVAL '2 days'
        );
        
        -- Log reorder
        INSERT INTO inventory_logs (
            restaurant_id,
            inventory_item_id,
            action,
            quantity,
            notes
        ) VALUES (
            p_restaurant_id,
            v_item.id,
            'reorder',
            v_order_quantity,
            'Automatic reorder triggered'
        );
    END LOOP;
END;
$$;

-- Calculate staff efficiency
CREATE OR REPLACE PROCEDURE calculate_staff_efficiency(
    p_staff_id UUID,
    p_date DATE,
    OUT orders_processed INTEGER,
    OUT avg_processing_time NUMERIC(10,2),
    OUT efficiency_score NUMERIC(5,2)
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Calculate metrics
    SELECT 
        COUNT(DISTINCT oi.order_id),
        AVG(EXTRACT(EPOCH FROM (oi.updated_at - oi.created_at))/60),
        CASE 
            WHEN AVG(EXTRACT(EPOCH FROM (oi.updated_at - oi.created_at))/60) <= 15 THEN 5
            WHEN AVG(EXTRACT(EPOCH FROM (oi.updated_at - oi.created_at))/60) <= 20 THEN 4
            WHEN AVG(EXTRACT(EPOCH FROM (oi.updated_at - oi.created_at))/60) <= 25 THEN 3
            WHEN AVG(EXTRACT(EPOCH FROM (oi.updated_at - oi.created_at))/60) <= 30 THEN 2
            ELSE 1
        END
    INTO orders_processed, avg_processing_time, efficiency_score
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    JOIN restaurants r ON r.id = o.restaurant_id
    JOIN staff s ON s.restaurant_id = r.id
    WHERE s.id = p_staff_id
    AND DATE(oi.created_at) = p_date;
END;
$$;

-- Generate performance report
CREATE OR REPLACE PROCEDURE generate_performance_report(
    p_restaurant_id UUID,
    p_start_date DATE,
    p_end_date DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_report JSONB;
BEGIN
    -- Gather metrics
    WITH revenue_metrics AS (
        SELECT 
            SUM(total_amount) as total_revenue,
            COUNT(DISTINCT id) as total_orders,
            COUNT(DISTINCT customer_id) as unique_customers,
            AVG(total_amount) as total_revenue,
            COUNT(DISTINCT id) as total_orders,
            COUNT(DISTINCT customer_id) as unique_customers,
            AVG(total_amount) as avg_order_value
        FROM orders
        WHERE restaurant_id = p_restaurant_id
        AND DATE(order_time) BETWEEN p_start_date AND p_end_date
    ),
    customer_metrics AS (
        SELECT 
            AVG(rating) as avg_rating,
            COUNT(DISTINCT CASE WHEN rating >= 4 THEN reviews.id END)::FLOAT / 
                NULLIF(COUNT(DISTINCT reviews.id), 0) * 100 as satisfaction_rate
        FROM reviews
        JOIN orders ON orders.id = reviews.order_id
        WHERE orders.restaurant_id = p_restaurant_id
        AND DATE(reviews.review_date) BETWEEN p_start_date AND p_end_date
    ),
    operational_metrics AS (
        SELECT 
            AVG(EXTRACT(EPOCH FROM (oi.updated_at - oi.created_at))/60) as avg_preparation_time,
            COUNT(DISTINCT CASE WHEN d.status = 'delivered' AND 
                d.actual_delivery_time <= d.estimated_delivery_time 
                THEN d.id END)::FLOAT / 
                NULLIF(COUNT(DISTINCT d.id), 0) * 100 as on_time_delivery_rate
        FROM order_items oi
        JOIN orders o ON o.id = oi.order_id
        LEFT JOIN deliveries d ON d.order_id = o.id
        WHERE o.restaurant_id = p_restaurant_id
        AND DATE(o.order_time) BETWEEN p_start_date AND p_end_date
    ),
    inventory_metrics AS (
        SELECT 
            COUNT(DISTINCT CASE WHEN quantity <= reorder_level THEN id END) as low_stock_items,
            AVG(quantity / NULLIF(reorder_level, 0)) * 100 as avg_stock_level
        FROM inventory_items
        WHERE restaurant_id = p_restaurant_id
    ),
    expense_metrics AS (
        SELECT 
            SUM(amount) as total_expenses,
            SUM(CASE WHEN category = 'staff' THEN amount ELSE 0 END) as staff_expenses,
            SUM(CASE WHEN category = 'inventory' THEN amount ELSE 0 END) as inventory_expenses
        FROM expenses
        WHERE restaurant_id = p_restaurant_id
        AND date BETWEEN p_start_date AND p_end_date
    )
    SELECT jsonb_build_object(
        'period', jsonb_build_object(
            'start_date', p_start_date,
            'end_date', p_end_date
        ),
        'revenue', jsonb_build_object(
            'total_revenue', rm.total_revenue,
            'total_orders', rm.total_orders,
            'unique_customers', rm.unique_customers,
            'avg_order_value', rm.avg_order_value
        ),
        'customer_satisfaction', jsonb_build_object(
            'avg_rating', cm.avg_rating,
            'satisfaction_rate', cm.satisfaction_rate
        ),
        'operations', jsonb_build_object(
            'avg_preparation_time', om.avg_preparation_time,
            'on_time_delivery_rate', om.on_time_delivery_rate
        ),
        'inventory', jsonb_build_object(
            'low_stock_items', im.low_stock_items,
            'avg_stock_level', im.avg_stock_level
        ),
        'expenses', jsonb_build_object(
            'total_expenses', em.total_expenses,
            'staff_expenses', em.staff_expenses,
            'inventory_expenses', em.inventory_expenses,
            'profit_margin', ((rm.total_revenue - em.total_expenses) / 
                NULLIF(rm.total_revenue, 0) * 100)
        )
    ) INTO v_report
    FROM revenue_metrics rm
    CROSS JOIN customer_metrics cm
    CROSS JOIN operational_metrics om
    CROSS JOIN inventory_metrics im
    CROSS JOIN expense_metrics em;

    -- Insert report into performance_reports table
    INSERT INTO performance_reports (
        restaurant_id,
        start_date,
        end_date,
        report_data
    ) VALUES (
        p_restaurant_id,
        p_start_date,
        p_end_date,
        v_report
    );
END;
$$;

-- Auto-assign delivery driver
CREATE OR REPLACE PROCEDURE assign_delivery_driver(
    p_order_id UUID
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_driver_id UUID;
    v_restaurant_location GEOGRAPHY;
    v_delivery_address GEOGRAPHY;
BEGIN
    -- Get locations
    SELECT 
        r.location, 
        (o.delivery_address->>'location')::GEOGRAPHY
    INTO v_restaurant_location, v_delivery_address
    FROM orders o
    JOIN restaurants r ON r.id = o.restaurant_id
    WHERE o.id = p_order_id;

    -- Find nearest available driver
    SELECT driver_id INTO v_driver_id
    FROM driver_locations dl
    WHERE dl.status = 'available'
    ORDER BY dl.location <-> v_restaurant_location
    LIMIT 1;

    IF v_driver_id IS NULL THEN
        RAISE EXCEPTION 'No available drivers found';
    END IF;

    -- Create delivery record
    INSERT INTO deliveries (
        order_id,
        driver_id,
        status,
        pickup_time,
        estimated_delivery_time,
        delivery_address
    ) VALUES (
        p_order_id,
        v_driver_id,
        'assigned',
        NOW(),
        NOW() + INTERVAL '30 minutes',
        jsonb_build_object(
            'location', v_delivery_address::TEXT,
            'instructions', (SELECT delivery_instructions FROM orders WHERE id = p_order_id)
        )
    );

    -- Update driver status
    UPDATE driver_locations
    SET status = 'assigned'
    WHERE driver_id = v_driver_id;

    -- Update order status
    UPDATE orders
    SET status = 'in_delivery'
    WHERE id = p_order_id;
END;
$$;

-- Process end-of-day tasks
CREATE OR REPLACE PROCEDURE process_end_of_day(
    p_restaurant_id UUID,
    p_date DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_revenue NUMERIC(10,2);
    v_order_count INTEGER;
    v_avg_order_value NUMERIC(10,2);
BEGIN
    -- Calculate daily revenue
    CALL calculate_daily_revenue(
        p_restaurant_id,
        p_date,
        v_revenue,
        v_order_count,
        v_avg_order_value
    );

    -- Process inventory reorder
    CALL process_inventory_reorder(p_restaurant_id);

    -- Generate performance report
    CALL generate_performance_report(
        p_restaurant_id,
        p_date,
        p_date
    );

    -- Archive completed orders
    INSERT INTO order_archive
    SELECT *
    FROM orders
    WHERE restaurant_id = p_restaurant_id
    AND DATE(order_time) = p_date
    AND status IN ('delivered', 'cancelled');

    -- Clean up old data
    DELETE FROM orders
    WHERE restaurant_id = p_restaurant_id
    AND DATE(order_time) = p_date
    AND status IN ('delivered', 'cancelled');

    -- Log daily summary
    INSERT INTO daily_summaries (
        restaurant_id,
        date,
        total_revenue,
        order_count,
        avg_order_value
    ) VALUES (
        p_restaurant_id,
        p_date,
        v_revenue,
        v_order_count,
        v_avg_order_value
    );
END;
$$;

-- Schedule daily tasks
CREATE OR REPLACE PROCEDURE schedule_daily_tasks()
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT id FROM restaurants WHERE status = 'active'
    LOOP
        CALL process_end_of_day(r.id, CURRENT_DATE - INTERVAL '1 day');
    END LOOP;
END;
$$;

-- Schedule this to run daily at 3 AM
SELECT cron.schedule('0 3 * * *', 'CALL schedule_daily_tasks()');