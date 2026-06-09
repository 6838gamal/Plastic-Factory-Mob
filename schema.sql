-- =============================================================
-- مصنع البلاستيك ERP - نظام إدارة الموارد
-- Plastic Factory ERP - Supabase Database Schema
-- =============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================
-- جدول المواد الخام - Raw Materials
-- =============================================================
CREATE TABLE IF NOT EXISTS raw_materials (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(200) NOT NULL,
  category VARCHAR(100) NOT NULL DEFAULT 'عام',
  unit VARCHAR(20) NOT NULL DEFAULT 'كجم',
  min_stock DECIMAL(12,3) NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_raw_materials_category ON raw_materials(category);
CREATE INDEX IF NOT EXISTS idx_raw_materials_active ON raw_materials(is_active);

-- =============================================================
-- جدول المخزون - Inventory
-- =============================================================
CREATE TABLE IF NOT EXISTS inventory (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  material_id UUID NOT NULL REFERENCES raw_materials(id),
  warehouse_type VARCHAR(50) NOT NULL DEFAULT 'main',  -- 'main' | 'mixer'
  balance DECIMAL(12,3) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(material_id, warehouse_type)
);

CREATE INDEX IF NOT EXISTS idx_inventory_material ON inventory(material_id);
CREATE INDEX IF NOT EXISTS idx_inventory_warehouse ON inventory(warehouse_type);

-- =============================================================
-- جدول حركات المخزون - Inventory Transactions
-- =============================================================
CREATE TABLE IF NOT EXISTS inventory_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  material_id UUID NOT NULL REFERENCES raw_materials(id),
  warehouse_type VARCHAR(50) NOT NULL,
  transaction_type VARCHAR(20) NOT NULL,  -- 'in' | 'out' | 'transfer' | 'adjustment'
  quantity DECIMAL(12,3) NOT NULL,
  batch_id UUID,
  production_id UUID,
  transaction_ref VARCHAR(100),
  created_by VARCHAR(200),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inv_tx_material ON inventory_transactions(material_id);
CREATE INDEX IF NOT EXISTS idx_inv_tx_created ON inventory_transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_inv_tx_ref ON inventory_transactions(transaction_ref);

-- =============================================================
-- جدول العمال - Workers
-- =============================================================
CREATE TABLE IF NOT EXISTS workers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(200) NOT NULL,
  phone VARCHAR(20),
  employee_id VARCHAR(50),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- جدول المنتجات - Products
-- =============================================================
CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(200) NOT NULL,
  code VARCHAR(50),
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- جدول الماكينات - Machines
-- =============================================================
CREATE TABLE IF NOT EXISTS machines (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(200) NOT NULL,
  code VARCHAR(50),
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- جدول الخلاطات - Mixers
-- =============================================================
CREATE TABLE IF NOT EXISTS mixers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(200) NOT NULL,
  capacity DECIMAL(10,2),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- جدول أنواع الخلطات - Mixture Types
-- =============================================================
CREATE TABLE IF NOT EXISTS mixture_types (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(200) NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- جدول الطبخات - Batches
-- =============================================================
CREATE TABLE IF NOT EXISTS batches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  batch_number VARCHAR(100) NOT NULL,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  shift VARCHAR(50),
  worker_id UUID REFERENCES workers(id),
  worker_name VARCHAR(200),
  mixer_id UUID REFERENCES mixers(id),
  mixer_name VARCHAR(200),
  product_id UUID REFERENCES products(id),
  product_name VARCHAR(200),
  mixture_type_id UUID REFERENCES mixture_types(id),
  mixture_type_name VARCHAR(200),
  
  -- Main raw material quantities (kg)
  pvc_qty DECIMAL(10,3) DEFAULT 0,
  dop_qty DECIMAL(10,3) DEFAULT 0,
  scrap_qty DECIMAL(10,3) DEFAULT 0,
  calcium_qty DECIMAL(10,3) DEFAULT 0,
  wax_qty DECIMAL(10,3) DEFAULT 0,
  stabilizer_qty DECIMAL(10,3) DEFAULT 0,
  titanium_qty DECIMAL(10,3) DEFAULT 0,
  
  -- Dynamic pigments and additives stored as JSON
  pigments JSONB DEFAULT '[]',
  additives JSONB DEFAULT '[]',
  materials JSONB DEFAULT '[]',
  
  -- Metadata
  notes TEXT,
  scale_image_url TEXT,
  transaction_id VARCHAR(100) UNIQUE,
  status VARCHAR(20) DEFAULT 'saved',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_batches_date ON batches(date);
CREATE INDEX IF NOT EXISTS idx_batches_worker ON batches(worker_id);
CREATE INDEX IF NOT EXISTS idx_batches_number ON batches(batch_number);
CREATE INDEX IF NOT EXISTS idx_batches_tx ON batches(transaction_id);

-- =============================================================
-- جدول إنتاج الماكينات - Machine Production
-- =============================================================
CREATE TABLE IF NOT EXISTS machine_production (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  batch_number VARCHAR(100),
  machine_id UUID REFERENCES machines(id),
  machine_name VARCHAR(200),
  product_id UUID REFERENCES products(id),
  product_name VARCHAR(200),
  worker_id UUID,
  worker_name VARCHAR(200),
  
  -- Production quantities (kg)
  produced_quantity DECIMAL(10,3) DEFAULT 0,
  scrap_quantity DECIMAL(10,3) DEFAULT 0,
  waste_quantity DECIMAL(10,3) DEFAULT 0,
  stop_time_minutes DECIMAL(8,2) DEFAULT 0,
  
  -- Metadata
  notes TEXT,
  production_image_url TEXT,
  transaction_id VARCHAR(100) UNIQUE,
  status VARCHAR(20) DEFAULT 'saved',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_machine_prod_machine ON machine_production(machine_id);
CREATE INDEX IF NOT EXISTS idx_machine_prod_created ON machine_production(created_at);
CREATE INDEX IF NOT EXISTS idx_machine_prod_tx ON machine_production(transaction_id);

-- =============================================================
-- جدول التحذيرات - Alerts
-- =============================================================
CREATE TABLE IF NOT EXISTS alerts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  alert_type VARCHAR(50) NOT NULL,  -- 'low_stock' | 'insufficient_stock' | 'high_waste' | 'machine_stop'
  severity VARCHAR(20) NOT NULL DEFAULT 'medium',  -- 'low' | 'medium' | 'high' | 'critical'
  material_id UUID REFERENCES raw_materials(id),
  material_name VARCHAR(200),
  batch_id UUID REFERENCES batches(id),
  batch_number VARCHAR(100),
  machine_id UUID REFERENCES machines(id),
  machine_name VARCHAR(200),
  description TEXT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',  -- 'pending' | 'acknowledged' | 'resolved'
  transaction_id VARCHAR(100),
  resolved_at TIMESTAMPTZ,
  resolved_by VARCHAR(200),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alerts_status ON alerts(status);
CREATE INDEX IF NOT EXISTS idx_alerts_severity ON alerts(severity);
CREATE INDEX IF NOT EXISTS idx_alerts_type ON alerts(alert_type);
CREATE INDEX IF NOT EXISTS idx_alerts_created ON alerts(created_at);

-- =============================================================
-- جدول سجل التدقيق - Audit Log
-- =============================================================
CREATE TABLE IF NOT EXISTS audit_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  action VARCHAR(20) NOT NULL,  -- 'create' | 'update' | 'delete' | 'deduct' | 'transfer' | 'failed'
  table_name VARCHAR(100) NOT NULL,
  record_id UUID,
  old_values JSONB,
  new_values JSONB,
  user_id VARCHAR(200),
  user_email VARCHAR(200),
  transaction_id VARCHAR(100),
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_table ON audit_log(table_name);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_tx ON audit_log(transaction_id);

-- =============================================================
-- جدول الوصفات - Recipes (optional)
-- =============================================================
CREATE TABLE IF NOT EXISTS recipes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(200) NOT NULL,
  product_id UUID REFERENCES products(id),
  mixture_type_id UUID REFERENCES mixture_types(id),
  is_active BOOLEAN NOT NULL DEFAULT true,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS recipe_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  material_id UUID NOT NULL REFERENCES raw_materials(id),
  quantity DECIMAL(10,3) NOT NULL,
  unit VARCHAR(20) DEFAULT 'كجم',
  notes TEXT
);

-- =============================================================
-- Storage Buckets (run in Supabase dashboard Storage section)
-- =============================================================
-- Create bucket: batch-images (public)
-- Create bucket: production-images (public)

-- =============================================================
-- Row Level Security (RLS) Policies
-- Enable RLS on all tables for production security
-- =============================================================
ALTER TABLE raw_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE workers ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE machines ENABLE ROW LEVEL SECURITY;
ALTER TABLE mixers ENABLE ROW LEVEL SECURITY;
ALTER TABLE mixture_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE machine_production ENABLE ROW LEVEL SECURITY;
ALTER TABLE alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipe_items ENABLE ROW LEVEL SECURITY;

-- Allow all authenticated users to read all tables
CREATE POLICY "Allow read for authenticated" ON raw_materials FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow read for authenticated" ON inventory FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow read for authenticated" ON inventory_transactions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow read for authenticated" ON workers FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow read for authenticated" ON products FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow read for authenticated" ON machines FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow read for authenticated" ON mixers FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow read for authenticated" ON mixture_types FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow read for authenticated" ON batches FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow read for authenticated" ON machine_production FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow read for authenticated" ON alerts FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow read for authenticated" ON audit_log FOR SELECT TO authenticated USING (true);

-- Allow all authenticated users to insert/update
CREATE POLICY "Allow write for authenticated" ON raw_materials FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow write for authenticated" ON inventory FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow write for authenticated" ON inventory_transactions FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow write for authenticated" ON workers FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow write for authenticated" ON products FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow write for authenticated" ON machines FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow write for authenticated" ON mixers FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow write for authenticated" ON mixture_types FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow write for authenticated" ON batches FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow write for authenticated" ON machine_production FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow write for authenticated" ON alerts FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow write for authenticated" ON audit_log FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Allow ANON to insert batches and machine_production (workers are not logged in)
CREATE POLICY "Allow anon insert batches" ON batches FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "Allow anon read batches" ON batches FOR SELECT TO anon USING (true);
CREATE POLICY "Allow anon insert production" ON machine_production FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "Allow anon read production" ON machine_production FOR SELECT TO anon USING (true);
CREATE POLICY "Allow anon read materials" ON raw_materials FOR SELECT TO anon USING (true);
CREATE POLICY "Allow anon read workers" ON workers FOR SELECT TO anon USING (true);
CREATE POLICY "Allow anon read machines" ON machines FOR SELECT TO anon USING (true);
CREATE POLICY "Allow anon read mixers" ON mixers FOR SELECT TO anon USING (true);
CREATE POLICY "Allow anon read products" ON products FOR SELECT TO anon USING (true);
CREATE POLICY "Allow anon read mixture_types" ON mixture_types FOR SELECT TO anon USING (true);
CREATE POLICY "Allow anon insert inventory_tx" ON inventory_transactions FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "Allow anon update inventory" ON inventory FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "Allow anon insert alerts" ON alerts FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "Allow anon read alerts" ON alerts FOR SELECT TO anon USING (true);
CREATE POLICY "Allow anon insert audit" ON audit_log FOR INSERT TO anon WITH CHECK (true);

-- =============================================================
-- Helper functions
-- =============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_raw_materials_updated_at BEFORE UPDATE ON raw_materials FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER update_inventory_updated_at BEFORE UPDATE ON inventory FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER update_workers_updated_at BEFORE UPDATE ON workers FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER update_batches_updated_at BEFORE UPDATE ON batches FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER update_machine_production_updated_at BEFORE UPDATE ON machine_production FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER update_alerts_updated_at BEFORE UPDATE ON alerts FOR EACH ROW EXECUTE FUNCTION update_updated_at();
