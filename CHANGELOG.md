# mount.pdxfs — CHANGELOG

## 1.0.0 — 2026-08-31 (R53 wave close, M5-001)

**First release.** Manifest scaffolded for a future dual-signed
(Ed25519 + ML-DSA-65) release per
`design/02-development-environment.md` §1140 (paideia-os); the actual
dual-sign + mirror-push run is deferred (see "Known deferred substrate"
below). Ships `.pdxdoc` for `doc mount.pdxfs` and a release manifest
source form targeting `https://pkgs.paideia-os/main/mount.pdxfs/1.0.0/`
per `release/RELEASE-1.0.0.md`.

### Landed

- **M1-001** scaffold + `caps.decl` (`KIND_USER` + `KIND_VOLUME` +
  `KIND_PDXFS_MOUNT_TABLE` + `KIND_ELEVATE_CHANNEL`, all real,
  already-landed kernel ordinals — the one real gap found was the
  `KIND_VOLUME` op catalog's missing `VOL_OP_MOUNT` ordinal, not a
  missing kind).
- **M1-002** argv surface (`--ro`, `--noexec`, `--verbose`, `--dry-run`,
  `<volume-cap>`, `<mount-point>`) — a minimal inline parser, matching
  `mkfs.pdxfs`'s own fallback shape (`libpdx-argv` still does not exist
  anywhere in the org).
- **M1-003** first runnable: `mount.pdxfs --dry-run <volume-cap>
  <mount-point>` prints a four-field `PdxFsMountRecord@0.1` line
  (`volume`, `mount_point`, `flags`, `result_code: DRY_RUN`).
- **M2-001** real volume-cap resolution + narrow
  (`VolumeCap::volume_cap_parse_slot` / `volume_cap_resolve`, composing
  with `libpdx-volume.vol_kind_narrow`).
- **M2-002** real `sys_mount` invocation + mount-table row append via
  `KIND_PDXFS_MOUNT_TABLE` — landed as a documented STUB: `sys_mount`
  (sysno 75) is dispatch-unwired, and even once wired its real ABI does
  not accept a `KIND_VOLUME` cap slot per the aspirational dispatch-
  table contract this repo's own call shape targets.
- **M2-003** user-subtree mount path (no elevate; `/home/`, `/mnt/`,
  `/tmp/`) — a real three-bucket classifier, narrower than §4.2's own
  five-class table (no founder/cross-user distinction; no `KIND_USER`
  identity lookup existed yet).
- **M3-001** the real §4.2 four-class mount-point table (`Elevate::
  mount_point_class`) plus a `libpdx-elevate` call site (`mount_elev_
  require_system`) — fail-closed STUB, mirroring `mkfs.pdxfs`'s own
  M3-005 (#12) landing over the identical library: no broker-endpoint
  cap is provisioned, so every `/system/**`/`/boot/**`/`/dev/**` mount
  point gets `result_code: ELEVATION_STUB` and a non-zero exit.
- **M3-002** real `libpdx-audit` INTENT/RESULT record pair sharing one
  `audit_id` per invocation (`src/audit_wire.pdx`).
- **M3-003** semantic-pipe `PdxFsMountRecord@0.1` schema bind — landed
  as a documented DEFERRAL (`src/pipe_wire.pdx`): `Registry::bind_by_
  name` is confirmed inert (`paideia-os#2000`), so every record stays
  the line-based `sys_write` rendering, now preceded by one deferral
  header line.
- **M3-004** failure-taxonomy encoding: eleven new `MR_RESULT_*` codes
  covering four policy refusals and the seven real kernel-errno
  sentinels `sys_mount.pdx` can return (six `SYS_MOUNT_*` constants plus
  raw `-ENOSYS`), via a new `MountRecord::mount_record_classify_mount_
  errno` classifier.
- **M4-001** happy-path smoke driver
  (`tests/test_happy_mnt.pdx`) — real (non-dry-run) `/mnt/user` mount
  against a well-formed volume cap.
- **M4-002** elevate-required smoke driver
  (`tests/test_elevate_system.pdx`) — `/system/foo`, asserting the
  fail-closed `ELEVATION_STUB` outcome.
- **M4-003** failure-matrix smoke driver
  (`tests/test_failure_matrix.pdx`) — four cases, four distinct
  `MR_RESULT_*` codes.
- **M4-004** elevate-timeout path — a documented STUB
  (`tests/test_elevate_timeout.pdx`): no code path in this repo ever
  dispatches a real elevate request, so there is no timeout to test yet.
- **M5-001** dual-signed release scaffold + `.pdxdoc` + mirror-push
  runbook. Ships `doc/mount.pdxfs.pdxdoc` source form, `release/
  manifest.pdxsig.txt` release-manifest source (every hash and
  signature slot a documented placeholder), and `release/
  RELEASE-1.0.0.md` operator runbook + release note.
- **M5-002** mirror push — documented in `release/RELEASE-1.0.0.md`'s
  own Distribution section; not actually run (mirror endpoint does not
  exist as of this landing).

### Known deferred substrate

- **`sys_mount` (sysno 75) dispatch-unwired.** `dispatch_mount`
  (`src/kernel/core/syscall/dispatch.pdx` L1975, paideia-os) is still an
  unconditional `-ENOSYS` stub. Every non-dry-run invocation of this
  tool observes `result_code: ENOSYS` today.
- **Two incompatible target ABIs for sysno 75.** The dispatch table's
  own forward-declaration comment documents a cap-slot-based contract;
  `sys_mount_body`'s real, already-landed signature takes a raw
  device-path string instead. Confirm with osarch which ABI sysno 75
  should grow into before wiring `dispatch_mount` for real.
- **`KIND_PDXFS_MOUNT_TABLE`'s `PMT_OP_APPEND_ROW` unwired**, and no
  `_init_caps`-style convention exists for seeding a standalone CLI tool
  (as opposed to a long-running IPC server) with a cap slot for this
  kind.
- **No `KIND_ELEVATE_CHANNEL` broker-endpoint cap provisioned.**
  `Elevate::mount_elev_require_system` stays a fail-closed stub until
  one exists — see M3-001 above and `src/elevate.pdx`'s own module
  header.
- **No `KIND_USER` identity lookup.** `Elevate::mount_point_class`
  cannot distinguish an invoker's own `/home/**` subtree from another
  user's; `MPC_CROSS_USER` is a defined but currently unreachable
  ordinal.
- **`libpdx-semantic-pipe` not linked.** Blocked on `paideia-os#2000`
  (`svc.schema-registry` standing up); every record stays the
  line-based fallback rendering.
- **Dual-sign + mirror-push run.** Repo-side scaffolding at M5-001 is
  complete. The signed build + HTTP-PUT to
  `pkgs.paideia-os/main/mount.pdxfs/1.0.0/` requires: (a) the
  paideia-as toolchain reachable in CI, (b) the `pkgs.paideia-os` mirror
  endpoint standing (does not exist as of this landing), and (c) a live
  release-line ML-DSA-65 seed key (hardware-backed custody, never
  repo-resident). Until all three go green, `release/manifest.pdxsig.txt`
  ships with the placeholder value `SIGNATURE_PLACEHOLDER_PENDING_LIVE_
  SIGN` in every signature slot.
- **`cap_check_kind` / `KIND_VOLUME.VOL_OP_MOUNT`.** No independent
  kind-check primitive exists anywhere in the kernel tree, and the
  landed `KIND_VOLUME` op catalog has no dedicated mount-rights ordinal
  — `VolumeCap`'s own module header carries the full write-up,
  unchanged since M2.

### Semver policy

- **Major** — wire-format grow past the documented `PdxFsMountRecord@0.1`
  field shape, error-code renumber, or any API-surface removal.
- **Minor** — additive API surface (e.g. a real `sys_mount` dispatch, a
  real `elevate_client_acquire` body, a real `libpdx-semantic-pipe`
  bind).
- **Patch** — correctness fixes, constant tuning, the deferred dual-sign
  + mirror-push run itself (no repo-side code change).
