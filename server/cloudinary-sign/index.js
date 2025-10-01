require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const crypto = require('crypto');

const app = express();
app.use(bodyParser.json());

// Ensure these are set in your server environment or in a .env file
// CLOUDINARY_API_KEY=your_api_key
// CLOUDINARY_API_SECRET=your_api_secret

const API_KEY = process.env.CLOUDINARY_API_KEY;
const API_SECRET = process.env.CLOUDINARY_API_SECRET;

if (!API_KEY || !API_SECRET) {
  console.error('CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET must be set');
  process.exit(1);
}

// Signs parameters for direct upload. The client sends an object of unsigned params
// (for example: {timestamp: 123456789, folder: 'flow_sounds'}) and the server returns
// {signature: '...', api_key: API_KEY, timestamp: 123456789}
app.post('/sign', (req, res) => {
  const params = req.body || {};
  // Only accept expected keys to avoid misuse
  const allowedKeys = ['timestamp', 'folder', 'public_id', 'eager'];
  const pairs = [];
  Object.keys(params).sort().forEach((k) => {
    if (allowedKeys.includes(k) && params[k] !== undefined && params[k] !== null && params[k] !== '') {
      pairs.push(`${k}=${params[k]}`);
    }
  });
  const toSign = pairs.join('&');
  const signature = crypto.createHash('sha1').update(toSign + API_SECRET).digest('hex');
  res.json({ signature, api_key: API_KEY, timestamp: params.timestamp });
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Cloudinary signing server listening on port ${port}`));
