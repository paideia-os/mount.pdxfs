# mount.pdxfs — status

**Wave:** R90-XREPO (post-R53 satellite-cascade + libpdx-volume v1.1)
**Current milestone:** M6 (libpdx-volume v1.1 API adoption) — **landed**;
PFS-10 end-to-end `sys_mount` ABI adoption (paideia-os#2577) —
**landed** at v1.1.5
**Version:** 1.1.5 (PFS-10 / paideia-os#2577: adopt frozen path-based
`sys_mount` ABI + real `PMT_OP_APPEND_ROW` end-to-end — closes the
three "KERNEL GAP #1/#2/#3" bullets `src/mount_op.pdx` carried since
M2-002)
**Version history:** 1.1.4 (PFS-07 / paideia-os#2574:
`snapshot_wire_list` 3-arg `snap_chain_walk` adoption + user-space
`BcReadStub::lpv_bc_read`), 1.1.3 (ENH-030: libpdx-argv adoption —
replaces handwritten scanner, #25)

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
      via `KIND_PDXFS_MOUNT_TABLE`: landed as a stub-shaped first draft
      against the ABI understood at that landing. **KERNEL ABI frozen at
      paideia-os commit `c49a4bff` per
      [`design/pdxfs/sys-mount-abi.md`](https://github.com/paideia-os/paideia-os/blob/main/design/pdxfs/sys-mount-abi.md)
      (PFS-01, 2026-10-11).**  The three "KERNEL GAP" bullets this
      landing originally cited are RETRACTED — direct source reads
      performed under PFS-01 confirm:
      - `dispatch_mount` (`src/kernel/core/syscall/dispatch.pdx`
        L2452-L2461) is a real, wired shim as of R53.M2 that register-
        shuffles and tail-calls `sys_mount_shim`.  It is NOT an
        `-ENOSYS` stub.
      - The dispatch comment at L2400-L2422 describing a cap-slot ABI
        is explicitly retracted on-site (L2429-L2431 says the comment
        "described a design that never landed; the shim's actual
        signature is what ships").  The sole live ABI is the dev-path-
        string shape of `sys_mount_body`.
      - `KIND_PDXFS_MOUNT_TABLE`'s dispatch (`kind_pdxfs_mount_table.pdx`
        L755-L822) wires `PMT_OP_QUERY_SLOT_COUNT` (3) and
        `PMT_OP_REMOVE_ROW` (4); `PMT_OP_APPEND_ROW` (2) remains
        reserved-but-unwired — PFS-02 lands the `_init_caps` seed
        convention and this repo's PFS-10 wires the real
        `mount_op_invoke` body against the frozen ABI.
      **PFS-10 unblocks real end-to-end mount** (rewrites
      `src/mount_op.pdx` against the frozen dev-path-string ABI;
      derives `dev_path`/`mount_point` strings from the `<volume-cap>`
      positional + `<mount-point>` arg).  **PFS-11 closes the
      KIND_BLOCK_DEVICE resolver gap** flagged below (`dev_cap = 0`
      placeholder in `mint_wire.pdx`; wires
      `VOL_OP_QUERY_DEVICE_SLOT` for real).  **PFS-12 wires
      `--passphrase-fd` to the frozen mount hop** (consumes PFS-05's
      `pdxb_block_encrypt`/`decrypt` real bodies).  The current
      `src/mount_op.pdx` text describing an aspirational cap-slot ABI
      stays in place until PFS-10's rewrite replaces it.
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

**UPDATED 2026-10-11 (PFS-01):** the "KERNEL GAP" posture this
paragraph documented is retracted — `dispatch_mount` is wired and
`sys_mount_body` is complete.  Today's `mount_op_invoke` still
issues the aspirational cap-slot ABI, so every non-dry-run invocation
still misses the real sys_mount shape and reports
`result_code: KERNEL_ERROR` for a different reason (shape mismatch,
not `-ENOSYS`).  PFS-10 lands the rewrite that produces the real
end-to-end mount; `--dry-run` continues to work exactly as M1 left it.

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
      caller-save-zeroing hardening) to feed it. **PFS-01 retraction
      (2026-10-11):** `dispatch_mount` is wired (not an `-ENOSYS` stub);
      `MR_RESULT_ENOSYS` (14) is NOT today's observed outcome.
      Today's non-dry-run outcome is `MR_RESULT_KERNEL_ERROR` classified
      from the ABI-mismatch sentinel sys_mount returns to the
      aspirational cap-slot call shape `mount_op_invoke` still issues;
      PFS-10 rewrites the call site against the frozen path-based ABI
      (per `design/pdxfs/sys-mount-abi.md` §2) and the six `SYS_MOUNT_*`
      sentinel arms become naturally reachable.

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
      well-formed real-mount attempt (originally `ENOSYS` — per PFS-01
      retraction, today's actual outcome is `KERNEL_ERROR` from the
      ABI shape mismatch; PFS-10 updates this test to the frozen ABI
      and expects `MOUNT_OP_OK` on a legal invocation).
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

### M6 — libpdx-volume v1.1 API adoption — **landed**

- [x] **M6-001 (#21)** — v1.1 cleanup adoption (`lpv_strerror` +
      `pdxb_sb_get_*` accessors + banded `LPV_E_*` public consts):
      landed. `src/lpv_errors_wire.pdx` (new) wraps `lpv_strerror` in
      a bounded 48-byte scratch + fd-2 diagnostic write; the six
      superblock accessors are consumed directly by the M6 wire
      modules (no per-consumer shim). The library's own v1.1.0
      `lpv_strerror` body is a scaffold returning 0 for every input
      today — this wrapper skips the diagnostic write in that case
      (no wasted syscall), matching the "unavailable" contract; once
      the upstream dispatch chain is populated, this wrapper's
      behaviour changes automatically. Parents: `libpdx-volume`
      #18/#19/#20.
- [x] **M6-002 (#22)** — LV.M2-003 elevate-cap wire-through:
      landed at 1.1.0 (module `src/mint_wire.pdx`) but ORPHANED at
      that landing — `mint_wire_invoke` had zero call sites in
      `src/main.pdx`, and the system-tier path still called the
      M3-era `mount_elev_require_system` stub (fixed exit 4,
      `MR_RESULT_ELEVATION_STUB`) instead. **v1.1.1 (2026-09-02)**
      completes the wiring: `src/main.pdx`'s Phase 3 SYSTEM_PATH /
      CROSS_USER branch now calls `mint_wire_invoke(dev_cap=0,
      mpc_class, &mount_narrowed_slot)`, dispatching MW_OK → jump
      to `mount_main_mount_op` with the minted narrowed slot in
      place (bypassing `volume_cap_resolve`), MW_ERR_NO_ELEVATE →
      `mount_main_m22_no_elevate` (`MR_RESULT_NO_ELEVATE = 16`,
      exit 3), MW_ERR_LIBPDX_VK → `mount_main_m22_mint_failed`
      (NEW `MR_RESULT_MINT_FAILED = 22`, exit 3). Today's landing:
      the refuse-gate inside `mint_wire_invoke` fires on every
      system-tier call (no `KIND_ELEVATE_CHANNEL` cap provisioned),
      so `NO_ELEVATE` is the only value the pipeline actually
      reaches; `MR_RESULT_ELEVATION_STUB` (4) is no longer emitted
      but the taxonomy code + label are retained for wire-format
      compatibility. `dev_cap = 0` is a documented GAP: no
      `KIND_BLOCK_DEVICE` resolver exists in this repo (or
      upstream) that maps a `<volume-cap>` URI to the backing
      dev_cap; safe today because the refuse-gate fires BEFORE
      `vol_kind_mint_elevate` dereferences dev_cap. The M3-era
      `mount_elev_require_system` remains defined in
      `src/elevate.pdx` for its `M4-002` test driver's sake
      (production call site REMOVED). Parent: `libpdx-volume` #23.
- [x] **M6-003 (#23)** — LV.M3 snapshots (`--snapshot=<slot>` RO
      mount + `--snapshot-list` enumeration): landed. New
      `src/snapshot_wire.pdx` + argv extensions
      (`PA_FLAG_SNAPSHOT_SET/LIST`, `PA_OFF_SNAPSHOT_SLOT` at
      offset +24) + `main.pdx` M6 dispatch (`mount_main_m6_snap_
      list`/`_snap_mount` labels).
      `--snapshot=` narrows to `R_VSNAP_READ` via `vol_snapshot_
      narrow` then would issue a snap-mount kernel op — KERNEL
      GAP #A (no such syscall exists), so every legal call refuses
      `MR_RESULT_SNAPSHOT_NOT_IMPL = 17` after passing narrow.
      `--snapshot-list` is a pure passthrough to `snap_chain_walk`
      (itself a documented stub upstream — GAP #B in `libpdx-
      volume`), likewise refusing `SNAPSHOT_NOT_IMPL`. FROZEN gate
      (`snapshot_wire_check_frozen`) wired but unreachable until
      GAP #B closes upstream. Parents: `libpdx-volume` #25/#26.
- [x] **M6-004 (#24 A)** — LV.M5 `--passphrase-fd=<n>` argv +
      KEK-derive + DEK-unwrap composition: landed as a wire module
      + argv-parser plumbing; call site deferred. New
      `src/passphrase_wire.pdx` (real bodies over `pdxb_kek_derive`
      + `pdxb_dek_unwrap`, with a defensive byte-zero wipe helper
      for the KEK/DEK/passphrase scratch). Argv parses
      `--passphrase-fd=<n>` into `ParsedArgv.passphrase_fd` (offset
      +32, i64, -1 sentinel unset). Mount-time hook that calls the
      wire is a Phase-5 addition deferred behind GAP #P2 (no
      `KIND_DEK` cap kernel-side) and the M2 shape-mismatch bug (NOT
      a dispatch_mount gap — see PFS-01 retraction above; the real
      blocker is `src/mount_op.pdx`'s aspirational cap-slot call
      shape, closed by PFS-10). The dispatched path today silently
      ignores `--passphrase-fd` at the mount hop; **PFS-12** wires it
      once PFS-10 lands. Parents: `libpdx-volume` #29/#30.
- [x] **M6-005 (#24 B)** — LV.M4 quota enforcement wrapper:
      landed. New `src/quota_wire.pdx`. `quota_wire_sb_has_quota`
      + `quota_wire_install` (documented no-op stub per GAP #Q1:
      no `KIND_PDXFS_QUOTA` cap kernel-side) + `quota_wire_check_
      or_refuse` (REAL body over `pdxb_quota_check` with the
      tool's `EDQUOT`-style refusal contract; call sites appear
      once mount.pdxfs — or a companion FS-write daemon — grows a
      real write path, per GAP #Q2). Parent: `libpdx-volume` #28.
- [x] **M6-006 (#24 C)** — LV.M6 dep-graph refusal (`--all`
      surface): landed. New `src/dep_graph_wire.pdx` +
      `main.pdx::mount_main_m6_all` handler. `dep_graph_wire_sort`
      is a thin adapter over `mount_table_sort_by_deps` (stub
      today, returns `LPV_ORDER_ERR_NOT_IMPL = 0x0A04` for every
      non-empty input). `--all` invocation emits
      `MR_RESULT_DEP_ORDER_NOT_IMPL = 21` + exit 3, refusing
      cleanly BEFORE any real mount happens. Parent:
      `libpdx-volume` #31.

`src/main.pdx`'s `_start` grew an M6 mode-dispatch block right after
argv parse, checking `PA_FLAG_ALL` → `PA_FLAG_SNAPSHOT_LIST` →
`PA_FLAG_SNAPSHOT_SET` in fixed precedence order and jumping to the
matching M6 handler. `--passphrase-fd` deliberately has no M6 branch;
it falls through to the legacy pipeline (its mount-time consumption
is a future Phase-5 wiring, gated on GAP #P2 and the M2 call-shape
bug fixed by PFS-10; the earlier citation of "dispatch_mount unwired"
is retracted per PFS-01).

`src/mount_record.pdx` grew six new `MR_RESULT_*` codes (16..21) at
v1.1.0 and their matching label literals, wired into `mount_record_
emit_result`'s cmp/je dispatch chain. **v1.1.1** adds a seventh:
`MR_RESULT_MINT_FAILED = 22` (`MINT_FAILED` literal), reachable only
via `mint_wire_invoke`'s MW_ERR_LIBPDX_VK arm (unreachable at this
landing since the refuse-gate consumes every system-tier call).

`src/argv.pdx`'s `ParsedArgv` widened from 24 bytes to 48 bytes: the
M1 offsets are byte-for-byte unchanged; every M6 addition is APPENDED
at offset +24/+32/+40. Positional-requirement gates relax per the
M6 surface (`--all` requires neither positional; `--snapshot-list`
requires only `<volume-cap>`; `--snapshot=` requires only
`<mount-point>`).

## Next milestone

Addressed via the **PFS AISSUE wave** (paideia-os PFS-01..PFS-17, filed
2026-10-11).  **KERNEL ABI frozen at paideia-os commit `c49a4bff` per
`design/pdxfs/sys-mount-abi.md` (PFS-01)** — the aspirational cap-slot
ABI the asks below were waiting on is retracted, and the live kernel
has the dev-path-string shape that `sys_mount_body` already shipped.
Ticket map for this repo's remaining work:

1. **PFS-10 — ABI reconciliation.**  Rewrites `src/mount_op.pdx` to
   the frozen path-based `sys_mount_shim` ABI (per
   `design/pdxfs/sys-mount-abi.md` §2); derives `dev_path`/`mount_point`
   strings from the `<volume-cap>` + `<mount-point>` positional args;
   closes the ABI-mismatch bug this repo's M2 landing documented.
2. **PFS-11 — KIND_BLOCK_DEVICE resolver.**  Maps `<volume-cap>` to the
   backing dev_cap via `VOL_OP_QUERY_DEVICE_SLOT`; closes the
   `dev_cap = 0` placeholder in `src/mint_wire.pdx`; real elevate
   wire-through for `/system` paths (consumes PFS-02's
   `_init_caps` seed + PFS-09's `vol_kind_mint` real body).
3. **PFS-12 — `--passphrase-fd` call-site wiring.**  KEK derive → DEK
   unwrap → mount hop; closes the Phase-5 deferral M6-004 flagged.
   (Depends on PFS-05's `pdxb_block_encrypt` real body + PFS-10's
   mount hop.)
4. **PFS-02 (parent-repo scope) — `_init_caps` seed convention.**
   Provisions standalone CLI tools (mount.pdxfs / umount.pdxfs) with
   `KIND_PDXFS_MOUNT_TABLE` row-append/remove cap +
   `KIND_ELEVATE_CHANNEL` broker-endpoint cap at exec time.  Closes
   the "no broker-endpoint cap provisioned" blocker both M3-001 and
   M6-002 cite. **Convention landed as design doc at paideia-os
   `design/pdxfs/init-caps-seed-convention.md` (PFS-02, 2026-10-11)**
   — slot 4 = `KIND_PDXFS_MOUNT_TABLE` (0x1A5) with
   `R_PMT_INVOKE|R_PMT_WRITE` (0x00A); slot 5 =
   `KIND_IPC_ENDPOINT` (0x005) to `ELEVATE_BROKER_ENDPOINT_ID = 16`
   with `R_IPC_INVOKE|R_IPC_WRITE` (0x00A).  Cap seed from PID 1
   `_init_caps` per `design/pdxfs/init-caps-seed-convention.md` is
   the authority root; kernel enablement (grow `KIND_SEEDABLE_TABLE`
   by two entries, singleton-row mint path, broker-endpoint
   seed-time gate) is stubbed in §6 of the doc and tracked as the
   PFS-02 kernel-side follow-up.  `src/mint_wire.pdx`'s
   `mount_mw_elevate_slot = 0` placeholder resolves to literal slot
   5 once the follow-up lands.

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
