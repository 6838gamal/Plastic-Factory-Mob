-- =============================================================
-- مصنع البلاستيك ERP - نظام إدارة الموارد
-- Plastic Factory ERP - Database Schema
-- =============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================
-- جدول المواد الخام - Raw Materials
-- =============================================================
CREATE TABLE IF NOT EXISTS raw_materials (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(200) NOT NULL,
  code VARCHAR(50),
  category VARCHAR(100) NOT NULL DEFAULT 'عام',
  unit VARCHAR(20) NOT NULL DEFAULT 'كجم',
  min_stock DECIMAL(12,3) NOT NULL DEFAULT 0,
  cost_per_unit DECIMAL(12,3) NOT NULL DEFAULT 0,
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
  warehouse_type VARCHAR(50) NOT NULL DEFAULT 'main',
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
  transaction_type VARCHAR(20) NOT NULL,
  quantity DECIMAL(12,3) NOT NULL,
  batch_id UUID,
  production_id UUID,
  transaction_ref VARCHAR(100),
  created_by VARCHAR(200),
  notes TEXT,
  balance_before DECIMAL(12,3),
  balance_after DECIMAL(12,3),
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
  pvc_qty DECIMAL(10,3) DEFAULT 0,
  dop_qty DECIMAL(10,3) DEFAULT 0,
  scrap_qty DECIMAL(10,3) DEFAULT 0,
  calcium_qty DECIMAL(10,3) DEFAULT 0,
  wax_qty DECIMAL(10,3) DEFAULT 0,
  stabilizer_qty DECIMAL(10,3) DEFAULT 0,
  titanium_qty DECIMAL(10,3) DEFAULT 0,
  pigments JSONB DEFAULT '[]',
  additives JSONB DEFAULT '[]',
  materials JSONB DEFAULT '[]',
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
  produced_quantity DECIMAL(10,3) DEFAULT 0,
  scrap_quantity DECIMAL(10,3) DEFAULT 0,
  waste_quantity DECIMAL(10,3) DEFAULT 0,
  stop_time_minutes DECIMAL(8,2) DEFAULT 0,
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
  alert_type VARCHAR(50) NOT NULL,
  severity VARCHAR(20) NOT NULL DEFAULT 'medium',
  material_id UUID REFERENCES raw_materials(id),
  material_name VARCHAR(200),
  batch_id UUID REFERENCES batches(id),
  batch_number VARCHAR(100),
  machine_id UUID REFERENCES machines(id),
  machine_name VARCHAR(200),
  description TEXT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
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
  action VARCHAR(20) NOT NULL,
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
-- جدول الوصفات - Recipes
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
-- جدول المستخدمين الإداريين - Admin Users
-- =============================================================
CREATE TABLE IF NOT EXISTS admin_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(200) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- جدول الإعدادات - Settings
-- =============================================================
CREATE TABLE IF NOT EXISTS settings (
  key VARCHAR(100) PRIMARY KEY,
  value TEXT NOT NULL DEFAULT '',
  description TEXT
);

-- =============================================================
-- جدول التقارير اليومية - Daily Reports
-- =============================================================
CREATE TABLE IF NOT EXISTS daily_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_date DATE UNIQUE NOT NULL,
  data JSONB DEFAULT '{}',
  is_locked BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- جدول الأرشيف اليومي - Daily Archive
-- =============================================================
CREATE TABLE IF NOT EXISTS daily_archive (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  archive_date DATE UNIQUE NOT NULL,
  report_data JSONB DEFAULT '{}',
  inventory_snapshot JSONB DEFAULT '[]',
  batch_count INTEGER DEFAULT 0,
  archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

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

CREATE OR REPLACE TRIGGER update_raw_materials_updated_at BEFORE UPDATE ON raw_materials FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE OR REPLACE TRIGGER update_inventory_updated_at BEFORE UPDATE ON inventory FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE OR REPLACE TRIGGER update_workers_updated_at BEFORE UPDATE ON workers FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE OR REPLACE TRIGGER update_batches_updated_at BEFORE UPDATE ON batches FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE OR REPLACE TRIGGER update_machine_production_updated_at BEFORE UPDATE ON machine_production FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE OR REPLACE TRIGGER update_alerts_updated_at BEFORE UPDATE ON alerts FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================================
-- جدول الورديات - Shifts
-- =============================================================
CREATE TABLE IF NOT EXISTS shifts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(100) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- جدول الأرصدة الافتتاحية - Opening Balances
-- =============================================================
CREATE TABLE IF NOT EXISTS opening_balances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  material_id UUID NOT NULL REFERENCES raw_materials(id),
  warehouse_type VARCHAR(50) NOT NULL DEFAULT 'main',
  balance DECIMAL(12,3) NOT NULL DEFAULT 0,
  balance_date DATE NOT NULL DEFAULT CURRENT_DATE,
  reason TEXT,
  created_by VARCHAR(200),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(material_id, warehouse_type, balance_date)
);

-- =============================================================
-- جدول جلسات الجرد - Stock Take Sessions
-- =============================================================
CREATE TABLE IF NOT EXISTS stock_take_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_name VARCHAR(200) NOT NULL,
  warehouse_type VARCHAR(50) NOT NULL DEFAULT 'main',
  notes TEXT,
  created_by VARCHAR(200),
  status VARCHAR(20) NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS stock_take_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES stock_take_sessions(id) ON DELETE CASCADE,
  material_id UUID NOT NULL REFERENCES raw_materials(id),
  material_name VARCHAR(200),
  warehouse_type VARCHAR(50),
  unit VARCHAR(20),
  system_qty DECIMAL(12,3),
  actual_qty DECIMAL(12,3),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- جدول سجل الخصومات - Deduction Log
-- =============================================================
CREATE TABLE IF NOT EXISTS deduction_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id VARCHAR(100) UNIQUE NOT NULL,
  batch_id UUID REFERENCES batches(id),
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reversed_at TIMESTAMPTZ,
  reversed_reason TEXT
);

-- =============================================================
-- جدول عناصر الطبخات - Batch Items
-- =============================================================
CREATE TABLE IF NOT EXISTS batch_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id UUID NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
  material_id UUID REFERENCES raw_materials(id),
  material_name VARCHAR(200),
  quantity DECIMAL(12,3) NOT NULL DEFAULT 0,
  unit VARCHAR(20) DEFAULT 'كجم',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================
-- التقارير اليومية المفصلة - Daily Reports (extended)
-- =============================================================
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS total_batches INTEGER DEFAULT 0;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS total_produced DECIMAL(12,3) DEFAULT 0;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS total_inputs DECIMAL(12,3) DEFAULT 0;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS total_waste DECIMAL(12,3) DEFAULT 0;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS total_scrap DECIMAL(12,3) DEFAULT 0;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS total_alerts INTEGER DEFAULT 0;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS day_cost DECIMAL(12,3) DEFAULT 0;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS most_consumed_material TEXT;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS least_consumed_material TEXT;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS efficiency_pct DECIMAL(8,2) DEFAULT 0;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS deviation_pct DECIMAL(8,2) DEFAULT 0;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS waste_pct DECIMAL(8,2) DEFAULT 0;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS snapshot JSONB DEFAULT '{}';
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ;

-- =============================================================
-- جدول تسليم الورديات - Shift Handovers
-- =============================================================
CREATE TABLE IF NOT EXISTS shift_handovers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_name VARCHAR(100) NOT NULL,
  supervisor_name VARCHAR(200) NOT NULL,
  handover_date DATE NOT NULL DEFAULT CURRENT_DATE,
  opening_stock_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
  received_from_main_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
  total_batch_inputs_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
  expected_stock_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
  actual_stock_kg DECIMAL(12,3),
  flashing_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
  rejected_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
  waste_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
  scrap_added_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
  deficit_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
  status VARCHAR(20) NOT NULL DEFAULT 'open',
  notes TEXT,
  next_supervisor_name VARCHAR(200),
  confirmed_at TIMESTAMPTZ,
  frozen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shift_handovers_date ON shift_handovers(handover_date);
CREATE INDEX IF NOT EXISTS idx_shift_handovers_status ON shift_handovers(status);

-- =============================================================
-- جدول مديونيات العهد - Custody Debts
-- =============================================================
CREATE TABLE IF NOT EXISTS custody_debts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  handover_id UUID NOT NULL REFERENCES shift_handovers(id),
  supervisor_name VARCHAR(200) NOT NULL,
  shift_name VARCHAR(100),
  deficit_kg DECIMAL(12,3) NOT NULL,
  handover_date DATE NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  notes TEXT,
  resolved_at TIMESTAMPTZ,
  resolved_by VARCHAR(200),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_custody_debts_status ON custody_debts(status);
CREATE INDEX IF NOT EXISTS idx_custody_debts_supervisor ON custody_debts(supervisor_name);

-- =============================================================
-- عرض ملخص المخزون - Inventory Summary View
-- (DROP + CREATE to handle column changes idempotently)
-- =============================================================
DROP VIEW IF EXISTS inventory_summary CASCADE;
CREATE VIEW inventory_summary AS
  SELECT
    i.id,
    i.material_id,
    rm.name   AS material_name,
    rm.category,
    rm.unit,
    rm.min_stock,
    COALESCE(rm.code, '')          AS code,
    i.warehouse_type,
    i.balance                      AS current_balance,
    i.balance,
    i.updated_at,
    COALESCE(rm.cost_per_unit, 0)  AS cost_per_unit,

    -- ── الرصيد الافتتاحي: آخر سجل لهذه المادة والمخزن ──────────
    COALESCE((
      SELECT ob.balance
      FROM   opening_balances ob
      WHERE  ob.material_id::text = i.material_id::text
        AND  ob.warehouse_type    = i.warehouse_type
      ORDER  BY ob.balance_date DESC, ob.created_at DESC
      LIMIT  1
    ), 0) AS opening_balance,

    -- ── إجمالي الوارد (in) ──────────────────────────────────────
    COALESCE((
      SELECT SUM(it.quantity)
      FROM   inventory_transactions it
      WHERE  it.material_id::text = i.material_id::text
        AND  it.warehouse_type    = i.warehouse_type
        AND  it.transaction_type  = 'in'
    ), 0) AS total_in,

    -- ── إجمالي الصادر (out) ─────────────────────────────────────
    COALESCE((
      SELECT SUM(it.quantity)
      FROM   inventory_transactions it
      WHERE  it.material_id::text = i.material_id::text
        AND  it.warehouse_type    = i.warehouse_type
        AND  it.transaction_type  = 'out'
    ), 0) AS total_out,

    -- ── صافي التحويلات ──────────────────────────────────────────
    COALESCE((
      SELECT SUM(
        CASE WHEN it.transaction_type = 'transfer_in'  THEN  it.quantity
             WHEN it.transaction_type = 'transfer_out' THEN -it.quantity
             ELSE 0 END
      )
      FROM   inventory_transactions it
      WHERE  it.material_id::text = i.material_id::text
        AND  it.warehouse_type    = i.warehouse_type
        AND  it.transaction_type IN ('transfer_in','transfer_out')
    ), 0) AS total_transfers,

    -- ── تسويات موجبة (رصيد ارتفع) ───────────────────────────────
    COALESCE((
      SELECT SUM(it.quantity)
      FROM   inventory_transactions it
      WHERE  it.material_id::text = i.material_id::text
        AND  it.warehouse_type    = i.warehouse_type
        AND  it.transaction_type  = 'adjustment'
        AND  COALESCE(it.balance_after, 0) >= COALESCE(it.balance_before, 0)
    ), 0) AS total_adjustments_pos,

    -- ── تسويات سالبة (رصيد انخفض) ───────────────────────────────
    COALESCE((
      SELECT SUM(it.quantity)
      FROM   inventory_transactions it
      WHERE  it.material_id::text = i.material_id::text
        AND  it.warehouse_type    = i.warehouse_type
        AND  it.transaction_type  = 'adjustment'
        AND  COALESCE(it.balance_after, 0) < COALESCE(it.balance_before, 0)
    ), 0) AS total_adjustments_neg,

    CASE WHEN i.balance <= 0                                   THEN 'out_of_stock'
         WHEN rm.min_stock > 0 AND i.balance <= rm.min_stock   THEN 'low'
         ELSE 'normal'
    END AS stock_status

  FROM inventory i
  JOIN raw_materials rm ON rm.id = i.material_id;
