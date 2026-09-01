# mount.pdxfs — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** M5 (signed release) — **landed** (source-form scaffold)
**Version:** 1.0.0

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

### M3 — Elevate + audit-first + semantic-pipe — **landed**

- [x] **M3-001** — mount-point-class table (§4.2) +
      `libpdx-elevate` integration for `/system`, `/boot`, `/dev`,
      cross-user: landed. `src/elevate.pdx`'s M2-003 `elevate_needed`
      is kept, unmodified, no remaining caller; a new `Elevate::mount_
      point_class` exposes the same three-prefix-group body under this
      issue's own four-value vocabulary (`MPC_USER_SUBTREE`, `MPC_
      SYSTEM_PATH`, `MPC_CROSS_USER` — defined, never actually produced,
      no `KIND_USER` identity lookup exists to tell an own-subtree
      `/home/` apart from another user's — `MPC_INVALID`). A full read
      of `libpdx-elevate`'s real, mature source confirms the identical
      "no broker-endpoint cap provisioned" gap `mkfs.pdxfs`'s own M3-005
      (#12) already found over the SAME library: `Elevate::mount_elev_
      require_system` is therefore a documented fail-closed stub —
      `MOUNT_ELEV_DENY` unconditionally. `MOUNT_ELEV_GRANT` and its
      dispatch arm are real, wired code, unreachable at this landing.
- [x] **M3-002** — INTENT record before `sys_mount` + RESULT record
      after (shared `audit_id`): landed. New `src/audit_wire.pdx`
      (`AuditWire::mount_audit_begin` / `mount_audit_commit`), mirroring
      mkfs.pdxfs's own `audit_wire.pdx` (M3-004, #11) shape exactly.
      `audit_begin` is called once, before any dispatch, in `main.pdx`;
      every terminal branch's own `audit_commit` call shares that ONE
      `audit_id` — libpdx-audit's real correlation mechanism for the
      INTENT/RESULT pairing this issue asks for (there is no separate
      `parent_audit_id` parameter on the real `audit_commit`; that name
      belongs to a different entry point, `audit_set_parent`, for
      cross-process parent/child audit trees).
- [x] **M3-003** — semantic-pipe: `PdxFsMountRecord@0.1` schema bind +
      emit: landed as a documented DEFERRAL, matching mkfs.pdxfs's own
      M3-003 (#10) finding over the identical `paideia-os#2000`
      schema-registry gap (`Registry::bind_by_name` confirmed inert).
      New `src/pipe_wire.pdx` — one wrapper (`PipeWire::mount_pipe_
      emit_result`, not two like mkfs.pdxfs's own two-wrapper shape,
      since this repo's M2 landing had already unified dry-run into the
      same emitter as every other result code), prepending one
      documented deferral header line before delegating to `MountRecord
      ::mount_record_emit_result` unchanged.
- [x] **M3-004** — failure-taxonomy encoding (§4.4): landed. `src/
      mount_record.pdx` gains eleven new `MR_RESULT_*` codes (4..14): four
      policy refusals this repo's own pipeline detects (`ELEVATION_
      STUB`, `INVALID_MOUNT_POINT`, `BAD_VOLUME_CAP`, `NARROW_FAILED` —
      all previously folded into the single M2 `KERNEL_ERROR` catch-all)
      plus the seven real kernel-errno sentinels `sys_mount.pdx` can
      return (six `SYS_MOUNT_*` constants at `0xFFFFED60..65`, plus raw
      `-ENOSYS`), classified via a new pure-leaf `MountRecord::mount_
      record_classify_mount_errno`. `src/mount_op.pdx`'s `mount_op_
      invoke` grows a 5th out-param (`out_raw_errno_ptr`, staged into a
      newly-pushed callee-save `r15` to survive the real-path syscall's
      caller-save-zeroing hardening) to feed it. Given `dispatch_mount`
      is still an unconditional `-ENOSYS` stub (`src/mount_op.pdx`'s own
      KERNEL GAP #1, unchanged since M2), `MR_RESULT_ENOSYS` (14) is the
      one real, observed outcome today for any non-dry-run invocation;
      the other six `SYS_MOUNT_*` arms are real, wired, unreachable
      until `dispatch_mount` is wired for real.

`src/main.pdx`'s `_start` is rewritten to wire all six modules together:
`r13` (dead `argv` after `argv_parse`) is reused to hold the shared
`audit_id` for the rest of the function — the identical register-reuse
trick mkfs.pdxfs's own M3 `main.pdx` applies to its `r12`. The M2-era
single shared `mount_main_kernel_error` label is gone, replaced by one
small, distinct emit-commit-exit block per failure cause.

### M4 — Tests + smoke — **landed**

- [x] **M4-001** — happy-path smoke: `/mnt` user-owned mount, no
      elevate: landed. `tests/test_happy_mnt.pdx` drives `Argv::argv_
      parse` → `Elevate::mount_point_class` → `VolumeCap::volume_cap_
      resolve` → `MountOp::mount_op_invoke` for a real (non-`--dry-run`)
      `cap:volume:0x42` / `/mnt/user` invocation, accepting either
      `MOUNT_OP_OK` or a `MOUNT_OP_ERR_KERNEL` that classifies to `MR_
      RESULT_ENOSYS` — a strictly more precise assertion than a bare
      "or KERNEL_ERROR", since M3-004 gave ENOSYS its own code.
- [x] **M4-002** — elevate-required smoke: `/system` mount: landed.
      `tests/test_elevate_system.pdx` asserts `mount_point_class`
      returns `MPC_SYSTEM_PATH` and `mount_elev_require_system` returns
      `MOUNT_ELEV_DENY` for `/system/foo` — the `result_code: ELEVATION_
      STUB` outcome this landing's fail-closed posture actually
      produces, per this issue's own "or ELEVATION_STUB" allowance.
- [x] **M4-003** — failure-matrix smoke: landed (adapted to this repo's
      own failure surface — sig-invalid / journal-corrupt / already-
      mounted have no `mount.pdxfs`-side analogue at this landing; the
      four cases below are the real, reachable failure modes this
      repo's own M3-004 taxonomy actually distinguishes).
      `tests/test_failure_matrix.pdx` drives four cases against four
      DISTINCT `MR_RESULT_*` codes: a malformed volume-cap hex tail
      (`BAD_VOLUME_CAP`), an unrecognised mount-point prefix (`INVALID_
      MOUNT_POINT`), a `/system/**` path (`ELEVATION_STUB`), and a
      well-formed real-mount attempt against the still-unwired kernel
      (`ENOSYS`).
- [x] **M4-004** — elevate-timeout path: landed as a documented STUB per
      this issue's own instruction. `tests/test_elevate_timeout.pdx`
      always returns a `TET_DEFERRED` sentinel (deliberately distinct
      from the `0` "passed" value) — no code path in this repo ever
      dispatches a real `elevate_client_acquire`/`_request_ex` call (see
      M3-001's fail-closed stub above), so there is no timeout scenario
      to construct yet; `libpdx-elevate`'s own real bounded-poll timeout
      machinery is mature and unaffected.

### M5 — Signed release — **landed** (source-form scaffold)

- [x] **M5-001** — dual-signed `manifest.pdxsig` + CHANGELOG-1.0 +
      `.pdxdoc` for `doc mount.pdxfs`: landed. `CHANGELOG.md` (new,
      `## 1.0.0` entry), `doc/mount.pdxfs.pdxdoc` (new, source form),
      `release/manifest.pdxsig.txt` (new, every hash and signature slot
      a documented placeholder — no live release-line key material in
      this repo, mirroring `libpdx-volume`'s own M5-001 posture exactly),
      `release/RELEASE-1.0.0.md` (new, operator runbook + release note,
      mirroring `libpdx-volume`'s own `RELEASE-1.0.0.md` shape).
- [x] **M5-002** — mirror push to `pkgs.paideia-os`: documented in
      `release/RELEASE-1.0.0.md`'s own Distribution section as a
      NOT-PERFORMED step (the mirror endpoint does not exist as of this
      landing, same status every other satellite repo's own release
      note carries) — no real mirror push happens in this repo.

## Next milestone

None currently scoped past M5. `mount.pdxfs` v1.0.0's real, end-to-end
mount path remains blocked on the three kernel-side gaps `src/mount_op.
pdx` and `src/elevate.pdx` each document in full (`dispatch_mount`'s
unwired stub, the two-incompatible-ABI question, `KIND_PDXFS_MOUNT_
TABLE`'s unwired `APPEND_ROW`, and `libpdx-elevate`'s unprovisioned
broker-endpoint cap) — none of which is this repo's own milestone to
close. Three concrete asks carried forward from M2, unchanged:

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
4. Provision `mount.pdxfs` with a real `KIND_ELEVATE_CHANNEL`
   broker-endpoint cap (the `parent_ep_slot` `libpdx-elevate`'s own
   README says is the caller's responsibility) so `src/elevate.pdx`'s
   `mount_elev_require_system` can grow a real `elevate_client_acquire`
   body — carried forward from M3-001, new at this landing.

The `KIND_VOLUME` op-catalog gap flagged in `caps.decl` (no
`VOL_OP_MOUNT` ordinal) and the missing `cap_check_kind` primitive
(`src/volume_cap.pdx`'s own header) remain open alongside these four.

## Upstream design

`design/tooling/volume-tooling-ux.md` §4 + §9.2 and
`design/tooling/volume-lifecycle-mechanism.md` in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.
