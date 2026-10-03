#!/usr/bin/env node
// exfil/server.js — attacker-controlled collector for the exfiltration probe.
// Listens for POST /collect and appends the request body to /recv/captured.txt.
// This stands in for a C2 / attacker endpoint an agent could phone home to.
// SAFETY: only receives what the probe deliberately sends (a demo secret).
const http = require('http');
const fs = require('fs');
const port = Number(process.env.EXFIL_PORT || 18080);
const out = process.env.EXFIL_OUT || '/recv/captured.txt';
const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (d) => { body += d; });
  req.on('end', () => {
    try { fs.appendFileSync(out, body + '\n'); } catch (e) { /* ignore */ }
    res.writeHead(200); res.end('got it');
    process.stdout.write('COLLECTED ' + req.method + ' ' + req.url + ' body=' + body.length + 'B\n');
  });
});
server.listen(port, '0.0.0.0', () => console.log('attacker-collector listening :' + port));