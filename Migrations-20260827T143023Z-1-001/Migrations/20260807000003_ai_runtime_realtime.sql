-- Publish automatic AI endpoint/status changes to every signed-in eFlow client.
-- The frontend also polls as a fallback, so temporary Realtime outages do not
-- leave clients pinned to an obsolete Quick Tunnel hostname.

do $$
begin
  begin
    alter publication supabase_realtime add table public.system_config;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end;
$$;

insert into public.system_config (key, value, updated_at)
values (
  'ai_endpoint_status_message',
  'The AI service is offline. Its automatic tunnel supervisor is not running.',
  now()
)
on conflict (key) do nothing;
