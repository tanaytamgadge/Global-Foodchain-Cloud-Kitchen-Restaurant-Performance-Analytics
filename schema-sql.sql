-- Cloud Kitchen & Restaurant Performance Analytics Schema
-- Created: 2025-01-14

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- Restaurants table
CREATE TABLE restaurants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    location GEOGRAPHY(POINT) NOT NULL,
    type VARCHAR(50) NOT NULL CHECK (type IN ('cloud_kitchen', 'restaurant', 'hybrid')),
    opening_date DATE NOT NULL,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'maintenance')),
    cuisine_type VARCHAR(50) NOT NULL,
    operating_hours JSONB NOT NULL,
    contact_info JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Kitchens table
CREATE TABLE kitchens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(id),
    capacity INTEGER NOT NULL CHECK (capacity > 0),
    equipment JSONB NOT NULL,
    area_sqft NUMERIC(8,2) NOT NULL,
    last_inspection_date DATE,
    safety_rating INTEGER CHECK (safety_rating BETWEEN 1 AND 5),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Menu table
CREATE TABLE menu_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(id),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    category VARCHAR(50) NOT NULL,
    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    cost NUMERIC(10,2) NOT NULL CHECK (cost >= 0),
    preparation_time INTEGER NOT NULL, -- in minutes
    allergens TEXT[],
    availability BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Customers table
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    address JSONB,
    preferences JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Orders table
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customers(id),
    restaurant_id UUID NOT NULL REFERENCES restaurants(id),
    order_time TIMESTAMP WITH TIME ZONE NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'confirmed', 'preparing', 'ready', 'in_delivery', 'delivered', 'cancelled')),
    total_amount NUMERIC(10,2) NOT NULL,
    payment_status VARCHAR(20) NOT NULL CHECK (payment_status IN ('pending', 'completed', 'failed', 'refunded')),
    payment_method VARCHAR(50),
    special_instructions TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Order Items table
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id),
    menu_item_id UUID NOT NULL REFERENCES menu_items(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL,
    special_instructions TEXT,
    status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'preparing', 'completed', 'cancelled')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Inventory table
CREATE TABLE inventory_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(id),
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    quantity NUMERIC(10,2) NOT NULL,
    unit VARCHAR(20) NOT NULL,
    reorder_level NUMERIC(10,2) NOT NULL,
    unit_cost NUMERIC(10,2) NOT NULL,
    supplier_info JSONB,
    last_restock_date TIMESTAMP WITH TIME ZONE,
    expiry_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Staff table
CREATE TABLE staff (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(id),
    name VARCHAR(100) NOT NULL,
    role VARCHAR(50) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    schedule JSONB,
    hourly_rate NUMERIC(10,2),
    hire_date DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Reviews table
CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id),
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comments TEXT,
    review_date TIMESTAMP WITH TIME ZONE NOT NULL,
    response TEXT,
    response_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Expenses table
CREATE TABLE expenses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(id),
    category VARCHAR(50) NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    description TEXT,
    date DATE NOT NULL,
    payment_method VARCHAR(50),
    receipt_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Delivery table
CREATE TABLE deliveries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id),
    driver_id UUID,
    status VARCHAR(20) NOT NULL CHECK (status IN ('assigned', 'picked_up', 'in_progress', 'delivered', 'failed')),
    pickup_time TIMESTAMP WITH TIME ZONE,
    delivery_time TIMESTAMP WITH TIME ZONE,
    estimated_delivery_time TIMESTAMP WITH TIME ZONE,
    actual_delivery_time TIMESTAMP WITH TIME ZONE,
    delivery_address JSONB NOT NULL,
    delivery_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better query performance
CREATE INDEX idx_restaurants_location ON restaurants USING GIST (location);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_restaurant_id ON orders(restaurant_id);
CREATE INDEX idx_orders_order_time ON orders(order_time);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_inventory_restaurant_id ON inventory_items(restaurant_id);
CREATE INDEX idx_staff_restaurant_id ON staff(restaurant_id);
CREATE INDEX idx_reviews_order_id ON reviews(order_id);
CREATE INDEX idx_expenses_restaurant_id ON expenses(restaurant_id);
CREATE INDEX idx_deliveries_order_id ON deliveries(order_id);

-- Create trigger function for updating timestamps
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for all tables
CREATE TRIGGER update_restaurants_timestamp BEFORE UPDATE ON restaurants FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER update_kitchens_timestamp BEFORE UPDATE ON kitchens FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER update_menu_items_timestamp BEFORE UPDATE ON menu_items FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER update_customers_timestamp BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER update_orders_timestamp BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER update_order_items_timestamp BEFORE UPDATE ON order_items FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER update_inventory_items_timestamp BEFORE UPDATE ON inventory_items FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER update_staff_timestamp BEFORE UPDATE ON staff FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER update_reviews_timestamp BEFORE UPDATE ON reviews FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER update_expenses_timestamp BEFORE UPDATE ON expenses FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER update_deliveries_timestamp BEFORE UPDATE ON deliveries FOR EACH ROW EXECUTE FUNCTION update_timestamp();
