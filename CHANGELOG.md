# mount.pdxfs — CHANGELOG

## 1.1.3 — 2026-09-02 (ENH-030: libpdx-argv adoption — replaces handwritten scanner)

**Patch bump — no observable behaviour change for well-formed input;
every exit code + stderr diagnostic preserved.** Replaces the
handwritten long-flag scanner in `src/argv.pdx` with a thin wire-in
over paideia-satellites/libpdx-argv v1.1.0 (ENH-030 rename tag). Every
public symbol callers depend on — the `argv_parse` entry point, the
`PA_OFF_*` / `PA_FLAG_*` / `PA_STRUCT_BYTES` constants, and every
`ARGV_ERR_*` return code — keeps its numeric value and its byte
offset unchanged, so `src/main.pdx`'s direct-offset loads at
`[r14 + 0]` / `[r14 + 8]` / `[r14 + 16]` / `[r14 + 24]` and
`tests/test_happy_mnt.pdx`'s `thm_parsed: [u8; 24]` buffer with
reads at +8/+16 continue to work byte-for-byte.

### Added

- **libpdx-argv wire-in** — `argv_parse` now registers the 8
  mount.pdxfs long flags with `flag_spec_register()` (each bound to a
  `FID_*` in the 100..107 range and a `FKIND_BOOL` / `FKIND_INT` value
  kind), drives `parse_argv(argv+8, argc-1)`, then walks
  `flag_ids[0..flag_count)` once to populate the caller's 48-byte
  ParsedArgv struct. `--snapshot=<slot>` still ORs both
  PA_FLAG_SNAPSHOT_SET (0x40) AND PA_FLAG_RO (0x1) into flags as
  0x41 — the "snap mount is RO" invariant preserved verbatim.
- **passphrase_fd = -1 sentinel** — the shim's zero-init pass writes
  the i64 unset-sentinel 0xFFFFFFFFFFFFFFFF into PA_OFF_PASSPHRASE_FD
  (+32) via `mov r10, 0xFFFFFFFFFFFFFFFF; mov [rbx+32], r10`,
  preserving the pre-shim distinction between "explicitly set to
  fd 0" and "left unset" for downstream unlock-hop dispatch.
- **Flag-name literals** — new NUL-terminated `[u8; N]` names in
  .rodata (`mount_argv_name_ro`, `_noexec`, `_verbose`, `_dry_run`,
  `_all`, `_snapshot_list`, `_snapshot`, `_passphrase_fd`).

### Removed

- **Handwritten scanner** — `argv_streq`, `argv_prefix_match`,
  `argv_parse_u64_dec`, and every `argv_lit_*` literal deleted.

### Behaviour notes

- **Relax-gates preserved**: `--all` overrides both positional
  checks; `--snapshot=<slot>` skips the volume-cap check;
  `--snapshot-list` skips the mount-point check. Return codes
  (ARGV_OK / ARGV_ERR_MISSING_VOLUME_CAP=1 / ARGV_ERR_MISSING_MOUNT_
  POINT=2) fire on identical inputs as the pre-shim body.
- **`--snapshot=<slot>` implies RO** — the shim OR's 0x41
  (PA_FLAG_SNAPSHOT_SET | PA_FLAG_RO) into flags on a match,
  matching pre-shim v1.1.2's `or rax, 0x41` idiom.
- **Malformed `--snapshot=abc` / `--passphrase-fd=abc`**: shim
  leaves the default in place (0 for snapshot_slot, -1 for
  passphrase_fd) and does NOT latch the presence bit. Pre-shim
  latched with a zero value; observationally equivalent for callers
  that consult only the value slot.

### Build

- **`bash tools/build.sh --extra-obj-dir ../libpdx-argv/build-out
  ...`** — the standing invocation must now include libpdx-argv's
  build-out alongside libpdx-volume's.

Closes #25 (satellite adoption of libpdx-argv). Depends on
libpdx-argv v1.1.0 (ENH-030 rename).

## 1.1.2 — 2026-09-02 (Phase C: `--extra-archive` + `--gc-sections` for satellite-runtime link)

**Patch bump — additive `tools/build.sh` flag; every existing invocation
still works unchanged.** Wires the two Phase A/B archives from
paideia-os#2226's satellite-runtime-shim landing (paideia-as v0.29.1
`libpaideia_satellite_runtime.a` + libpdx-audit v1.1.1
`libpdx-audit-satellite.a`) through this repo's own final `ld` link so
`bash tools/build.sh --extra-archive .../libpaideia_satellite_runtime.a
--extra-archive .../libpdx-audit-satellite.a` now resolves the
satellite-runtime symbol references (crypto FFI thunks +
`mldsa65_sign_runtime_entry` + `audit_begin` / `audit_commit`
satellite bodies + panic/allocator/eh_personality shim) end-to-end.

### Added

- **`--extra-archive PATH` (repeatable)** on `tools/build.sh`, symmetric
  to the existing `--extra-obj-dir DIR` flag: each PATH is a static
  archive (`.a`) appended to the final `ld` link line AFTER the
  --extra-obj-dir loose objects. Archives are pulled in AS-NEEDED
  (unlike loose objects, which link unconditionally), so the archive
  contents only pay their way for symbols the ELF actually references.
  Bounds-checks the value slot; a bare `--extra-archive` with no
  following PATH exits 2 with `--extra-archive requires an argument`
  (same discipline as `--extra-obj-dir`). A PATH that names a missing
  file surfaces later as an `ld` open-failure at link time (not an
  early parse error) — the flag validates only that the slot was
  supplied, mirroring how `--extra-obj-dir` never validates its DIR.

### Changed

- **`ld` link line** — added `--gc-sections` to the `ld -nostdlib
  --warn-common --fatal-warnings` invocation. Essential when linking
  the Phase A staticlib: Rust archives emit per-function sections
  (`.text.<sym>`), and `--gc-sections` walks from `_start` (KEEPed by
  `link.ld` at `.text._start`) and prunes every satellite-runtime
  symbol nothing in this repo transitively references. Without it, the
  archive dumps unused compiler-builtins/std padding into the ELF and
  leaves dangling refs from Rust's own internal call graph. This
  repo's own `src/*.pdx` objects emit into one big `.text` section per
  module, so `--gc-sections` is a no-op for them (the section stays
  live as soon as `_start` is reached).

### Invocation (unchanged for callers not wiring in Phase A/B archives)

```
# Old — still works, still emits build-out/mount.pdxfs.elf against
# just this repo's own objects (dangling refs on satellite-runtime
# symbols surface at ld, not here):
bash tools/build.sh --extra-obj-dir ../libpdx-volume/build-out

# New — resolves every satellite-runtime ref, end-to-end link OK:
bash tools/build.sh \
  --extra-obj-dir ../libpdx-volume/build-out \
  --extra-archive $HOME/Development/PaideiaOS/tools/paideia-as/target/release/libpaideia_satellite_runtime.a \
  --extra-archive $HOME/tmp/libpdx-audit/build-out/libpdx-audit-satellite.a
```

References: paideia-os#2226, paideia-as#1348, libpdx-audit#19, design
doc `design/infrastructure/satellite-runtime-shim.md` §4.1 + §5 Step 5.

## 1.1.1 — 2026-09-02 (M6-002 wire-through fix — issue #22 completion)

**Patch bump — completes the M6-002 (#22) landing.** The 1.1.0 landing
of `src/mint_wire.pdx` shipped `mint_wire_invoke` as fully wired inside
the module but ORPHANED at the call-site level: `src/main.pdx` never
invoked it, and the system-tier path still called the M3-era
`mount_elev_require_system` stub (fixed exit 4, `MR_RESULT_
ELEVATION_STUB`) instead. STATUS.md and this CHANGELOG's own 1.1.0
entry both claimed "system-tier mounts without a provisioned
`KIND_ELEVATE_CHANNEL` cap refuse `MW_ERR_NO_ELEVATE` (→
`MR_RESULT_NO_ELEVATE = 16`) BEFORE the library call" — a claim no
code path actually made true. 1.1.1 makes it true.

### Landed

- **M6-002 (#22 wire-through)** — `src/main.pdx`'s Phase 3 SYSTEM_PATH
  / CROSS_USER branch now calls `mint_wire_invoke(dev_cap=0,
  mpc_class, &mount_narrowed_slot)` instead of `mount_elev_require_
  system`. Dispatch on the MW return:
  - `MW_OK` (0) → jump to `mount_main_mount_op` with the minted
    narrowed slot already in `mount_narrowed_slot` (bypasses
    `volume_cap_resolve` — the raw `<volume-cap>` URI is unused on
    the elevated path; the minted slot IS the cap `sys_mount`
    consumes). Unreachable today.
  - `MW_ERR_NO_ELEVATE` (1) → `mount_main_m22_no_elevate`: emits
    `MR_RESULT_NO_ELEVATE = 16`, exit 3. **The one reachable
    system-tier outcome at this landing** (the refuse-gate fires on
    every call: no `KIND_ELEVATE_CHANNEL` cap is provisioned).
  - `MW_ERR_LIBPDX_VK` (2) or unrecognised → `mount_main_m22_mint_
    failed`: emits **new** `MR_RESULT_MINT_FAILED = 22`, exit 3.
    Wired but unreachable until the refuse-gate stops firing (i.e.
    once cap-seeding lands and the mint hop itself starts running).
- **New `MR_RESULT_MINT_FAILED` code (22)** — added to
  `src/mount_record.pdx` (constant, `MINT_FAILED` label literal,
  cmp/je case in `mount_record_emit_result`). Distinct from
  `MR_RESULT_NO_ELEVATE` (16, pre-library refusal) and
  `MR_RESULT_NARROW_FAILED` (7, legacy user-tier
  `volume_cap_resolve` failure).

### Removed from the production path

- `Elevate::mount_elev_require_system` no longer has any call site in
  `src/main.pdx`. The function itself remains defined in
  `src/elevate.pdx` (still-returning `MOUNT_ELEV_DENY`) because its
  M4-002 test driver `tests/test_elevate_system.pdx` still asserts the
  DENY posture. `MR_RESULT_ELEVATION_STUB` (4) constant + label are
  retained in `src/mount_record.pdx` for wire-format compatibility
  with any 1.0.x/1.1.0 record consumer, but no code path in v1.1.1
  emits code 4 any more.

### Known gap flagged for main

- **No `KIND_BLOCK_DEVICE` resolver.** `mint_wire_invoke` takes a
  `dev_cap` as its first argument (the backing block device from
  which a fresh `KIND_VOLUME` cap is minted); no upstream helper
  exists in this repo (or in `libpdx-volume`) that maps a
  `<volume-cap>` URI string to the corresponding
  `KIND_BLOCK_DEVICE` cap slot. `src/main.pdx` passes `rdi = 0` at
  the call site — safe TODAY because `mint_wire_invoke`'s
  refuse-gate consumes every reachable system-tier call before
  `vol_kind_mint_elevate` ever dereferences dev_cap, but the gap
  becomes load-bearing the day cap-seeding installs a real
  `KIND_ELEVATE_CHANNEL` slot. **Flagged for a follow-up landing
  paired with the cap-seeding hook that closes the elevate-cap
  provisioning gap.**

## 1.1.0 — 2026-09-02 (M6, libpdx-volume v1.1.0 API adoption — issues #21..#24)

**Minor bump — additive API adoption, no wire-format break.** Adopts
the full libpdx-volume v1.1.0 API surface (LV.M1..M6 landings, issues
`paideia-os/libpdx-volume#18`..`#31`) plus three new argv surfaces and
six new `MR_RESULT_*` codes. The pre-existing dry-run and legacy
non-`--dry-run` paths are byte-for-byte unchanged; every M6 addition
is either a new argv flag, a new emitter code, or a new wire-through
helper module. No existing consumer of this tool needs to change.

### Landed

- **M6-001 (#21)** — libpdx-volume v1.1 API cleanup adoption
  (`src/lpv_errors_wire.pdx`, new). Wraps `lpv_strerror` in a
  bounded-buffer fd-2 diagnostic helper; the six new `pdxb_sb_get_*`
  accessors and the banded `LPV_E_*` namespace are consumed directly
  by the M6 wire modules below (no per-consumer shim). Parents:
  `libpdx-volume` #18/#19/#20.
- **M6-002 (#22)** — LV.M2-003 elevate-cap wire-through for
  `vol_kind_mint_elevate` (`src/mint_wire.pdx`, new). Provides
  `mint_wire_invoke(dev_cap, mpc_class, out_slot)` composing the
  elevate-tier selection with the new 3-arg mint form; refuses cleanly
  with `MW_ERR_NO_ELEVATE` on a system-tier mount without a provisioned
  `KIND_ELEVATE_CHANNEL` cap (today's posture — parent `libpdx-volume`
  #23 landed the API, not the broker-endpoint cap seeding).
  **Post-landing note (1.1.1):** the module itself is fully wired but
  had no call site in `src/main.pdx` at 1.1.0 — the system-tier path
  still called the M3-era `mount_elev_require_system` stub instead, so
  the "refuses with `MW_ERR_NO_ELEVATE` → `MR_RESULT_NO_ELEVATE`"
  claim above only became true at 1.1.1. See 1.1.1 entry above.
- **M6-003 (#23)** — LV.M3 snapshots: `--snapshot=<slot>` read-only
  mount surface + `--snapshot-list` enumeration (`src/snapshot_wire.
  pdx` new, argv extended, `main.pdx` M6 dispatch). `--snapshot=`
  narrows to `R_VSNAP_READ` via `vol_snapshot_narrow` and issues a
  snap-mount kernel op (KERNEL GAP #A: no snap-mount syscall exists
  yet, so every legal call refuses `SNAPSHOT_NOT_IMPL`).
  `--snapshot-list` is a passthrough to `snap_chain_walk` (KERNEL GAP
  #B in libpdx-volume: the walker is itself a stub returning
  `LPV_SNAP_ERR_NOT_IMPL` for every input). The FROZEN gate
  (`snapshot_wire_check_frozen`) is wired but unreachable until GAP #B
  closes. Parents: `libpdx-volume` #25/#26.
- **M6-004 (#24, part A)** — LV.M5 `--passphrase-fd=<n>` argv surface
  + KEK-derive + DEK-unwrap composition (`src/passphrase_wire.pdx`,
  new). `passphrase_wire_read` / `passphrase_wire_unlock` /
  `passphrase_wire_wipe` are real bodies over the v1.1 crypto helpers
  (`pdxb_kek_derive`, `pdxb_dek_unwrap`); the mount-time hook that
  calls them lives at Phase 5 (mount_op) and is deferred until (a) the
  kernel-side `KIND_DEK` cap kind lands (GAP #P2) and (b)
  `dispatch_mount` is wired for real (already-flagged gap since M2).
  The argv flag is fully parsed and the value is stashed in
  `ParsedArgv.passphrase_fd` (offset +32). Parents: `libpdx-volume`
  #29/#30.
- **M6-005 (#24, part B)** — LV.M4 quota enforcement wrapper
  (`src/quota_wire.pdx`, new). `quota_wire_install` is a documented
  stub returning `QW_OK` (no-op) or `QW_ERR_NOT_IMPL` per superblock
  `PDXB_FLAG_HAS_QUOTA` bit (GAP #Q1: no `KIND_PDXFS_QUOTA` cap kind
  kernel-side). `quota_wire_check_or_refuse` is a REAL body over
  `pdxb_quota_check` with the tool's `EDQUOT`-style refusal contract;
  call sites appear once `mount.pdxfs` (or a companion FS-write
  daemon) grows a real write path (GAP #Q2). Parent: `libpdx-volume`
  #28.
- **M6-006 (#24, part C)** — LV.M6 dep-graph refusal (`--all` argv
  surface, `src/dep_graph_wire.pdx`, new). `dep_graph_wire_sort` +
  `dep_graph_wire_parse_block` wrap `mount_table_sort_by_deps` +
  `mount_deps_parse`. Today's posture: any non-empty `--all`
  invocation reaches `LPV_ORDER_ERR_NOT_IMPL` (0x0A04), mapped to
  `MR_RESULT_DEP_ORDER_NOT_IMPL` (21, new). Refusal is BEFORE any
  real mount happens, matching the ticket's "any missing
  mount-requires dep refuses the whole --all invocation" contract.
  Parent: `libpdx-volume` #31.

### Argv surface additions

- `--all` — batch mount every volume in a caller-visible manifest
  (source shape agreed with the future `mountall.pdxfs` tool). Today
  refuses `DEP_ORDER_NOT_IMPL`.
- `--snapshot=<slot>` — mount a `KIND_VOLUME_SNAPSHOT` cap read-only
  at `<mount-point>`; PA_FLAG_RO is stamped implicitly. Today refuses
  `SNAPSHOT_NOT_IMPL`.
- `--snapshot-list` — enumerate the snap chain anchored at a
  `<volume-cap>`'s superblock; today refuses `SNAPSHOT_NOT_IMPL`.
- `--passphrase-fd=<n>` — read a passphrase from fd `<n>` at mount
  time (used by the future encrypted-volume mount hop). Parsed and
  stashed today; consumed at Phase 5 once the surrounding gaps close.

### New MR_RESULT_* codes (16..21)

Six additions to the `PdxFsMountRecord@0.1` `result_code` vocabulary,
each with its own literal in `src/mount_record.pdx`'s emitter:

- `NO_ELEVATE` (16) — system-tier mount without a provisioned
  `KIND_ELEVATE_CHANNEL` cap (surfaces via `mint_wire_invoke` and, in
  future, via any elevate-gated wire helper).
- `SNAPSHOT_NOT_IMPL` (17) — snap-mount syscall / snap_chain_walk
  stub (`--snapshot=` and `--snapshot-list`).
- `SNAPSHOT_NOT_FROZEN` (18) — FROZEN gate refusal (wired but
  unreachable at this landing).
- `WRONG_PASSPHRASE` (19) — AEAD tag mismatch on DEK unwrap
  (`LPV_CRYPTO_ERR_TAG_MISMATCH`, wired via `passphrase_wire_unlock`;
  no call site until the mount-op hop closes).
- `EDQUOT` (20) — quota-hard-exceeded or grace-expired refusal from
  `quota_wire_check_or_refuse` (call site awaits a real write path).
- `DEP_ORDER_NOT_IMPL` (21) — `--all` refusal from
  `dep_graph_wire_sort`.

### Known deferred substrate (delta from 1.0.x)

- **KERNEL GAP #A (snap-mount syscall)**: no syscall analogous to
  `sys_mount` that accepts a `KIND_VOLUME_SNAPSHOT` slot and stamps
  the resulting mount-table row with `snap_id + read-only`. Every
  `--snapshot=` call refuses `SNAPSHOT_NOT_IMPL` until this lands.
- **KERNEL GAP #B (snap_chain_walk)**: `libpdx-volume` v1.1.0's
  walker is itself a stub. Every `--snapshot-list` call refuses
  `SNAPSHOT_NOT_IMPL` until this lands upstream.
- **GAP #P1 (`pdxb_sb_get_dek_nonce` accessor)**: no getter for the
  wrapped-DEK's AEAD nonce at v1.1.0. `src/passphrase_wire.pdx`
  reads it via direct offset arithmetic on the caller-supplied
  superblock buffer (`PW_D_OFF_DEK_NONCE = 256`). **Flagged for
  libpdx-volume v1.1.x follow-up.**
- **GAP #P2 (`KIND_DEK` cap kind)**: no kernel-side cap kind for a
  32-byte unwrapped DEK. Every unlocked DEK stays in .bss scratch
  today; the "install as cap" step at the bottom of
  `passphrase_wire_unlock` is a future landing.
- **GAP #Q1 (`KIND_PDXFS_QUOTA` cap kind)**: no kernel-side cap kind
  to seed the FS layer's per-mount quota-table cache. Every mount
  with `PDXB_FLAG_HAS_QUOTA` set silently proceeds without quota
  enforcement at this landing.
- **GAP #Q2 (`mount.pdxfs` write path)**: no in-tool write path yet.
  `quota_wire_check_or_refuse` is a real body with no production call
  sites; a future landing wires it into whichever component grows the
  first write op.
- **`libpdx-elevate` broker-endpoint cap**: unchanged since M3-001.
  Every system-tier mount observes `NO_ELEVATE` (16) at v1.1.1 (was
  `ELEVATION_STUB` (4) at 1.1.0 due to the #22 orphan-wiring gap
  fixed in 1.1.1).

## 1.0.1 — 2026-09-01 (paideia-os#1976/#1977 satellite-embedding wiring)

**Build tooling only, no source/wire-format change.** `tools/build.sh`
now links `build-out/*.o` into `build-out/mount.pdxfs.elf` (+ `.bin` via
`objcopy` where available) using a new root-level `link.ld`, matching
paideia-os's own `src/user/true.ld` layout (`.bss` kept contiguous with
`.data` per paideia-os#1595) and its `tools/build-user.sh` `ld`
invocation convention (`--warn-common --fatal-warnings`). Adds a
repeatable `--extra-obj-dir DIR` flag so a caller (e.g. paideia-os's own
`/bin`-seeding build) can fold in out-of-tree `.o` dependencies; a
missing or empty `DIR` contributes nothing and is not an error.
Compile-time test scaffolding (`build-out/tests-*.o`) is excluded from
the link. This is the linking half of wiring mount.pdxfs into
paideia-os's boot-time `/bin` seeding pipeline (paideia-os#1976/#1977).

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
