#!/usr/bin/env python3
"""Part 2: rewrite _write_*_needs helpers."""
from pathlib import Path
import subprocess, os, re

os.chdir("/home/ordo/ordo-dev")
subprocess.check_call(["git", "fetch", "origin"])
subprocess.check_call(["git", "checkout", "feature/clear-semantics"])
subprocess.check_call(["git", "pull", "--ff-only", "origin", "feature/clear-semantics"])
p = Path("lib/ordo.pm")
t = p.read_text()
C = []


def replace_func(name, new_body):
    global t
    m = re.search(rf"^sub {name} \{{", t, re.M)
    if not m:
        print("MISS sub", name)
        return False
    start = m.start()
    i = m.end() - 1
    depth = 0
    for j in range(i, len(t)):
        if t[j] == "{":
            depth += 1
        elif t[j] == "}":
            depth -= 1
            if depth == 0:
                end = j + 1
                if end < len(t) and t[end] == "\n":
                    end += 1
                t = t[:start] + new_body + t[end:]
                C.append(name)
                print("OK replaced", name)
                return True
    print("MISS braces", name)
    return False


write_job = r"""sub _write_job_needs {
   my ( $self, $user, $d ) = @_;
   my $job_id = $d->{id};
   return unless $job_id;

   my $touch_all = $d->{touch_all};
   my $touch_any = $d->{touch_any};
   if ( !defined $touch_all && !defined $touch_any ) {
      $touch_all = exists $d->{needs_all};
      $touch_any = exists $d->{needs_any};
      return 1 unless $touch_all || $touch_any;
   }
   return 1 unless $touch_all || $touch_any;

   my $needs_all = $d->{needs_all} // [];
   my $needs_any = $d->{needs_any} // [];
   $needs_all = [] unless ref $needs_all eq 'ARRAY';
   $needs_any = [] unless ref $needs_any eq 'ARRAY';

   my $tx = $self->sqlite->db->begin;

   if ($touch_all) {
      $self->sqlite->db->query(
         'DELETE FROM job_needs WHERE job_id = ? AND needs_any_mode = 0',
         $job_id );
      for my $target_id (@$needs_all) {
         next unless defined $target_id && $target_id =~ /^\d+$/;
         $self->sqlite->db->query(
'INSERT OR IGNORE INTO job_needs (job_id, needs_job_id, needs_any_mode) VALUES (?, ?, 0)',
            $job_id, $target_id
         );
      }
   }

   if ($touch_any) {
      $self->sqlite->db->query(
         'DELETE FROM job_needs WHERE job_id = ? AND needs_any_mode = 1',
         $job_id );
      for my $target_id (@$needs_any) {
         next unless defined $target_id && $target_id =~ /^\d+$/;
         $self->sqlite->db->query(
'INSERT OR IGNORE INTO job_needs (job_id, needs_job_id, needs_any_mode) VALUES (?, ?, 1)',
            $job_id, $target_id
         );
      }
   }

   $tx->commit;
   return 1;
}
"""

write_cluster = r"""sub _write_cluster_needs {
   my ( $self, $user, $d ) = @_;
   my $cluster_id = $d->{id};
   return unless $cluster_id;

   my $touch_all = $d->{touch_all};
   my $touch_any = $d->{touch_any};
   if ( !defined $touch_all && !defined $touch_any ) {
      $touch_all = exists $d->{needs_all};
      $touch_any = exists $d->{needs_any};
      return 1 unless $touch_all || $touch_any;
   }
   return 1 unless $touch_all || $touch_any;

   my $needs_all = $d->{needs_all} // [];
   my $needs_any = $d->{needs_any} // [];
   $needs_all = [] unless ref $needs_all eq 'ARRAY';
   $needs_any = [] unless ref $needs_any eq 'ARRAY';

   my $tx = $self->sqlite->db->begin;

   if ($touch_all) {
      $self->sqlite->db->query(
         'DELETE FROM cluster_needs WHERE cluster_id = ? AND needs_any_mode = 0',
         $cluster_id );
      for my $target_id (@$needs_all) {
         next unless defined $target_id && $target_id =~ /^\d+$/;
         $self->sqlite->db->query(
'INSERT INTO cluster_needs (cluster_id, needs_cluster_id, needs_any_mode) VALUES (?, ?, 0)',
            $cluster_id, $target_id
         );
      }
   }

   if ($touch_any) {
      $self->sqlite->db->query(
         'DELETE FROM cluster_needs WHERE cluster_id = ? AND needs_any_mode = 1',
         $cluster_id );
      for my $target_id (@$needs_any) {
         next unless defined $target_id && $target_id =~ /^\d+$/;
         $self->sqlite->db->query(
'INSERT INTO cluster_needs (cluster_id, needs_cluster_id, needs_any_mode) VALUES (?, ?, 1)',
            $cluster_id, $target_id
         );
      }
   }

   $tx->commit;
   return 1;
}
"""

replace_func("_write_job_needs", write_job)
replace_func("_write_cluster_needs", write_cluster)

old = """   $self->_write_job_needs(
      $user,
      {
         needs_all  => $needs_ids,
         needs_any  => $needs_any_ids,
         id         => $id,
         cluster_id => $parent_id
      }
   );"""
new = """   if ( $needs_ids || $needs_any_ids ) {
      $self->_write_job_needs(
         $user,
         {
            needs_all  => $needs_ids // [],
            needs_any  => $needs_any_ids // [],
            touch_all  => $needs_ids ? 1 : 0,
            touch_any  => $needs_any_ids ? 1 : 0,
            id         => $id,
            cluster_id => $parent_id
         }
      );
   }"""
if old in t:
    t = t.replace(old, new, 1)
    C.append("create_job needs call")
    print("OK create_job needs")
else:
    print("MISS create_job needs call")

old = """   if ( $needs_ids || $needs_any_ids ) {
      $self->_write_cluster_needs(
         $user,
         {
            needs_all => $needs_ids,
            needs_any => $needs_any_ids,
            id        => $id,
         }
      );
   }"""
new = """   if ( $needs_ids || $needs_any_ids ) {
      $self->_write_cluster_needs(
         $user,
         {
            needs_all => $needs_ids // [],
            needs_any => $needs_any_ids // [],
            touch_all => $needs_ids ? 1 : 0,
            touch_any => $needs_any_ids ? 1 : 0,
            id        => $id,
         }
      );
   }"""
if old in t:
    t = t.replace(old, new, 1)
    C.append("create_cluster needs call")
    print("OK create_cluster needs")
else:
    print("MISS create_cluster needs")

old = """   $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } );
   $self->sqlite->db->delete( 'job_needs', { job_id => $job->{id} } )
     if $d->{remove_needs};

   $self->_broadcast_job( $user, [ $job->{id} ] ) if scalar keys %$update_hash;"""
new = """   $self->sqlite->db->update( 'job', $update_hash, { id => $job->{id} } )
     if scalar keys %$update_hash;

   $self->_broadcast_job( $user, [ $job->{id} ] );"""
if old in t:
    t = t.replace(old, new, 1)
    C.append("drop job remove_needs block")
    print("OK drop job remove_needs block")
else:
    print("MISS job remove_needs block")

p.write_text(t)
print("CHANGES", C)
subprocess.check_call(["git", "add", "lib/ordo.pm"])
subprocess.check_call(["git", "rm", "-f", "dev/clear_p2.py"])
subprocess.check_call([
        "git", "commit", "-m",
        "refactor: mode-scoped needs writers; drop remove_needs job path",
])
subprocess.check_call(["git", "push", "origin", "feature/clear-semantics"])
print("PUSHED")
