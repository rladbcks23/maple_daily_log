alter table characters enable row level security;
alter table character_snapshots enable row level security;
alter table starforce_events enable row level security;
alter table cube_events enable row level security;
alter table potential_events enable row level security;
alter table play_time_records enable row level security;
alter table reports enable row level security;

create policy "anon can read characters"
on characters
for select
to anon
using (true);

create policy "anon can read character snapshots"
on character_snapshots
for select
to anon
using (true);

create policy "anon can read starforce events"
on starforce_events
for select
to anon
using (true);

create policy "anon can read cube events"
on cube_events
for select
to anon
using (true);

create policy "anon can read potential events"
on potential_events
for select
to anon
using (true);

create policy "anon can read play time records"
on play_time_records
for select
to anon
using (true);

create policy "anon can read reports"
on reports
for select
to anon
using (true);
