# mount.pdxfs

paideia-os PdxFS volume mount tool — attaches a `KIND_VOLUME` cap to a
VFS mount point (`sys_mount`) and appends a row to the kernel's
`KIND_PDXFS_MOUNT_TABLE`, with audit-first `PdxFsMountRecord@0.1`
journaling and elevate-gated writes to protected trees.

## Purpose

`mount.pdxfs` is the second of three actions that bring a blank disk
(or image file) online for PdxFS v1: format (`mkfs.pdxfs`), then
**mount** (this tool), with `umount.pdxfs` as the reversal. It is
invoked as:

```
mount.pdxfs [--ro] [--noexec] [--verbose] [--dry-run] <volume-cap> <mount-point>
```

`<volume-cap>` is a `KIND_VOLUME` cap URI (e.g. `cap:volume:0x0002`)
looked up in the invoker's cap environment. `<mount-point>` is a VFS
path where the volume should attach. See
[`design/architecture.md`](design/architecture.md) for the full
argv/mount-point-class write-up and
`design/tooling/volume-tooling-ux.md` §4 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo for the
upstream CLI spec this tool implements.

## Status

**v1.0.0 — M1..M5 landed** (source-form release scaffold; the actual
dual-sign + mirror-push run is deferred, see
[`release/RELEASE-1.0.0.md`](release/RELEASE-1.0.0.md)). See
[`STATUS.md`](STATUS.md) for the per-issue checklist and
`design/tooling/volume-tooling-ux.md` §9.2 in paideia-os for the full
M1..M5 milestone breakdown (16 issues).

Try it (once built and linked into a runnable image):

```
mount.pdxfs --ro --dry-run cap:volume:0x0002 /mnt/data
```

prints (the leading `#` line is the M3 semantic-pipe deferral header —
see "Depends on" below for why):

```
# semantic-pipe emit deferred (svc.schema-registry not yet live, paideia-os#2000) -- PdxFsMountRecord@0.1 line-based fallback below
PdxFsMountRecord@0.1 { volume: cap:volume:0x0002, mount_point: /mnt/data, flags: 9, result_code: DRY_RUN }
```

and exits 0 without mounting anything (`flags: 9` = `PA_FLAG_RO (0x1)
| PA_FLAG_DRY_RUN (0x8)`). An invocation without `--dry-run` against a
`/system/**`, `/boot/**`, or `/dev/**` mount point prints `result_code:
ELEVATION_STUB` and exits 4 (no `libpdx-elevate` broker cap provisioned
yet — see "Depends on" below); against any other mount point it runs
the real `sys_mount` pipeline and, since the kernel's `dispatch_mount`
is still an unconditional `-ENOSYS` stub, prints `result_code: ENOSYS`
and exits 3 — every terminal outcome is now audit-wrapped (`libpdx-
audit`, one shared `audit_id` per invocation) and mapped to one of the
fifteen `MR_RESULT_*` codes `src/mount_record.pdx` defines.

## Depends on

- **`libpdx-volume`** (`paideia-os/libpdx-volume`, v1.0.0) — supplies
  `vol_kind_narrow` (mount-scoped `KIND_VOLUME` sub-cap). Called by bare
  symbol per that repo's own README ("declared but not yet linked" for
  this consumer); no actual cross-repo link step exists in this repo's
  `tools/build.sh` yet.
- **`libpdx-audit`** (`paideia-satellites/libpdx-audit`, @0.2) — real
  `AuditClient::audit_begin` / `audit_commit` calls (`src/audit_
  wire.pdx`), one shared `audit_id` per invocation. The kernel-side
  audit-journal broker dispatch is confirmed stubbed, so every call may
  no-op at the daemon today.
- **`libpdx-elevate`** (`paideia-satellites/libpdx-elevate`,
  v1.1.0-in-progress) — real, mature library, but NOT dispatched: `src/
  elevate.pdx`'s `mount_elev_require_system` is a documented fail-closed
  stub pending a real `KIND_ELEVATE_CHANNEL` broker-endpoint cap this
  repo does not hold.
- **`libpdx-semantic-pipe`** (v1.0.0, real + released) — NOT linked
  (`src/pipe_wire.pdx`): `Registry::bind_by_name` is confirmed inert
  (`paideia-os#2000`). Every `PdxFsMountRecord@0.1` this tool emits is a
  documented line-based fallback rendering instead.
- **`R53-PREP-001`** (paideia-os main repo) — `KIND_PDXFS_MOUNT_TABLE`
  kernel substrate. Landed (`src/kernel/core/cap/kind_pdxfs_mount_table.pdx`).
- **paideia-as ≥ 0.21.0** (build toolchain).

## Milestones

| Milestone | Scope | Status |
|---|---|---|
| M1 | Scaffold, caps.decl, argv surface, first runnable `--dry-run` | **Landed** |
| M2 | Real volume-cap resolution + narrow, `sys_mount`, mount-table row append | **Landed** |
| M3 | Elevate + audit-first INTENT/RESULT + semantic-pipe + failure taxonomy | **Landed** |
| M4 | Tests + smoke | **Landed** |
| M5 | Signed release | **Landed** (source-form scaffold) |

## License

MIT — see [`LICENSE`](LICENSE).
