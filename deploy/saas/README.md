# SaaS Docker Compose

Container user is **uid/gid 1000** (`ordo`). Host bind mounts under this directory (`config`, `db`, `data`, `ssh`) must be owned by that user, or the stack will fail:

- Entrypoint crashes with `chmod: ... Operation not permitted` when `./ssh` is mounted but not owned by 1000 (older images). Current entrypoint warns and continues, but SSH key gen still needs a writable mount.
- Minion/Ordo hit `DBD::SQLite ... attempt to write a readonly database` when `./db` (including `sqlite:minion.db`) isn’t writable by 1000 — magic-link / email enqueue can look like a UI “network error”.

## Host setup

```bash
mkdir -p config db data ssh
chown -R 1000:1000 config db data ssh
```

If the host `ordo` account isn’t uid 1000, either remap it or keep using numeric `chown 1000:1000` on these dirs.

## Optional home mount

Compose mounts `./ssh:/home/ordo/.ssh` with `HOME=/home/ordo`. If you see `mkdir: cannot create directory '/home/ordo'`, also bind the home parent:

```yaml
volumes:
  - ./home:/home/ordo
  - ./ssh:/home/ordo/.ssh
```

and `chown -R 1000:1000 home ssh`.
