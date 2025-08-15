#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting proxy server setup..."

# Step 1: Clean existing NodeJS installation
echo "🔧 Removing old Node.js and npm..."
sudo apt remove nodejs npm -y
sudo apt autoremove -y

# Step 2: Install latest LTS version of Node.js
echo "📦 Installing Node.js LTS..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

# Step 3: Create proxy project
echo "📁 Setting up proxy server folder..."
mkdir -p proxy-server
cd proxy-server

# Step 4: Initialize Node.js project and install dependencies
echo "🧩 Installing dependencies..."
npm init -y
npm install express http-proxy-middleware cors

# Step 5: Create proxy server file
echo "📝 Writing proxy server code..."
cat > index.js << 'EOF'
const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

// Get backend URL from environment variable or use default
const BACKEND_URL = 'http://localhost:8000';

// Enable CORS for all requests
app.use(cors());

// Log all incoming requests
app.use((req, res, next) => {
  console.log(`Received request: ${req.method} ${req.url}`);
  next();
});

// Proxy all requests to the backend
app.use('/', createProxyMiddleware({
  target: BACKEND_URL,
  changeOrigin: true,
  logLevel: 'debug',
  timeout: 120000,
  proxyTimeout: 120000,
  onProxyReq: (proxyReq, req, res) => {
    console.log(`Proxying ${req.method} ${req.url} to ${BACKEND_URL}${proxyReq.path}`);
  },
  onProxyRes: (proxyRes, req, res) => {
    console.log(`Received response for ${req.method} ${req.url}: ${proxyRes.statusCode}`);
  },
  onError: (err, req, res) => {
    console.error(`Proxy error: ${err.message}`);
    res.status(500).send(`Proxy Error: ${err.message}`);
  }
}));

app.listen(PORT, () => {
  console.log(`Proxy server running on http://localhost:${PORT}`);
  console.log(`Proxying requests to: ${BACKEND_URL}`);
});
EOF

# # Step 6: Run the proxy server
# echo "🚀 Starting proxy server..."
# node index.js
