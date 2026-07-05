// Generates the podcast RSS feed (public/podcast/feed.xml) from episodes.json.
// Run after `npx quartz build` — the build wipes public/, so the feed is written last.
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const { show, episodes } = JSON.parse(readFileSync(join(root, "episodes.json"), "utf8"));

const esc = (s) =>
  s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");

const fmtDur = (sec) => {
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
};

const items = [...episodes]
  .sort((a, b) => b.number - a.number)
  .map((ep) => `    <item>
      <title>${esc(`${ep.number}. ${ep.title}`)}</title>
      <link>${esc(`${show.siteUrl}/${ep.page}`)}</link>
      <guid isPermaLink="false">he-is-the-land-s${String(ep.number).padStart(2, "0")}</guid>
      <pubDate>${new Date(ep.pubDate).toUTCString()}</pubDate>
      <description>${esc(ep.description)}</description>
      <enclosure url="${esc(`${show.audioBase}/${ep.file}`)}" length="${ep.bytes}" type="audio/mpeg"/>
      <itunes:episode>${ep.number}</itunes:episode>
      <itunes:duration>${fmtDur(ep.durationSec)}</itunes:duration>
      <itunes:explicit>${show.explicit}</itunes:explicit>
      <itunes:image href="${esc(ep.imageUrl || show.imageUrl)}"/>
    </item>`)
  .join("\n");

const feed = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>${esc(show.title)}</title>
    <link>${esc(show.podcastPage)}</link>
    <description>${esc(show.description)}</description>
    <language>${show.language}</language>
    <atom:link href="${esc(show.feedUrl)}" rel="self" type="application/rss+xml"/>
    <itunes:author>${esc(show.author)}</itunes:author>
    <itunes:subtitle>${esc(show.subtitle)}</itunes:subtitle>
    <itunes:summary>${esc(show.description)}</itunes:summary>
    <itunes:owner><itunes:name>${esc(show.author)}</itunes:name><itunes:email>${esc(show.email)}</itunes:email></itunes:owner>
    <itunes:image href="${esc(show.imageUrl)}"/>
    <itunes:category text="${esc(show.category)}"><itunes:category text="${esc(show.subcategory)}"/></itunes:category>
    <itunes:explicit>${show.explicit}</itunes:explicit>
    <itunes:type>episodic</itunes:type>
${items}
  </channel>
</rss>
`;

const out = join(root, "public", "podcast", "feed.xml");
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, feed);
console.log(`Wrote ${out} (${episodes.length} episodes)`);
