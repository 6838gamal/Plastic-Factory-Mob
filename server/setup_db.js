const pool = require('./db');
const fs = require('fs');
const path = require('path');

async function setup() {
  const client = await pool.connect();
  try {
    await client.query('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"');
    await client.query('CREATE EXTENSION IF NOT EXISTS pgcrypto');

    await client.query(`
      CREATE TABLE IF NOT EXISTS admin_users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        email VARCHAR(200) UNIQUE NOT NULL,
        password_hash VARCHAR(200) NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS raw_materials (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(200) NOT NULL,
        category VARCHAR(100) NOT NULL DEFAULT 'عام',
        unit VARCHAR(20) NOT NULL DEFAULT 'كجم',
        min_stock DECIMAL(12,3) NOT NULL DEFAULT 0,
        is_active BOOLEAN NOT NULL DEFAULT true,
        notes TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS inventory (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        material_id UUID NOT NULL REFERENCES raw_materials(id),
        warehouse_type VARCHAR(50) NOT NULL DEFAULT 'main',
        balance DECIMAL(12,3) NOT NULL DEFAULT 0,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE(material_id, warehouse_type)
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS inventory_transactions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        material_id UUID NOT NULL REFERENCES raw_materials(id),
        warehouse_type VARCHAR(50) NOT NULL,
        transaction_type VARCHAR(20) NOT NULL,
        quantity DECIMAL(12,3) NOT NULL,
        batch_id UUID,
        production_id UUID,
        transaction_ref VARCHAR(100),
        created_by VARCHAR(200),
        notes TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS workers (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(200) NOT NULL,
        phone VARCHAR(20),
        employee_id VARCHAR(50),
        is_active BOOLEAN NOT NULL DEFAULT true,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS products (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(200) NOT NULL,
        code VARCHAR(50),
        description TEXT,
        is_active BOOLEAN NOT NULL DEFAULT true,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS machines (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(200) NOT NULL,
        code VARCHAR(50),
        description TEXT,
        is_active BOOLEAN NOT NULL DEFAULT true,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS mixers (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(200) NOT NULL,
        capacity DECIMAL(10,2),
        is_active BOOLEAN NOT NULL DEFAULT true,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS mixture_types (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(200) NOT NULL,
        description TEXT,
        is_active BOOLEAN NOT NULL DEFAULT true,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS batches (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS machine_production (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS alerts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS audit_log (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS recipes (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(200) NOT NULL,
        product_id UUID REFERENCES products(id),
        mixture_type_id UUID REFERENCES mixture_types(id),
        is_active BOOLEAN NOT NULL DEFAULT true,
        notes TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS recipe_items (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        material_id UUID NOT NULL REFERENCES raw_materials(id),
        quantity DECIMAL(10,3) NOT NULL,
        unit VARCHAR(20) DEFAULT 'كجم',
        notes TEXT
      )
    `);

    console.log('✅ All tables created successfully');

    const existingAdmin = await client.query('SELECT id FROM admin_users LIMIT 1');
    if (existingAdmin.rows.length === 0) {
      const bcrypt = require('bcryptjs');
      const hash = await bcrypt.hash('admin123', 10);
      await client.query(
        `INSERT INTO admin_users (email, password_hash) VALUES ('admin@factory.com', $1)`,
        [hash]
      );
      console.log('✅ Default admin created: admin@factory.com / admin123');
    }

  } catch (err) {
    console.error('❌ Setup error:', err.message);
    throw err;
  } finally {
    client.release();
    await pool.end();
  }
}

setup().then(() => {
  console.log('✅ Database setup complete');
  process.exit(0);
}).catch(err => {
  console.error('Setup failed:', err);
  process.exit(1);
});
