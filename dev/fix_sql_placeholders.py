#!/usr/bin/env python3
"""Replace interpolated SQL in lib/ordo.pm with placeholders."""
from pathlib import Path
import re
import sys

p = Path("/home/ordo/ordo-dev/lib/ordo.pm")
text = p.read_text()
orig = text
changes = []

def replace_once(old, new, label):
    global text
    n = text.count(old)
    if n == 0:
        print(f"MISS {label}")
        return False
    if n > 1:
        print(f"WARN {label}: found {n} times, replacing all")
    text = text.replace(old, new)
    changes.append(f"{label} x{n}")
    return True

# 1a startup cron count
old = '''my $count = $self->sqlite->db->query(\n         "select count(*) as count from cluster where cal_id = $a->{cal_id}")\n        ->hash->{count};'''
new = '''my $count = $self->sqlite->db->query(\n         'select count(*) as count from cluster where cal_id = ?',\n         $a->{cal_id} )->hash->{count};'''
# Use real newlines
old = old.replace('\\n', '\n')
new = new.replace('\\n', '\n')
replace_once(old, new, "startup cal count")

old = '''my $count = $self->sqlite->db->query(\n         "select count(*) as count from cluster where cal_id = $c->{cal_id}")\n        ->hash->{count};'''.replace('\\n','\n')
new = '''my $count = $self->sqlite->db->query(\n         'select count(*) as count from cluster where cal_id = ?',\n         $c->{cal_id} )->hash->{count};'''.replace('\\n','\n')
replace_once(old, new, "delete_cluster cal count")

old = '''my $count = $self->sqlite->db->query(\n         "select count(*) as count from cluster where cal_id = $old_cal_id")\n        ->hash->{count};'''.replace('\\n','\n')
new = '''my $count = $self->sqlite->db->query(\n         'select count(*) as count from cluster where cal_id = ?',\n         $old_cal_id )->hash->{count};'''.replace('\\n','\n')
replace_once(old, new, "set_cal_id old count")

old = '''my $count = $self->sqlite->db->query(\n         "select count(*) as count from cluster where cal_id = $new_cal_id")\n        ->hash->{count};'''.replace('\\n','\n')
new = '''my $count = $self->sqlite->db->query(\n         'select count(*) as count from cluster where cal_id = ?',\n         $new_cal_id )->hash->{count};'''.replace('\\n','\n')
replace_once(old, new, "set_cal_id new count")

old = '''my $count = $self->sqlite->db->query(\n      "select count(*) as count from cluster where cal_id = $cal_info->{id}")\n     ->hash->{count};'''.replace('\\n','\n')
new = '''my $count = $self->sqlite->db->query(\n      'select count(*) as count from cluster where cal_id = ?',\n      $cal_info->{id} )->hash->{count};'''.replace('\\n','\n')
replace_once(old, new, "add_cron cal count")

old = '''my $sql = <<~"SQL";\n     select max(year_month) as current_month_year, call_count from usage_counters where org_id = $org_id\n   SQL\n\n   my $usage = $self->sqlite->db->query($sql)->hash;'''.replace('\\n','\n')
new = '''my $usage = $self->sqlite->db->query(\n     'select max(year_month) as current_month_year, call_count from usage_counters where org_id = ?',\n     $org_id )->hash;'''.replace('\\n','\n')
replace_once(old, new, "usage_counters org")

old = '''my $server_count = $self->sqlite->db->query(\n      "select count(*) as count from server where org_id = $org_id")\n     ->hash->{count};'''.replace('\\n','\n')
new = '''my $server_count = $self->sqlite->db->query(\n      'select count(*) as count from server where org_id = ?',\n      $org_id )->hash->{count};'''.replace('\\n','\n')
replace_once(old, new, "server count org")

old = '''my $count = $self->sqlite->db->query(\n      "select count(*) as count from job where cluster_id = $job->{cluster_id}")\n     ->hash->{count};'''.replace('\\n','\n')
new = '''my $count = $self->sqlite->db->query(\n      'select count(*) as count from job where cluster_id = ?',\n      $job->{cluster_id} )->hash->{count};'''.replace('\\n','\n')
replace_once(old, new, "delete_job job count")

old = '''my $sql = <<~"SQL";\n      select j.*, c.org_id,\n      s.name as server_name, js.state as jobstate\n      from job j\n      join cluster c on j.cluster_id = c.id\n      left join server s on j.server_id = s.id\n      left join job_states js on j.state_id = js.id\n      where c.org_id = $org_id \n      and j.id = $job_id \n   SQL\n\n   my $job = $self->sqlite->db->query($sql)->hash;'''.replace('\\n','\n')
new = '''my $sql = <<~'SQL';\n      select j.*, c.org_id,\n      s.name as server_name, js.state as jobstate\n      from job j\n      join cluster c on j.cluster_id = c.id\n      left join server s on j.server_id = s.id\n      left join job_states js on j.state_id = js.id\n      where c.org_id = ?\n      and j.id = ?\n   SQL\n\n   my $job = $self->sqlite->db->query( $sql, $org_id, $job_id )->hash;'''.replace('\\n','\n')
replace_once(old, new, "_job_info")

old = '''my $depends_sql = <<~"SQL";\n         SELECT cn.cluster_id AS id\n         FROM cluster_needs cn\n         JOIN cluster c ON cn.cluster_id = c.id\n         WHERE cn.needs_cluster_id = $cluster_id\n           AND c.state_id IN ($ready, $waiting, $ice)\n      SQL\n\n      my $cneed = $self->sqlite->db->query($depends_sql);'''.replace('\\n','\n')
new = '''my $depends_sql = <<~'SQL';\n         SELECT cn.cluster_id AS id\n         FROM cluster_needs cn\n         JOIN cluster c ON cn.cluster_id = c.id\n         WHERE cn.needs_cluster_id = ?\n           AND c.state_id IN (?, ?, ?)\n      SQL\n\n      my $cneed = $self->sqlite->db->query(\n         $depends_sql, $cluster_id, $ready, $waiting, $ice );'''.replace('\\n','\n')
replace_once(old, new, "cluster depends_sql")

old = '''my $depends_sql = <<~"SQL";\n         SELECT jn.job_id, j.state_id, jn.needs_any_mode\n         FROM job_needs jn\n         JOIN job j ON jn.job_id = j.id\n         WHERE jn.needs_job_id = $job_id\n           AND j.state_id IN ($ready, $waiting, $ice)\n      SQL\n\n      my $need = $self->sqlite->db->query($depends_sql);'''.replace('\\n','\n')
new = '''my $depends_sql = <<~'SQL';\n         SELECT jn.job_id, j.state_id, jn.needs_any_mode\n         FROM job_needs jn\n         JOIN job j ON jn.job_id = j.id\n         WHERE jn.needs_job_id = ?\n           AND j.state_id IN (?, ?, ?)\n      SQL\n\n      my $need = $self->sqlite->db->query(\n         $depends_sql, $job_id, $ready, $waiting, $ice );'''.replace('\\n','\n')
replace_once(old, new, "job depends_sql")

old = '''my $all_sql = <<~"SQL";\n      select cn.needs_cluster_id, c.state_id, cn.cluster_id\n      from cluster c \n      join cluster_needs cn on c.id = cn.needs_cluster_id\n      where c.state_id not in ($complete,$ice)\n      and cn.needs_any_mode = 0\n      and cn.cluster_id = ?;\n   SQL\n\n   my $not_met = $self->sqlite->db->query( $all_sql, $d->{id} )->hash;'''.replace('\\n','\n')
new = '''my $all_sql = <<~'SQL';\n      select cn.needs_cluster_id, c.state_id, cn.cluster_id\n      from cluster c \n      join cluster_needs cn on c.id = cn.needs_cluster_id\n      where c.state_id not in (?,?)\n      and cn.needs_any_mode = 0\n      and cn.cluster_id = ?;\n   SQL\n\n   my $not_met = $self->sqlite->db->query( $all_sql, $complete, $ice, $d->{id} )->hash;'''.replace('\\n','\n')
replace_once(old, new, "cluster_needs_met all")

old = '''my $any_sql = <<~"SQL";\n      select cn.needs_cluster_id, c.state_id, cn.cluster_id\n      from cluster c \n      join cluster_needs cn on c.id = cn.needs_cluster_id\n      where c.state_id in ($complete,$ice)\n      and cn.needs_any_mode = 1\n      and cn.cluster_id = ?;\n   SQL\n\n   my $met     = $self->sqlite->db->query( $any_sql, $d->{id} )->hash;'''.replace('\\n','\n')
new = '''my $any_sql = <<~'SQL';\n      select cn.needs_cluster_id, c.state_id, cn.cluster_id\n      from cluster c \n      join cluster_needs cn on c.id = cn.needs_cluster_id\n      where c.state_id in (?,?)\n      and cn.needs_any_mode = 1\n      and cn.cluster_id = ?;\n   SQL\n\n   my $met     = $self->sqlite->db->query( $any_sql, $complete, $ice, $d->{id} )->hash;'''.replace('\\n','\n')
replace_once(old, new, "cluster_needs_met any")

old = '''my $all_sql = <<~"SQL";\n      select jn.needs_job_id, j.state_id, jn.job_id\n      from job j\n      join job_needs jn on j.id = jn.needs_job_id \n      where j.state_id not in ($complete,$ice)\n      and jn.needs_any_mode = 0\n      and jn.job_id = ?;\n   SQL\n\n   my $not_met = $self->sqlite->db->query( $all_sql, $d->{id} )->hash;'''.replace('\\n','\n')
new = '''my $all_sql = <<~'SQL';\n      select jn.needs_job_id, j.state_id, jn.job_id\n      from job j\n      join job_needs jn on j.id = jn.needs_job_id \n      where j.state_id not in (?,?)\n      and jn.needs_any_mode = 0\n      and jn.job_id = ?;\n   SQL\n\n   my $not_met = $self->sqlite->db->query( $all_sql, $complete, $ice, $d->{id} )->hash;'''.replace('\\n','\n')
replace_once(old, new, "job_needs_met all")

old = '''my $any_sql = <<~"SQL";\n      select jn.needs_job_id, j.state_id, jn.job_id\n      from job j\n      join job_needs jn on j.id = jn.needs_job_id\n      where j.state_id in ($complete,$ice)\n      and jn.needs_any_mode = 1 \n      and jn.job_id = ?;\n   SQL\n\n   my $met     = $self->sqlite->db->query( $any_sql, $d->{id} )->hash;'''.replace('\\n','\n')
new = '''my $any_sql = <<~'SQL';\n      select jn.needs_job_id, j.state_id, jn.job_id\n      from job j\n      join job_needs jn on j.id = jn.needs_job_id\n      where j.state_id in (?,?)\n      and jn.needs_any_mode = 1 \n      and jn.job_id = ?;\n   SQL\n\n   my $met     = $self->sqlite->db->query( $any_sql, $complete, $ice, $d->{id} )->hash;'''.replace('\\n','\n')
replace_once(old, new, "job_needs_met any")

old = '''my $jobs = $self->sqlite->db->query(\n"select * from job where (pid is not null or ppid is not null) and server_id = $d->{id}"\n   )->hashes->to_array;'''.replace('\\n','\n')
new = '''my $jobs = $self->sqlite->db->query(\n      'select * from job where (pid is not null or ppid is not null) and server_id = ?',\n      $d->{id}\n   )->hashes->to_array;'''.replace('\\n','\n')
replace_once(old, new, "sync_server jobs")

old = '''my $jobs = $self->sqlite->db->query(\n"select * from job where (pid is not null or ppid is not null) and server_id = $server->{id}"\n      )->hashes->to_array;'''.replace('\\n','\n')
new = '''my $jobs = $self->sqlite->db->query(\n         'select * from job where (pid is not null or ppid is not null) and server_id = ?',\n         $server->{id}\n      )->hashes->to_array;'''.replace('\\n','\n')
replace_once(old, new, "sync jobs")

old = '''$log = $self->sqlite->db->query(\n"select * from job_log where job_id = $job->{id} order by id desc limit 1"\n      )->hash;'''.replace('\\n','\n')
new = '''$log = $self->sqlite->db->query(\n         'select * from job_log where job_id = ? order by id desc limit 1',\n         $job->{id}\n      )->hash;'''.replace('\\n','\n')
replace_once(old, new, "log_info latest")

old = '''my $sql    = <<~"SQL";\n      select cron.id as cron_id, cal.id as cal_id\n      from cron\n      join cal on cron.cal_id = cal.id\n      where cal.org_id = $org_id\n      and cron.id = $d->{id}\n   SQL\n\n   my $cal = $self->sqlite->db->query($sql)->hash;'''.replace('\\n','\n')
new = '''my $sql    = <<~'SQL';\n      select cron.id as cron_id, cal.id as cal_id\n      from cron\n      join cal on cron.cal_id = cal.id\n      where cal.org_id = ?\n      and cron.id = ?\n   SQL\n\n   my $cal = $self->sqlite->db->query( $sql, $org_id, $d->{id} )->hash;'''.replace('\\n','\n')
replace_once(old, new, "delete_cron")

old = '''my $c = $self->sqlite->db->query(\n"select cron.*, cal.tz from cron join cal on cron.cal_id = cal.id where cron.id = $d->{id}"\n   )->hash;'''.replace('\\n','\n')
new = '''my $c = $self->sqlite->db->query(\n      'select cron.*, cal.tz from cron join cal on cron.cal_id = cal.id where cron.id = ?',\n      $d->{id}\n   )->hash;'''.replace('\\n','\n')
replace_once(old, new, "cron_next_start")

old = '''my $sql = <<~"SQL";\n      select min(next_start) as ns\n      from cron\n      where cal_id = $cal_id\n      and next_start is not null\n      and next_start >= unixepoch('now');\n   SQL\n\n   my $next_start = $self->sqlite->db->query($sql)->hash->{ns};'''.replace('\\n','\n')
new = '''my $sql = <<~'SQL';\n      select min(next_start) as ns\n      from cron\n      where cal_id = ?\n      and next_start is not null\n      and next_start >= unixepoch('now');\n   SQL\n\n   my $next_start = $self->sqlite->db->query( $sql, $cal_id )->hash->{ns};'''.replace('\\n','\n')
replace_once(old, new, "cal_next_start")

remaining = []
for i, line in enumerate(text.splitlines(), 1):
    if line.lstrip().startswith("#"):
        continue
    if re.search(r'"(select |delete from |update |insert )', line, re.I) and "$" in line:
        remaining.append(f"{i}: {line.strip()[:120]}")
    if '<<~"SQL"' in line:
        remaining.append(f"{i}: still interpolating heredoc {line.strip()}")

print("CHANGES:")
for c in changes:
    print(" ", c)
print(f"total replacements: {len(changes)}")
if text == orig:
    print("NO CHANGES APPLIED - abort")
    sys.exit(1)

p.write_text(text)
print("wrote", p)
print("REMAINING suspects:")
for r in remaining:
    print(" ", r)
if not remaining:
    print("  (none)")
