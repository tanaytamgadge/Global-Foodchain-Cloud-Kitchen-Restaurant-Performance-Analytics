-- Daily Revenue Analysis
CREATE MATERIALIZED VIEW daily_revenue AS
WITH order_summary AS (
    SELECT 
        o.restaurant_id,
        DATE(o.order_time) as order_date,
        COUNT(DISTINCT o.id) as total_orders,
        SUM(o.total_amount) as total_revenue,
        COUNT(DISTINCT o.customer_id) as unique_customers
    FROM orders o
    WHERE o.status = 'delivered'
    GROUP BY o.restaurant_id, DATE(o.order_time)
)
SELECT 
    r.name as restaurant_name,
    os.order_date,
    os.total_orders,
    os.total_revenue,
    os.unique_customers,
    LAG(os.total_revenue) OVER (PARTITION BY r.id ORDER BY os.order_date) as prev_day_revenue,
    ((os.total_revenue - LAG(os.total_revenue) OVER (PARTITION BY r.id ORDER BY os.order_date)) / 
     NULLIF(LAG(os.total_revenue) OVER (PARTITION BY r.id ORDER BY os.order_date), 0)) * 100 as revenue_growth_percent
FROM order_summary os
JOIN restaurants r ON r.id = os.restaurant_id;

-- Kitchen Performance Metrics
CREATE MATERIALIZED VIEW kitchen_performance AS
SELECT 
    k.id as kitchen_id,
    r.name as restaurant_name,
    DATE(o.order_time) as operation_date,
    COUNT(DISTINCT o.id) as total_orders,
    AVG(EXTRACT(EPOCH FROM (oi.updated_at - oi.created_at))/60) as avg_preparation_time,
    COUNT(DISTINCT CASE WHEN oi.status = 'completed' THEN oi.id END)::FLOAT / 
        NULLIF(COUNT(DISTINCT oi.id), 0) * 100 as completion_rate,
    k.capacity as kitchen_capacity,
    COUNT(DISTINCT oi.id)::FLOAT / NULLIF(k.capacity, 0) as capacity_utilization
FROM kitchens k
JOIN restaurants r ON r.id = k.restaurant_id
JOIN orders o ON o.restaurant_id = r.id
JOIN order_items oi ON oi.order_id = o.id
GROUP BY k.id, r.name, DATE(o.order_time), k.capacity;

-- Menu Item Performance
CREATE MATERIALIZED VIEW menu_performance AS
SELECT 
    mi.id as menu_item_id,
    mi.name as item_name,
    r.name as restaurant_name,
    COUNT(DISTINCT oi.order_id) as times_ordered,
    SUM(oi.quantity) as total_quantity_sold,
    SUM(oi.quantity * oi.unit_price) as total_revenue,
    SUM(oi.quantity * mi.cost) as total_cost,
    (SUM(oi.quantity * oi.unit_price) - SUM(oi.quantity * mi.cost)) as total_profit,
    ((SUM(oi.quantity * oi.unit_price) - SUM(oi.quantity * mi.cost)) / 
     NULLIF(SUM(oi.quantity * oi.unit_price), 0) * 100) as profit_margin_percent
FROM menu_items mi
JOIN restaurants r ON r.id = mi.restaurant_id
LEFT JOIN order_items oi ON oi.menu_item_id = mi.id
GROUP BY mi.id, mi.name, r.name;

-- Customer Insights
CREATE MATERIALIZED VIEW customer_insights AS
WITH customer_metrics AS (
    SELECT 
        c.id as customer_id,
        c.name as customer_name,
        COUNT(DISTINCT o.id) as total_orders,
        SUM(o.total_amount) as total_spent,
        AVG(o.total_amount) as avg_order_value,
        MAX(o.order_time) as last_order_date,
        MIN(o.order_time) as first_order_date
    FROM customers c
    JOIN orders o ON o.customer_id = c.id
    WHERE o.status = 'delivered'
    GROUP BY c.id, c.name
)
SELECT 
    cm.*,
    EXTRACT(EPOCH FROM (NOW() - cm.last_order_date))/86400 as days_since_last_order,
    CASE 
        WHEN cm.total_spent > 1000 THEN 'VIP'
        WHEN cm.total_spent > 500 THEN 'Regular'
        ELSE 'New'
    END as customer_segment
FROM customer_metrics cm;

-- Delivery Performance
CREATE MATERIALIZED VIEW delivery_performance AS
SELECT 
    d.driver_id,
    r.name as restaurant_name,
    DATE(d.pickup_time) as delivery_date,
    COUNT(DISTINCT d.id) as total_deliveries,
    AVG(EXTRACT(EPOCH FROM (d.actual_delivery_time - d.pickup_time))/60) as avg_delivery_time,
    AVG(EXTRACT(EPOCH FROM (d.actual_delivery_time - d.estimated_delivery_time))/60) as avg_delivery_delay,
    COUNT(DISTINCT CASE WHEN d.actual_delivery_time <= d.estimated_delivery_time THEN d.id END)::FLOAT / 
        NULLIF(COUNT(DISTINCT d.id), 0) * 100 as on_time_delivery_rate
FROM deliveries d
JOIN orders o ON o.id = d.order_id
JOIN restaurants r ON r.id = o.restaurant_id
WHERE d.status = 'delivered'
GROUP BY d.driver_id, r.name, DATE(d.pickup_time) as pickup_date;

-- Inventory Analysis
CREATE MATERIALIZED VIEW inventory_analysis AS
SELECT 
    ii.id as inventory_item_id,
    ii.name as item_name,
    r.name as restaurant_name,
    ii.quantity as current_quantity,
    ii.reorder_level,
    ii.unit_cost,
    ii.quantity * ii.unit_cost as total_value,
    CASE 
        WHEN ii.quantity <= ii.reorder_level THEN 'Reorder Required'
        WHEN ii.quantity <= (ii.reorder_level * 1.2) THEN 'Low Stock'
        ELSE 'Adequate'
    END as stock_status,
    ii.last_restock_date,
    ii.expiry_date,
    EXTRACT(EPOCH FROM (ii.expiry_date::timestamp - NOW()))/86400 as days_until_expiry
FROM inventory_items ii
JOIN restaurants r ON r.id = ii.restaurant_id;

-- Staff Performance
CREATE MATERIALIZED VIEW staff_performance AS
WITH staff_orders AS (
    SELECT 
        s.id as staff_id,
        s.name as staff_name,
        s.role,
        r.name as restaurant_name,
        DATE(o.order_time) as work_date,
        COUNT(DISTINCT o.id) as orders_handled,
        AVG(EXTRACT(EPOCH FROM (oi.updated_at - oi.created_at))/60) as avg_order_processing_time
    FROM staff s
    JOIN restaurants r ON r.id = s.restaurant_id
    JOIN orders o ON o.restaurant_id = r.id
    JOIN order_items oi ON oi.order_id = o.id
    GROUP BY s.id, s.name, s.role, r.name, DATE(o.order_time)
)
SELECT 
    so.*,
    AVG(so.avg_order_processing_time) OVER (
        PARTITION BY so.staff_id 
        ORDER BY so.work_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as rolling_7day_avg_processing_time
FROM staff_orders so;

-- Customer Feedback Analysis
CREATE MATERIALIZED VIEW feedback_analysis AS
SELECT 
    r.name as restaurant_name,
    DATE(rv.review_date) as review_date,
    COUNT(DISTINCT rv.id) as total_reviews,
    AVG(rv.rating) as avg_rating,
    COUNT(DISTINCT CASE WHEN rv.rating >= 4 THEN rv.id END)::FLOAT / 
        NULLIF(COUNT(DISTINCT rv.id), 0) * 100 as satisfaction_rate,
    COUNT(DISTINCT CASE WHEN rv.rating <= 2 THEN rv.id END) as negative_reviews,
    AVG(CASE WHEN rv.response IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (rv.response_date - rv.review_date))/3600 
        END) as avg_response_time_hours
FROM reviews rv
JOIN orders o ON o.id = rv.order_id
JOIN restaurants r ON r.id = o.restaurant_id
GROUP BY r.name, DATE(rv.review_date);

-- Financial Performance
CREATE MATERIALIZED VIEW financial_performance AS
WITH revenue AS (
    SELECT 
        restaurant_id,
        DATE_TRUNC('month', order_time) as month,
        SUM(total_amount) as total_revenue
    FROM orders
    WHERE status = 'delivered'
    GROUP BY restaurant_id, DATE_TRUNC('month', order_time)
),
expenses AS (
    SELECT 
        restaurant_id,
        DATE_TRUNC('month', date) as month,
        SUM(amount) as total_expenses
    FROM expenses
    GROUP BY restaurant_id, DATE_TRUNC('month', date)
),
staff_costs AS (
    SELECT 
        restaurant_id,
        DATE_TRUNC('month', date) as month,
        SUM(amount) as staff_costs
    FROM expenses
    WHERE category = 'staff'
    GROUP BY restaurant_id, DATE_TRUNC('month', date)
)
SELECT 
    r.name as restaurant_name,
    rv.month,
    rv.total_revenue,
    COALESCE(e.total_expenses, 0) as total_expenses,
    COALESCE(sc.staff_costs, 0) as staff_costs,
    rv.total_revenue - COALESCE(e.total_expenses, 0) as net_profit,
    CASE 
        WHEN rv.total_revenue = 0 THEN 0
        ELSE ((rv.total_revenue - COALESCE(e.total_expenses, 0)) / rv.total_revenue * 100)
    END as profit_margin_percent
FROM revenue rv
JOIN restaurants r ON r.id = rv.restaurant_id
LEFT JOIN expenses e ON e.restaurant_id = rv.restaurant_id AND e.month = rv.month
LEFT JOIN staff_costs sc ON sc.restaurant_id = rv.restaurant_id AND sc.month = rv.month;

-- Peak Hours Analysis
CREATE MATERIALIZED VIEW peak_hours_analysis AS
SELECT 
    r.name as restaurant_name,
    DATE(o.order_time) as order_date,
    EXTRACT(HOUR FROM o.order_time) as hour_of_day,
    COUNT(DISTINCT o.id) as total_orders,
    SUM(o.total_amount) as total_revenue,
    COUNT(DISTINCT o.customer_id) as unique_customers,
    AVG(EXTRACT(EPOCH FROM (oi.updated_at - oi.created_at))/60) as avg_preparation_time
FROM orders o
JOIN restaurants r ON r.id = o.restaurant_id
JOIN order_items oi ON oi.order_id = o.id
GROUP BY r.name, DATE(o.order_time), EXTRACT(HOUR FROM o.order_time);

-- Refresh schedules for materialized views
CREATE OR REPLACE FUNCTION refresh_all_mat_views()
RETURNS void AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT matviewname FROM pg_matviews
    LOOP
        EXECUTE 'REFRESH MATERIALIZED VIEW ' || r.matviewname;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create a schedule to refresh views every hour
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('0 * * * *', 'SELECT refresh_all_mat_views()');