-- Nightly Steam sync for Save File.
-- Updates hours and last-played for your Steam games, adds new purchases,
-- and keeps "Currently playing" fresh. Runs every night at about 4:15am Eastern.
-- It does nothing until a Steam Web API key is saved (see the last section).

create extension if not exists http with schema extensions;
create extension if not exists pg_cron;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.settings (k text primary key, v text not null);
revoke all on private.settings from public, anon, authenticated;

create or replace function public.steam_sync_apply(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  g jsonb; gid text; cur jsonb; hours numeric; last_ts bigint; last_d text;
  now_ms bigint := (extract(epoch from now())*1000)::bigint;
  added int := 0; updated int := 0; st text; title text;
begin
  for g in select * from jsonb_array_elements(coalesce(payload->'response'->'games','[]'::jsonb)) loop
    title := g->>'name';
    continue when title is null
      or title ~* '(test server|staging branch|playtest|dedicated server)'
      or (g->>'appid') in ('431960','993090','905370');   -- Wallpaper Engine, Lossless Scaling, placeholder page
    gid := 'steam-' || (g->>'appid');
    hours := round(coalesce((g->>'playtime_forever')::numeric,0)/60.0, 1);
    last_ts := coalesce((g->>'rtime_last_played')::bigint,0);
    last_d := case when last_ts>0 then to_char(to_timestamp(last_ts) at time zone 'UTC','YYYY-MM-DD') else '' end;
    select data into cur from games where id = gid;
    if cur is null then
      st := case when hours=0 then 'backlog' when last_ts > extract(epoch from now()) - 30*86400 and hours >= 1 then 'playing' else 'played' end;
      insert into games(id, data) values (gid, jsonb_build_object(
        'title', regexp_replace(title,'[™®]','','g'), 'platform','PC', 'status',st, 'steam',g->>'appid', 'img','',
        'hours', case when hours=0 then null else hours end, 'lastPlayed', last_d,
        'rating',null,'review','','spoiler',false,'tags',jsonb_build_array('Steam'),'sessions','[]'::jsonb,'hltb','{}'::jsonb,
        'top',0,'priority',2,'started','','finished','','createdAt',now_ms,'updatedAt',now_ms));
      added := added + 1;
    else
      st := cur->>'status';
      if hours > coalesce((cur->>'hours')::numeric,0) or last_d > coalesce(cur->>'lastPlayed','') then
        -- new play time: games you just played move to Playing (finished/dropped games keep their status)
        if st in ('backlog','played','shelved') and last_ts > extract(epoch from now()) - 14*86400 then st := 'playing'; end if;
        update games set data = data || jsonb_build_object('hours', greatest(hours, coalesce((cur->>'hours')::numeric,0)),
          'lastPlayed', greatest(last_d, coalesce(cur->>'lastPlayed','')), 'status', st, 'updatedAt', now_ms),
          updated_at = now() where id = gid;
        updated := updated + 1;
      elsif st = 'playing' and last_d <> '' and last_d < to_char(now() - interval '45 days','YYYY-MM-DD') then
        -- not touched in 45 days: drop it out of Currently playing
        update games set data = data || jsonb_build_object('status','played'), updated_at = now() where id = gid;
        updated := updated + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('added', added, 'updated', updated);
end $$;

create or replace function public.steam_sync()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_key text; v_sid text; resp record;
begin
  select v into v_key from private.settings where k = 'steam_key';
  select v into v_sid from private.settings where k = 'steam_id';
  if v_key is null or v_sid is null then return jsonb_build_object('skipped','no Steam key saved yet'); end if;
  select status, content into resp from extensions.http_get(
    'https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?include_appinfo=1&include_played_free_games=1&key='
    || extensions.urlencode(v_key) || '&steamid=' || extensions.urlencode(v_sid));
  if resp.status <> 200 then return jsonb_build_object('error', resp.status); end if;
  return public.steam_sync_apply(resp.content::jsonb);
end $$;

revoke execute on function public.steam_sync_apply(jsonb) from public, anon, authenticated;
revoke execute on function public.steam_sync() from public, anon, authenticated;

insert into private.settings(k, v) values ('steam_id', '76561198174796294') on conflict (k) do nothing;

select cron.unschedule(jobid) from cron.job where jobname = 'steam-sync';
select cron.schedule('steam-sync', '14 8 * * *', 'select public.steam_sync()');

-- To turn it on, run this one line with your key from https://steamcommunity.com/dev/apikey :
-- insert into private.settings(k, v) values ('steam_key', 'PASTE_KEY_HERE') on conflict (k) do update set v = excluded.v;
-- Then run  select public.steam_sync();  once to sync immediately.
