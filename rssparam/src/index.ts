export default {
  async fetch(request) {
    // 1. Parse URL parameters from the request
    const { searchParams } = new URL(request.url);
    const rssUrls = searchParams.getAll('rss');
    const count = parseInt(searchParams.get('count')) || 1;

    // 2. Default landing page if no RSS param is provided
    if (!rssUrls.length) {
      return new Response(landingPageHTML, { 
        headers: { 'content-type': 'text/html;charset=UTF-8' } 
      });
    }

    // 3. Fetch all requested feeds in parallel
    const feedSections = await Promise.all(
      rssUrls.map(url => fetchFeedSection(url, count))
    );

    return new Response(wrapHTML('<div class="feed-grid">' + feedSections.join('') + '</div>'), {
      headers: { 'content-type': 'text/html;charset=UTF-8' }
    });
  }
};

async function fetchFeedSection(rssUrl: string, count: number) {
  try {
    // Note: Workers bypass CORS, so no proxy is needed!
    const response = await fetch(rssUrl, {
      headers: { 'User-Agent': 'Cloudflare-Worker-RSS-Reader' }
    });
    const xmlText = await response.text();

    // Feed title from the channel (first <title> in the XML)
    const feedTitle = extract(xmlText, 'title') || rssUrl;

    // Basic RSS Parsing (Simple Regex for Title, Link, Description)
    // Since Workers don't have 'DOMParser', we extract items manually
    const items = xmlText.split('<item>').slice(1, count + 1);

    let itemsHtml = '';
    for (let item of items) {
      const title = extract(item, 'title');
      const link = extract(item, 'link');
      const desc = extract(item, 'description');

      itemsHtml += `
          <article>
            <h3>${title}</h3>
            <div class="description">${desc}</div>
            <a class="btn" href="${link}" target="_blank">Read More →</a>
          </article>`;
    }

    if (!itemsHtml) {
      itemsHtml = '<p><em>No items found in this feed.</em></p>';
    }

    return `
      <section>
        <h2>${feedTitle}</h2>
        ${itemsHtml}
      </section>`;

  } catch (e) {
    return `
      <section>
        <h2>Error fetching ${rssUrl}</h2>
        <p>${e.message}</p>
      </section>`;
  }
}

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
    body { font-family: system-ui, sans-serif; line-height: 1.6; max-width: 960px; margin: 2rem auto; padding: 1rem; background: #f4f4f7; color: #333; }
    .feed-grid { column-width: 380px; column-gap: 1.5rem; display: block; }
    .feed-grid > section { break-inside: avoid; margin-bottom: 1.5rem; display: inline-block; width: 100%; background: white; padding: 2rem; border-radius: 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); box-sizing: border-box; }
    h2 { margin-top: 0; line-height: 1.2; }
    h3 { margin-bottom: 0.5rem; }
    .description { color: #555; margin-bottom: 1.5rem; overflow-wrap: anywhere; word-break: break-word; }
    .btn { background: #0070f3; color: white; text-decoration: none; padding: 0.6rem 1.2rem; border-radius: 6px; font-weight: bold; display: inline-block; }
  </style>
</head>
<body>${content}</body>
</html>`;

const landingPageHTML = wrapHTML(`
  <h1>RSS Worker Reader</h1>
  <p>To use this, add one or more <code>?rss=URL</code> parameters.</p>
  <p>Single feed:<br><code>?rss=https://www.theverge.com/rss/index.xml&count=3</code></p>
  <p>Multiple feeds:<br><code>?rss=https://www.theverge.com/rss/index.xml&rss=https://news.ycombinator.com/rss&count=3</code></p>
`);