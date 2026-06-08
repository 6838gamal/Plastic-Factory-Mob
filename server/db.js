const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.PG_DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

module.exports = pool;
