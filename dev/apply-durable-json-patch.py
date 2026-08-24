#!/usr/bin/env python3
"""Apply durable ORDO_JSON patches to ordo.pm and Tools.pm.

Run from repo root or with REPO=/path/to/ordo-dev.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path.cwd())
ordo_path = ROOT / "lib/ordo.pm"
tools_path = ROOT / "lib/ordo/MCP/Tools.pm"
ordo = ordo_path.read_text()
tools = tools_path.read_text()
orig_ordo_len = len(ordo)
orig_tools_len = len(tools)
changes = []

# 1) validate_params type 'j'
old_j = """   elsif ( $type eq 'j' ) {     # JSON object
      eval { JSON::PP->new->decode($value) };
      return ( 0, "invalid JSON for $key" ) if $@;
      $clean->{$key} = $value;
   }"""
new_j = r"""   elsif ( $type eq 'j' ) {     # JSON object (string); null/'' clear
      if ( !defined $value || $value eq '' ) {
         $clean->{$key} = undef;    # clear column
         next;
      }
      if ( length($value) > 65536 ) {
         return ( 0, "$key exceeds 64 KB limit" );
      }
      my $decoded;
      eval { $decoded = JSON::PP->new->decode($value) };
      return ( 0, "invalid JSON for $key" ) if $@;
      return ( 0, "$key must be a JSON object" )
        unless ref($decoded) eq 'HASH';
      $clean->{$key} = $value;
   }"""
if old_j not in ordo:
    sys.exit("FAIL: validate_params type j block not found")
ordo = ordo.replace(old_j, new_j, 1)
changes.append("validate_params type j")

# 2) request() keep json key when undef
old_req = """   my $params  = {
      map  { $_ => $decoded->{$_} }
      grep { defined $decoded->{$_} } keys %$decoded
   };"""
new_req = """   my $params  = {
      map  { $_ => $decoded->{$_} }
      grep {
         defined $decoded->{$_}
           || $_ eq 'json'    # allow null to clear attached json
      } keys %$decoded
   };"""
if old_req not in ordo:
    sys.exit("FAIL: request() params filter not found")
ordo = ordo.replace(old_req, new_req, 1)
changes.append("request() keep json key")

# 3) remove job json clear on ready/waiting
cleared = False
for p in [
    "      # Clear job-level json on reset (new cycle = fresh data)\n"
    "      # Cluster-level json is left alone (shared config survives).\n"
    "      $update_hash->{json} = undef;\n",
    "      $update_hash->{json} = undef;\n",
]:
    if p in ordo:
        ordo = ordo.replace(
            p, "      # job json is durable — not cleared on ready/waiting\n", 1
        )
        cleared = True
        changes.append("removed job json clear on reset")
        break
if not cleared:
    m = re.search(r".{0,100}\$update_hash->\{json\} = undef;.{0,60}", ordo)
    if m:
        print("FOUND nearby:", repr(m.group(0)[:200]))
    sys.exit("FAIL: job json clear line not found")

# 4) _start_job: select cluster json
old_cluster_sel = (
    "   my $cluster = $self->sqlite->db->select( 'cluster', ['handler_context'],\n"
    "      { id => $job->{cluster_id} } )->hash;"
)
new_cluster_sel = (
    "   my $cluster = $self->sqlite->db->select( 'cluster', [ 'handler_context', 'json' ],\n"
    "      { id => $job->{cluster_id} } )->hash;"
)
if old_cluster_sel not in ordo:
    sys.exit("FAIL: cluster select in _start_job not found")
ordo = ordo.replace(old_cluster_sel, new_cluster_sel, 1)
changes.append("_start_job select cluster.json")

if "#json => $job->{json} || undef," in ordo:
    ordo = ordo.replace(
        "#json => $job->{json} || undef,",
        "job_json     => $job->{json},\n"
        "         cluster_json => $cluster->{json},",
        1,
    )
    changes.append("_start_job pass job_json/cluster_json")
elif "job_json" not in ordo:
    old_tok = None
    for cand in [
        "token => $job->{token},",
        "token         => $job->{token},",
        "token   => $job->{token},",
    ]:
        if cand in ordo:
            old_tok = cand
            break
    if not old_tok:
        sys.exit("FAIL: token line in _start_job opts not found")
    ordo = ordo.replace(
        old_tok,
        old_tok
        + "\n         job_json     => $job->{json},\n"
        + "         cluster_json => $cluster->{json},",
        1,
    )
    changes.append("_start_job insert job_json/cluster_json after token")

# 5) exists $d->{json}
old_if = "if ( $d->{json} )"
n = ordo.count(old_if)
if n:
    ordo = ordo.replace(old_if, "if ( exists $d->{json} )")
    changes.append(f"exists $d->{{json}} ({n} sites)")
else:
    print("WARN: no if ( $d->{json} ) found")

# ---------- Tools.pm ----------
old_use = "use MIME::Base64 ();\n"
new_use = """use MIME::Base64 ();
use Mojo::JSON qw(encode_json);

# MCP `json` arg: object -> JSON string; null/empty -> '' (clear via API)
sub _normalize_json_arg {
   my ($payload) = @_;
   return $payload unless exists $payload->{json};
   my $j = $payload->{json};
   if ( !defined $j || ( !ref($j) && $j eq '' ) ) {
      $payload->{json} = '';
   }
   elsif ( ref $j ) {
      $payload->{json} = encode_json($j);
   }
   return $payload;
}
"""
if old_use not in tools:
    sys.exit("FAIL: Tools.pm MIME::Base64 use not found")
tools = tools.replace(old_use, new_use, 1)
changes.append("Tools.pm helper")

JSON_PROP = """               json => {
                  type        => 'object',
                  description =>
'Arbitrary JSON object attached to this entity. Durable across reset. '
. 'Injected as ORDO_JOB_JSON (job) or ORDO_CLUSTER_JSON (cluster) when non-empty. '
. 'Use for parameters (repo, branch, dirs, flags)—not for secrets. Max 64 KB. '
. 'Pass null to clear.',
               },
"""

old_cj = """               delay               => { type => 'integer' },
               max_runtime_seconds => {
                  type        => 'integer',
                  description =>
'Exceeding max_runtime_seconds starts the configured handler cluster; it does not automatically kill the job. Kill, notify, or recover as you define in the handler'
               },
               max_runtime_cluster_id => { type => 'integer' },
            },
            required => [ 'name', 'script', 'parent_id', 'server_id' ],"""
new_cj = (
    "               delay               => { type => 'integer' },\n"
    + JSON_PROP
    + """               max_runtime_seconds => {
                  type        => 'integer',
                  description =>
'Exceeding max_runtime_seconds starts the configured handler cluster; it does not automatically kill the job. Kill, notify, or recover as you define in the handler'
               },
               max_runtime_cluster_id => { type => 'integer' },
            },
            required => [ 'name', 'script', 'parent_id', 'server_id' ],"""
)
if old_cj not in tools:
    sys.exit("FAIL: create_job properties block not found")
tools = tools.replace(old_cj, new_cj, 1)
changes.append("Tools create_job json prop")

old_cjh = """            if ( $payload->{script} && !$payload->{script_b64} ) {
               $payload->{script_b64} =
                 MIME::Base64::encode_base64( $payload->{script}, '' );
               delete $payload->{script};
            }
            $c->app->request( $c->stash('user'),
               { command => 'create_job', %$payload } );"""
new_cjh = """            if ( $payload->{script} && !$payload->{script_b64} ) {
               $payload->{script_b64} =
                 MIME::Base64::encode_base64( $payload->{script}, '' );
               delete $payload->{script};
            }
            _normalize_json_arg($payload);
            $c->app->request( $c->stash('user'),
               { command => 'create_job', %$payload } );"""
if old_cjh not in tools:
    sys.exit("FAIL: create_job handler not found")
tools = tools.replace(old_cjh, new_cjh, 1)
changes.append("Tools create_job handler")

old_cc = """               loops => { type => 'integer' },
            },
            required => ['name'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'create_cluster', %$args } );
         },
      },"""
new_cc = (
    "               loops => { type => 'integer' },\n"
    + JSON_PROP
    + """            },
            required => ['name'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            my $payload = {%$args};
            _normalize_json_arg($payload);
            $c->app->request( $c->stash('user'),
               { command => 'create_cluster', %$payload } );
         },
      },"""
)
if old_cc not in tools:
    sys.exit("FAIL: create_cluster block not found")
tools = tools.replace(old_cc, new_cc, 1)
changes.append("Tools create_cluster json")

old_uj = """               delay               => { type => 'integer' },
               max_runtime_seconds => {
                  type        => 'integer',
                  description =>
'Exceeding max_runtime_seconds starts the configured handler cluster; it does not automatically kill the job. Kill, notify, or recover as you define in the handler'
               },
               max_runtime_cluster_id => { type => 'integer' },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            my $payload = {%$args};
            if ( $payload->{script} && !$payload->{script_b64} ) {
               $payload->{script_b64} =
                 MIME::Base64::encode_base64( $payload->{script}, '' );
               delete $payload->{script};
            }
            $c->app->request( $c->stash('user'),
               { command => 'update_job_config', %$payload } );
         },
      },"""
new_uj = (
    "               delay               => { type => 'integer' },\n"
    + JSON_PROP
    + """               max_runtime_seconds => {
                  type        => 'integer',
                  description =>
'Exceeding max_runtime_seconds starts the configured handler cluster; it does not automatically kill the job. Kill, notify, or recover as you define in the handler'
               },
               max_runtime_cluster_id => { type => 'integer' },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            my $payload = {%$args};
            if ( $payload->{script} && !$payload->{script_b64} ) {
               $payload->{script_b64} =
                 MIME::Base64::encode_base64( $payload->{script}, '' );
               delete $payload->{script};
            }
            _normalize_json_arg($payload);
            $c->app->request( $c->stash('user'),
               { command => 'update_job_config', %$payload } );
         },
      },"""
)
if old_uj not in tools:
    sys.exit("FAIL: update_job block not found")
tools = tools.replace(old_uj, new_uj, 1)
changes.append("Tools update_job json")

old_uc = """               on_fail_id    => { type => 'integer' },
               on_overdue_id => { type => 'integer' },
               loops         => { type => 'integer' },
            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            $c->app->request( $c->stash('user'),
               { command => 'update_cluster', %$args } );
         },
      },"""
new_uc = (
    "               on_fail_id    => { type => 'integer' },\n"
    "               on_overdue_id => { type => 'integer' },\n"
    "               loops         => { type => 'integer' },\n"
    + JSON_PROP
    + """            },
            required => ['id'],
         },
         handler => sub {
            my ( $c, $args ) = @_;
            my $payload = {%$args};
            _normalize_json_arg($payload);
            $c->app->request( $c->stash('user'),
               { command => 'update_cluster', %$payload } );
         },
      },"""
)
if old_uc not in tools:
    sys.exit("FAIL: update_cluster block not found")
tools = tools.replace(old_uc, new_uc, 1)
changes.append("Tools update_cluster json")

ordo_path.write_text(ordo)
tools_path.write_text(tools)

print("CHANGES:")
for c in changes:
    print(" -", c)
print(f"ordo.pm: {orig_ordo_len} -> {len(ordo)}")
print(f"Tools.pm: {orig_tools_len} -> {len(tools)}")

r1 = subprocess.run(["perl", "-c", str(ordo_path)], capture_output=True, text=True)
r2 = subprocess.run(["perl", "-c", str(tools_path)], capture_output=True, text=True)
print("perl -c ordo.pm:", (r1.stderr or r1.stdout).strip(), "rc=", r1.returncode)
print("perl -c Tools.pm:", (r2.stderr or r2.stdout).strip(), "rc=", r2.returncode)
if r1.returncode or r2.returncode:
    sys.exit("SYNTAX FAIL")
print("PATCH_OK")
