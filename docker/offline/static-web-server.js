#!/usr/bin/env node
const fs = require("fs")
const http = require("http")
const path = require("path")

const root = path.resolve(process.argv[2] || "/app/web-app/dist")
const host = process.env.VITE_HOST || process.env.WEBAPP_HOST || "0.0.0.0"
const port = Number(process.env.VITE_PORT || process.env.WEBAPP_PORT || "5173")

const contentTypes = {
    ".css": "text/css; charset=utf-8",
    ".html": "text/html; charset=utf-8",
    ".ico": "image/x-icon",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".map": "application/json; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".txt": "text/plain; charset=utf-8",
    ".woff": "font/woff",
    ".woff2": "font/woff2"
}

function resolveFile(urlPath) {
    let decoded
    try {
        decoded = decodeURIComponent(urlPath.split("?")[0])
    } catch {
        return null
    }

    const candidate = path.resolve(root, `.${decoded}`)
    if (!candidate.startsWith(`${root}${path.sep}`) && candidate !== root) {
        return null
    }

    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
        return candidate
    }
    return path.join(root, "index.html")
}

http.createServer((req, res) => {
    const file = resolveFile(req.url || "/")
    if (!file || !fs.existsSync(file)) {
        res.writeHead(404)
        res.end("not found")
        return
    }

    res.writeHead(200, {
        "content-type": contentTypes[path.extname(file)] || "application/octet-stream",
        "cache-control": file.endsWith("index.html") ? "no-cache" : "public, max-age=31536000, immutable"
    })
    fs.createReadStream(file).pipe(res)
}).listen(port, host, () => {
    console.log(`webapp static server listening on http://${host}:${port}`)
})
