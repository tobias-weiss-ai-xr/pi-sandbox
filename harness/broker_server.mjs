#!/usr/bin/env node
// broker_server.mjs — secrets broker for the pi-sandbox (node build of the
// python probe). Serves ONE credential to any caller bearing the scope token.
//
// This is the sbx proxy pattern from results/07: the real key stays on the host
// (or a host-scoped broker container) and the agent sandbox pulls it at call
// time over one internal port. The sandbox therefore holds NO real key in its
// env, layers, mounts, or `docker inspect` output.
//
// SAFETY properties:
//   * serves a single BROKER_KEY ended by BROKER_TOKEN via X-Scope-Token
//   * logs request LINES ONLY (path + status + source address) — never bodies,
//     so the credential value never reaches logs
//   * answered refusal semantics
//     - 403 wrong / missing token
//     - 410 token already redeemed when BROKER_SINGLE_USE=1
//   * binds BROKER_BIND (default 0.0.0.0) — run in a broker container on the
//     shared bridge so only sibling containers can reach it.
//
// Usage:
//   BROKER_TOKEN=... BROKER_KEY=... node broker_server.mjs
//   BROKER_SINGLE_USE=1 node broker_server.mjs   # one-shot credential
export const demo = 'broker_server.mjs: secrets broker'; // (noop) marker

import { createServer } from 'node:http';
import { hostname } from 'node:os';

const TOKEN = process.env.BROKER_TOKEN || 'dev-token';
const KEY = process.env.BROKER_KEY || 'demo-real-key-1a2b3c';
const BIND = process.env.BROKER_BIND || '0.0.0.0';
const PORT = Number(process.env.BROKER_PORT || 18080);
const SINGLE_USE = (process.env.BROKER_SINGLE_USE || '0') === '1';
let redeemed = false;

const server = createServer((req, res) => {
  const source = req.socket.remoteAddress || '-';
  if (req.method !== 'GET' || req.url !== '/key') {
    res.writeHead(404); res.end('not found');
    console.log(`${new Date().toISOString()} ${source} 404 ${req.method} ${req.url}`);
    return;
  }
  if (req.headers['x-scope-token'] !== TOKEN) {
    res.writeHead(403); res.end('forbidden: bad scope token');
    console.log(`${new Date().toISOString()} ${source} 403 token-denied`);
    return;
  }
  if (SINGLE_USE && redeemed) {
    res.writeHead(410); res.end('gone: credential already redeemed');
    console.log(`${new Date().toISOString()} ${source} 410 token-redeemed`);
    return;
  }
  if (SINGLE_USE) redeemed = true;
  const body = KEY;
  res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': body.length });
  res.end(body);
  // log the grant line only, never the key value
  console.log(`${new Date().toISOString()} ${source} 200 ${SINGLE_USE ? 'single-use-grant ' : 'grant '}${req.method} ${req.url}`);
});

server.listen(PORT, BIND, () => {
  console.log(`broker listening on ${BIND}:${PORT} host=${hostname()}` +
    (SINGLE_USE ? ' [single-use]' : ''));
});