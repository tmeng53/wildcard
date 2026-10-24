// Serves public/ the way Vercel does for this site (a folder's index.html at its path, then
// vercel.json's rewrites where no file matches), for local previews and the Playwright tests:
// `node scripts/serve.mjs [port]`.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { dirname, extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const web = join(dirname(fileURLToPath(import.meta.url)), '..');
const root = join(web, 'public');
// Each rewrite's source as a pattern: `:name` matches one path segment.
const rewrites = JSON.parse(await readFile(join(web, 'vercel.json'), 'utf8')).rewrites.map(
  ({ source, destination }) => ({
    pattern: new RegExp(`^${source.replace(/:\w+/g, '[^/]+')}/?$`),
    destination,
  }),
);
const port = Number(process.argv[2] ?? 4321);
const types = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.png': 'image/png',
  '.js': 'text/javascript; charset=utf-8',
  '.ttf': 'font/ttf',
  '.txt': 'text/plain; charset=utf-8',
};

createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, 'http://localhost').pathname));
  let file = join(root, path);
  if (!file.startsWith(root)) {
    res.writeHead(403).end();
    return;
  }
  try {
    const found = await stat(file).catch(() => undefined);
    const rewrite = rewrites.find(({ pattern }) => pattern.test(path));
    if (!found && rewrite) file = join(root, rewrite.destination);
    else if (found?.isDirectory()) file = join(file, 'index.html');
    const body = await readFile(file);
    res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
}).listen(port, () => process.stdout.write(`http://localhost:${port}\n`));
