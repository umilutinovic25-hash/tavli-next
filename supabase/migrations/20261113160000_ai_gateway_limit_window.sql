-- consume_ai_request sada vraća koji je prozor prekoračen ('ok', 'minute',
-- 'day'), da gateway može da javi dnevni limit kao dnevni i da kaže kada
-- ponovo važi. Prethodna verzija je vraćala boolean.
drop function public.consume_ai_request(uuid, timestamptz);

create function public.consume_ai_request(
  uid uuid,
  at timestamptz default now()
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  m timestamptz := date_trunc('minute', at);
  d timestamptz := date_trunc('day', at);
  mc integer;
  dc integer;
begin
  insert into private.ai_gateway_usage as u
    (user_id, minute_start, minute_count, day_start, day_count)
  values (uid, m, 1, d, 1)
  on conflict (user_id) do update set
    minute_count = case when u.minute_start = m then u.minute_count + 1 else 1 end,
    minute_start = m,
    day_count = case when u.day_start = d then u.day_count + 1 else 1 end,
    day_start = d
  returning minute_count, day_count into mc, dc;
  return case when dc > 300 then 'day' when mc > 20 then 'minute' else 'ok' end;
end;
$$;
revoke execute on function public.consume_ai_request(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.consume_ai_request(uuid, timestamptz) to service_role;
