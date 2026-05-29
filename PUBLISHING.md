# Publishing the Barovia player site

This folder is a [Quartz v5](https://quartz.jzhao.xyz) site that publishes selected
notes from the Obsidian vault to **https://askwho.github.io/he-is-the-land/**.

Hosting is free (GitHub Pages). The repo is **public**, so the Markdown of any
published note is readable on GitHub — but only notes you explicitly mark are ever
copied here. Your DM vault stays private on your machine.

## Per-session file convention

Keep DM and player material in **separate files** — never publish your DM notes:

- `Session_XX_Notes.md` — your full DM notes. **No `publish` flag; left untouched.**
- `Session_XX_Player_Recap.md` — the narrative recap for players (`publish: true`).
- `Session_XX_Player_Notes.md` — the detailed field-notes log for players, trimmed of
  spoilers and table-meta (`publish: true`).

## How to publish a note

1. **In the vault**, add this to the note's frontmatter (the `---` block at the very top):

   ```yaml
   ---
   title: "Session 2 — Recap"
   publish: true
   ---
   ```

   Only notes with `publish: true` are ever copied to the site.

2. **Hide DM-only bits** inside a published note by wrapping them in Obsidian comments:

   ```
   %%
   This text is invisible in Obsidian reading view AND is stripped out
   before anything is copied to the site. Safe for spoilers / DM reminders.
   %%
   ```

   `%% inline comments %%` work too.

3. **Publish:**

   ```powershell
   cd "C:\Users\askew\Documents\DnD\Barovia\PlayerSite"
   .\publish.ps1 -Push                       # sync + build + go live
   .\publish.ps1 -Push -Message "Add S2"     # with a custom commit message
   ```

   The live site updates ~1-2 minutes after the push (GitHub Actions rebuilds it).

## Preview locally before going live

```powershell
.\publish.ps1                  # sync + build only, nothing goes public
npx quartz build --serve       # then open http://localhost:8080
```

## Two layers of spoiler protection

1. **`publish.ps1`** only copies notes marked `publish: true`, and strips `%% ... %%`
   comments before copying — so DM text never reaches this folder or GitHub.
2. **Quartz's `explicit-publish` plugin** is enabled, so even if an unmarked note
   landed in `content/`, it would not be rendered.

## Where things live

- `content/index.md` — the site's home page (edit freely; it is *not* overwritten by sync).
- `content/...`       — synced copies of published vault notes (regenerated each run; don't edit here).
- `quartz.config.yaml` — site title, colors, plugins.
- `.github/workflows/deploy.yml` — the GitHub Pages auto-deploy.
