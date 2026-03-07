export default {
  async fetch(request) {
    // 1. Parse URL parameters from the request
    const { searchParams } = new URL(request.url);
    const rssUrl = searchParams.get('rss');
    const count = parseInt(searchParams.get('count')) || 1;

    // 2. Default landing page if no RSS param is provided
    if (!rssUrl) {
      return new Response(landingPageHTML, { 
        headers: { 'content-type': 'text/html;charset=UTF-8' } 
      });
    }

    try {
      // 3. Fetch the external RSS feed
      // Note: Workers bypass CORS, so no proxy is needed!
      const response = await fetch(rssUrl, {
        headers: { 'User-Agent': 'Cloudflare-Worker-RSS-Reader' }
      });
      const xmlText = await response.text();

      // 4. Basic RSS Parsing (Simple Regex for Title, Link, Description)
      // Since Workers don't have 'DOMParser', we extract items manually
      const items = xmlText.split('<item>').slice(1, count + 1);
      
      let itemsHtml = '';
      for (let item of items) {
        const title = extract(item, 'title');
        const link = extract(item, 'link');
        const desc = extract(item, 'description');

        itemsHtml += `
          <article>
            <h2>${title}</h2>
            <div class="description">${desc}</div>
            <a class="btn" href="${link}" target="_blank">Read More →</a>
          </article>`;
      }

      return new Response(wrapHTML(itemsHtml), {
        headers: { 'content-type': 'text/html;charset=UTF-8' }
      });

    } catch (e) {
      return new Response(`Error fetching feed: ${e.message}`, { status: 500 });
    }
  }
};

// Helper to extract XML tags (handles CDATA and simple tags)
function extract(str, tag) {
  const regex = new RegExp(`<${tag}[^>]*>(?:<!\\[CDATA\\[)?([\\s\\S]*?)(?:\\]\\]>)?<\\/${tag}>`, 'i');
  const match = str.match(regex);
  return match ? match[1].trim() : '';
}

// Minimal CSS/Template
const wrapHTML = (content) => `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: system-ui, sans-serif; line-height: 1.6; max-width: 700px; margin: 2rem auto; padding: 1rem; background: #f4f4f7; color: #333; }
    article { background: white; padding: 2rem; border-radius: 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); margin-bottom: 2rem; }
    h2 { margin-top: 0; line-height: 1.2; }
    .description { color: #555; margin-bottom: 1.5rem; overflow-wrap: anywhere; word-break: break-word; }
    .btn { background: #0070f3; color: white; text-decoration: none; padding: 0.6rem 1.2rem; border-radius: 6px; font-weight: bold; display: inline-block; }
  </style>
</head>
<body>${content}</body>
</html>`;

const landingPageHTML = wrapHTML(`
  <h1>RSS Worker Reader</h1>
  <p>To use this, add <code>?rss=URL</code> to the address bar.</p>
  <p>Example: <code>?rss=https://www.theverge.com/rss/index.xml&count=3</code></p>
`);