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

**M1 landed** (scaffold + caps.decl, argv surface, first runnable
`--dry-run`). See [`STATUS.md`](STATUS.md) for the per-issue checklist
and `design/tooling/volume-tooling-ux.md` §9.2 in paideia-os for the
full M1..M5 milestone breakdown (15 issues).

Try it (once built and linked into a runnable image):

```
mount.pdxfs --ro --dry-run cap:volume:0x0002 /mnt/data
```

prints:

```
PdxFsMountRecord@0.1 { volume: cap:volume:0x0002, mount_point: /mnt/data, flags: 9, result_code: DRY_RUN }
```

and exits 0 without mounting anything (`flags: 9` = `PA_FLAG_RO (0x1)
| PA_FLAG_DRY_RUN (0x8)`). Any invocation without `--dry-run` currently
prints `mount.pdxfs: not yet implemented` to stderr and exits 1 — the
real write path (volume-cap resolve + narrow, `sys_mount`, mount-table
row append, elevate, signing gates) lands at M2/M3.

## Depends on

- **`libpdx-volume`** (`paideia-os/libpdx-volume`) — M1/M2 landed. Will
  supply `vol_kind_narrow` (mount-scoped `KIND_VOLUME` sub-cap) and
  `mount_table_snapshot` this tool's M2/M3 link against. Not yet linked
  by any M1 code in this repo.
- **`R53-PREP-001`** (paideia-os main repo) — `KIND_PDXFS_MOUNT_TABLE`
  kernel substrate. Landed (`src/kernel/core/cap/kind_pdxfs_mount_table.pdx`).
- **paideia-as ≥ 0.21.0** (build toolchain).

## Milestones

| Milestone | Scope | Status |
|---|---|---|
| M1 | Scaffold, caps.decl, argv surface, first runnable `--dry-run` | **Landed** |
| M2 | Real volume-cap resolution + narrow, `sys_mount`, mount-table row append | Pending |
| M3 | Elevate + audit-first INTENT/RESULT + semantic-pipe | Pending |
| M4 | Tests + smoke | Pending |
| M5 | Signed release | Pending |

## License

MIT — see [`LICENSE`](LICENSE).
