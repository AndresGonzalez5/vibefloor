// ABOUTME: Simple dev server for the website.
// ABOUTME: Serves dist/ on localhost:3000 with live reload via bun --hot.

const server = Bun.serve({
  port: 3000,
  async fetch(req) {
    const url = new URL(req.url);
    let path = url.pathname === "/" ? "/index.html" : url.pathname;
    const file = Bun.file(`dist${path}`);
    if (await file.exists()) {
      return new Response(file);
    }
    return new Response("Not found", { status: 404 });
  },
});

console.log(`Serving website at http://localhost:${server.port}`);
