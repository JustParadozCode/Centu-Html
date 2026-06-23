const express = require('express');
const app = express();

const luaSource = `script_key = "KEY"; 
print("Script successfully executed!")`;

const generateHtml = (code) => { /* Keep the same HTML string from before */ };

app.get('/', (req, res) => {
    const userAgent = req.headers['user-agent'] || '';
    if (userAgent.toLowerCase().includes('roblox')) {
        res.setHeader('Content-Type', 'text/plain');
        return res.send(luaSource);
    } 
    res.setHeader('Content-Type', 'text/html');
    return res.send(generateHtml(luaSource));
});

// Export the app for Vercel's serverless handler
module.exports = app;

