const express = require('express');
const cors = require('cors');
const pool = require('./db');

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

app.use('/api/auth', require('./routes/auth'));
app.use('/api/materials', require('./routes/materials'));
app.use('/api/inventory', require('./routes/inventory'));
app.use('/api/workers', require('./routes/workers'));
app.use('/api/products', require('./routes/products'));
app.use('/api/machines', require('./routes/machines'));
app.use('/api/mixers', require('./routes/mixers'));
app.use('/api/mixture-types', require('./routes/mixture_types'));
app.use('/api/batches', require('./routes/batches'));
app.use('/api/machine-production', require('./routes/machine_production'));
app.use('/api/alerts', require('./routes/alerts'));
app.use('/api/audit', require('./routes/audit'));
app.use('/api/dashboard', require('./routes/dashboard'));

app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', db: 'connected' });
  } catch (err) {
    res.status(500).json({ status: 'error', db: err.message });
  }
});

const PORT = process.env.API_PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Plastic Factory API running on port ${PORT}`);
});
