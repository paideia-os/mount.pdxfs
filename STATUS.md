# mount.pdxfs — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** M1 (design + skeleton) — **landed**
**Version:** unreleased (pre-1.0.0)

See `design/tooling/volume-tooling-ux.md` §9.2 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo for the
full 15-issue breakdown this checklist mirrors.

## Milestone checklist

### M1 — Design + skeleton

- [x] **M1-001** — scaffold + `caps.decl` (`KIND_USER` + `KIND_VOLUME` +
      `KIND_PDXFS_MOUNT_TABLE` + `KIND_ELEVATE_CHANNEL`): landed. Four
      source files (`src/main.pdx`, `src/argv.pdx`, `src/mount_record.pdx`,
      `src/elevate.pdx`), `caps.decl`, `design/architecture.md`. Unlike
      mkfs.pdxfs's own `caps.decl` (which flags a `KIND_BLOCK_DEVICE`
      naming gap) all four kinds this tool consumes are real,
      already-landed kernel ordinals with matching names — see
      `caps.decl`'s own header for the one real gap found instead: the
      landed `KIND_VOLUME` op catalog has no `VOL_OP_MOUNT` ordinal, so
      §4.2's "mount+query" phrase is a rights-shape description, not a
      cap-invoke op name. Confirm with osarch before M2-001.
- [x] **M1-002** — argv surface (`--ro`, `--noexec`, `--verbose`,
      `--dry-run`, `<volume-cap>`, `<mount-point>`): landed.
      `libpdx-argv` still does not exist anywhere in the paideia-os
      monorepo or under `paideia-satellites/` as of this landing
      (confirmed via `grep`, same finding mkfs.pdxfs.M1-002 made) —
      `src/argv.pdx` implements a minimal long-flag parser inline,
      matching mkfs.pdxfs's own fallback shape (`argv_parse(argc, argv,
      out_ptr) -> status`). Two positionals (not mkfs.pdxfs's one):
      first non-flag token fills `<volume-cap>`, second fills
      `<mount-point>`; a third+ is silently ignored at M1. See
      `design/architecture.md` §3 for the deferral note.
- [x] **M1-003** — first runnable: `mount.pdxfs --dry-run <volume-cap>
      <mount-point>` prints the `PdxFsMountRecord@0.1` line with
      `result_code: DRY_RUN`: landed. `src/main.pdx`'s `_start` wires
      `Argv::argv_parse` → `MountRecord::mount_record_emit_dry_run`.
      Unlike mkfs.pdxfs, the dry-run happy path has no target-taxonomy
      gate — mount.pdxfs takes exactly two well-formed positionals with
      no file-vs-cap-URI branch to classify at M1, so `--dry-run` always
      succeeds once argv parses. Any invocation without `--dry-run`
      falls through to a `not yet implemented` diagnostic + exit 1 (the
      real write path is M2/M3). The printed record is a REAL rendering
      of the caller's actual volume-cap/mount-point/flags arguments —
      `result_code: DRY_RUN` is the one hardcoded literal — see
      `src/mount_record.pdx`'s module header for exactly which of the
      full 10-field `PdxFsMountRecord@0.1` schema this M1 slice covers
      (four fields: `volume`, `mount_point`, `flags`, `result_code`) and
      which are deferred to M3-003 along with the semantic-pipe binary
      framing itself.

### M2 — Core implementation (pending)

- [ ] **M2-001** — volume-cap resolution + narrow via
      `libpdx-volume.vol_kind_narrow`.
- [ ] **M2-002** — real `sys_mount` invocation + mount-table row append
      via `KIND_PDXFS_MOUNT_TABLE`.
- [ ] **M2-003** — user-subtree mount path (no elevate; `/home/$user` +
      `/mnt` + `/tmp`).

### M3 — Elevate + audit-first + semantic-pipe (pending)

- [ ] **M3-001** — mount-point-class table (§4.2) +
      `libpdx-elevate` integration for `/system`, `/boot`, `/dev`,
      cross-user. Replaces `src/elevate.pdx`'s M1 stub (`elevate_needed`
      always returns "not required").
- [ ] **M3-002** — INTENT record before `sys_mount` + RESULT record
      after (shared `audit_id`).
- [ ] **M3-003** — semantic-pipe: `PdxFsMountRecord@0.1` schema bind +
      emit (full 10-field record, replacing M1's 4-field text line).
- [ ] **M3-004** — failure-taxonomy encoding (§4.4): map every kernel
      errno + policy-refusal to a distinct `result_code`.

### M4 — Tests + smoke (pending)

- [ ] **M4-001** — happy-path smoke: `/mnt` user-owned mount, no
      elevate.
- [ ] **M4-002** — elevate-required smoke: `/system` mount with
      auto-approve policy + human-approve fallback.
- [ ] **M4-003** — failure-matrix smoke: sig-invalid, journal-corrupt,
      already-mounted, mount-point-exists, no-permission.
- [ ] **M4-004** — elevate-timeout path: request times out (30s
      default) → exit 4 with clean audit trail.

### M5 — Signed release (pending)

- [ ] **M5-001** — dual-signed `manifest.pdxsig` + CHANGELOG-1.0 +
      `.pdxdoc` for `doc mount.pdxfs`.
- [ ] **M5-002** — mirror push to `pkgs.paideia-os`.

## Next milestone

M2 opens once `mount.pdxfs.M1` closes and `libpdx-volume`'s
`vol_kind_narrow` (real body, landed as of `libpdx-volume.M2` per that
repo's own `caps.decl`) is confirmed linkable — M2-001's volume-cap
narrow calls that function directly. The `KIND_VOLUME` op-catalog gap
flagged in `caps.decl` (no `VOL_OP_MOUNT` ordinal) should be confirmed
with osarch before M2-001 opens, mirroring the `KIND_BLOCK_DEVICE`
confirmation mkfs.pdxfs's own `STATUS.md` asks for before its M3-001.

## Upstream design

`design/tooling/volume-tooling-ux.md` §4 + §9.2 and
`design/tooling/volume-lifecycle-mechanism.md` in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.
