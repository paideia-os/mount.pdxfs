# mount.pdxfs — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** M2 (core implementation) — **landed**
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

### M2 — Core implementation — **landed**

- [x] **M2-001** — volume-cap resolution + narrow via
      `libpdx-volume.vol_kind_narrow`: landed. New `src/volume_cap.pdx`
      (`VolumeCap::volume_cap_parse_slot` decodes a `cap:volume:0xNN`
      URI into a raw slot number via a byte-loop hex parser;
      `VolumeCap::volume_cap_resolve` composes that with
      `vol_kind_narrow`). Two flagged gaps: (1) no `cap_check_kind` (or
      equivalent) kernel primitive exists anywhere in the monorepo to
      independently verify the slot is actually a `KIND_VOLUME` — this
      file trusts the caller-supplied slot and defers entirely to
      whatever `vol_kind_narrow` / `sys_mount` eventually enforce; (2)
      the requested `ops_mask` (`VC_OPS_MOUNT_QUERY = 0x3`) is a
      documented stand-in for "VOL_MOUNT|VOL_QUERY" — bits 0/1 of the
      landed `KIND_VOLUME` op catalog, which still has no real
      `VOL_OP_MOUNT` ordinal (M1's own flag, unchanged). `vol_kind_narrow`
      is called by bare symbol per libpdx-volume's own README
      ("declared but not yet linked" for this consumer) — neither this
      repo's `tools/build.sh` (single-file compiles, no link step) nor
      any other script performs the actual cross-repo link yet.
- [x] **M2-002** — real `sys_mount` invocation + mount-table row append
      via `KIND_PDXFS_MOUNT_TABLE`: landed as a documented STUB, not a
      working call, per this issue's own instruction. New
      `src/mount_op.pdx`. **Three kernel-side gaps found and cited by
      source location** (see that file's own header for the full
      write-up): (1) `sysno 75` (`sys_mount`)'s live dispatch label
      (`dispatch_mount`, `src/kernel/core/syscall/dispatch.pdx` L1975)
      is STILL an unconditional `-ENOSYS` stub that reads no argument
      register, despite `sys_mount_body`/`sys_mount_shim`
      (`sys_mount.pdx`) already having a complete, real, audit-emitting
      implementation — the dispatch-table wiring between the two was
      simply never landed; (2) even once wired, `sys_mount_body`'s real
      signature (`dev_path_ptr, dev_path_len, mount_point_ptr,
      mount_point_len, backend_id`) does not accept a `KIND_VOLUME` cap
      slot at all, contradicting `dispatch.pdx`'s own forward-
      declaration comment (L1951-1962) documenting a cap-slot-based
      ABI for the same sysno — two incompatible target ABIs for one
      syscall number; (3) `KIND_PDXFS_MOUNT_TABLE`'s cap-invoke handler
      (`kind_pdxfs_mount_table.pdx`) refuses every op including the
      reserved `PMT_OP_APPEND_ROW` (2) with `INVOKE_UNSUPPORTED` — no
      row-append op is wired, and no `_init_caps`-style convention
      seeds a standalone CLI tool with a mount-table cap slot in the
      first place. `mount_op_invoke` issues the syscall using the
      aspirational cap-slot ABI (gap #2's shape) and treats any
      implausible return (anything ≥ 65536) as `MOUNT_OP_ERR_KERNEL` —
      today that is EVERY non-dry-run invocation, given gap #1.
      `mount_op_append_row`'s `cap_invoke` result is discarded
      (best-effort, matching `audit_emit`'s own discard convention).
      **Confirm with osarch which of the two ABIs (gap #2) sysno 75
      should actually grow into before wiring `dispatch_mount` for
      real** — this is the concrete evidence for the "confirm before
      M2-001" flag this repo's own M1 landing already raised.
- [x] **M2-003** — user-subtree mount path (no elevate; `/home/$user` +
      `/mnt` + `/tmp`): landed. `src/elevate.pdx`'s M1 stub replaced
      with a real three-bucket classifier
      (`Elevate::elevate_needed`): `/home/`, `/mnt/`, `/tmp/` prefixes
      → `ELEVATE_NOT_REQUIRED` (0); `/system/`, `/boot/`, `/dev/` →
      `ELEVATE_REQUIRED` (1); anything else → `ELEVATE_INVALID` (2).
      Deliberately NARROWER than design/tooling/volume-tooling-ux.md
      §4.2's full five-class table — this milestone's own scope has no
      founder/cross-user distinction (every `/home/**` path is
      never-elevate for now, over-permissive relative to §4.2's
      own-subtree-only exemption; no `ELEVATE_INVALID` bucket exists in
      §4.2 at all, whose unmatched default is founder-only-elevate, not
      a refusal) — both narrowings are flagged in `elevate.pdx`'s own
      header for M3-001 to close once a `KIND_USER` identity lookup
      exists. `main.pdx`'s M2 pipeline treats `ELEVATE_REQUIRED` as a
      hard stop (`result_code: ELEVATION_REQUIRED`, exit 4) and folds
      `ELEVATE_INVALID` into the same `KERNEL_ERROR` bucket M2-002's
      own failures use (exit 3) — no dedicated result_code exists yet
      for "unclassifiable mount point".

`src/mount_record.pdx` gained a new unified emitter,
`MountRecord::mount_record_emit_result`, and four `MR_RESULT_*`
result_code constants (`DRY_RUN`, `OK`, `ELEVATION_REQUIRED`,
`KERNEL_ERROR`) — `main.pdx`'s M2 `_start` calls it on every path
instead of M1's dry-run-only `mount_record_emit_dry_run` (kept,
unmodified, as a still-valid M1 call shape). A shared
`mount_record_print_decimal` leaf was factored out of the old inline
digit-conversion loop so both `flags` and the new `mount_id` field
reuse one implementation.

Given the M2-002 kernel gaps above, `mount.pdxfs`'s real (non-`--dry-
run`) mount path is not reachable end-to-end today: `--dry-run` still
works exactly as M1 left it (result_code: DRY_RUN, exit 0); any
non-dry-run invocation with a valid argv, a never-elevate mount point,
and a well-formed `<volume-cap>` URI reaches `mount_op_invoke`'s real
branch, issues the (currently `-ENOSYS`) syscall, and reports
`result_code: KERNEL_ERROR` with exit 3 — this is the correct,
documented M2 landing behaviour, not a defect in this repo.

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

M3 (elevate + audit-first + semantic-pipe) opens once the M2-002 kernel
gaps above are resolved enough for a real end-to-end mount, OR M3's own
scope (elevate round-trip, INTENT/RESULT audit pair, semantic-pipe
framing, failure-taxonomy encoding) is judged independently landable
against the current `KERNEL_ERROR` stub path — confirm with osarch.
Three concrete asks carried forward from M2:

1. Which ABI sysno 75 (`sys_mount`) should grow into: the cap-slot
   contract `dispatch.pdx`'s own forward-declaration comment documents,
   or `sys_mount_body`'s already-landed dev-path-string signature —
   they are mutually incompatible today (`src/mount_op.pdx`'s header).
2. Wire `dispatch_mount` (dispatch.pdx L1975) to whichever body results
   from (1) — it is currently an unconditional `-ENOSYS` stub.
3. Wire `KIND_PDXFS_MOUNT_TABLE`'s `PMT_OP_APPEND_ROW` (reserved
   ordinal 2) for real, and establish an `_init_caps`-style convention
   for seeding a standalone CLI tool (not just a long-running IPC
   server) with a cap slot for that kind.

The `KIND_VOLUME` op-catalog gap flagged in `caps.decl` (no
`VOL_OP_MOUNT` ordinal) and the missing `cap_check_kind` primitive
(`src/volume_cap.pdx`'s own header) remain open alongside these three.

## Upstream design

`design/tooling/volume-tooling-ux.md` §4 + §9.2 and
`design/tooling/volume-lifecycle-mechanism.md` in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.
