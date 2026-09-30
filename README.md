# Save File

looski's game log: every game played, rated, ranked and reviewed. Live at https://luxtae.github.io

## How it works

- `index.html` is the whole site. It reads games from a Supabase database, so anyone can view without an account.
- Only the owner can edit, after signing in with **Owner login** at the bottom of the page. The database rules reject edits from any other account.
- Covers come from Steam's image CDN (or an uploaded or pasted image). Genres, descriptions, screenshots and Metacritic scores are pulled from Steam by database functions.

## Nightly Steam sync

A scheduled database job (`steam-sync`, around 4:15am Eastern) updates hours and last-played dates, adds new Steam games, and fills in genres, details and covers. It needs a Steam Web API key saved once in the Supabase SQL editor:

```sql
insert into private.settings(k, v) values ('steam_key', 'YOUR_KEY') on conflict (k) do update set v = excluded.v;
select public.steam_sync();
```

Get a key at https://steamcommunity.com/dev/apikey.

## Files

- `index.html` — the site
- `og.png` — link preview image
- `manifest.webmanifest`, `icon-*.png`, `apple-touch-icon.png`, `favicon.png` — app icon and home-screen install
