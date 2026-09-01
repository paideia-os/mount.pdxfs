# tests/ — mount.pdxfs test suite (M4)

**Milestone lineage.** M4 in `design/tooling/volume-tooling-ux.md` §9.3
(paideia-os). Four issues under this milestone:

- **#11 — M4-001** happy-path smoke: `/mnt` user-owned mount, no elevate.
- **#12 — M4-002** elevate-required smoke: `/system` mount.
- **#13 — M4-003** failure-matrix smoke.
- **#14 — M4-004** elevate-timeout path — **STUB**, see below.

All four landed at M4.

## Why these are pipeline-replay drivers, not a literal `mount.pdxfs
--dry-run ... ` subprocess invocation

`mount.pdxfs` is a standalone ring-3 ELF with its own `_start` (unlike
`libpdx-volume` / `libpdx-audit`, whose M4 test drivers are the
established precedent this suite otherwise follows byte-for-byte) — but
`_start` itself is not a callable, return-value-bearing function: every
path through it ends in a real `sys_exit` syscall and it takes no
arguments a test driver could stage in `.bss`. There is also no
QEMU-boot smoke-test harness in this repo (or, as of this landing,
anywhere in `paideia-satellites/` for a standalone argv-driven CLI
tool — `libpdx-audit`'s own M4 precedent is a QEMU-boot PROTOCOL, not a
subprocess-argv one) that could exec the compiled binary with a real
argv array, capture its stdout, and report pass/fail back to a
`u64`-returning caller.

Every driver in this directory instead does what `_start` itself does,
one call at a time: it builds a synthetic argv array (or feeds a
hand-written `<mount-point>` / `<volume-cap>` string directly) into
`Argv::argv_parse`, then walks the SAME sequence of real, linked entry
points `src/main.pdx`'s `_start` calls in the SAME order —
`Elevate::mount_point_class`, `Elevate::mount_elev_require_system`,
`VolumeCap::volume_cap_resolve`, `MountOp::mount_op_invoke`,
`MountRecord::mount_record_classify_mount_errno` — asserting on each
one's real return value, and returns a `u64` status instead of the
literal "emit \<message\>, exit \<code\>" a real invocation would
produce. This exercises the actual dispatch logic `_start` runs (every
function called here is the SAME code, not a mock), just without the
final `sys_write`/`sys_exit` framing — the identical trade every M4
driver in `libpdx-volume` / `libpdx-audit` already makes for their own
console-free bodies, here applied to a CLI tool's `_start` dispatch
instead of a library's public API.

## Return-code convention

Every driver exports `run() -> u64`: `0` means "every assertion in this
driver passed"; any nonzero value identifies which assertion failed
first (see each file's own header for its exact nonzero-code table). A
future test harness — either a proper QEMU-boot argv/subprocess
protocol once one exists for standalone CLI tools, or a thin `pkg`/
`shell`-hosted runner that links this repo's `src/` alongside these
drivers — walks the driver list and reports each nonzero return using
the table in that driver's own file header; the process exits 0 iff
every driver returned 0. Matches `libpdx-volume`'s own `tests/README.md`
convention exactly.

## Why no link step happens here

`tools/build.sh` compiles every `src/*.pdx` file to its own `.o`
independently, with no link step — cross-module calls like `call
argv_parse;` are unresolved-external references in a test file's own
object, resolved only once a future consumer links `src/` alongside
these drivers. Every driver here is written against that same
convention: `call argv_parse;`, `call mount_point_class;`, `call
volume_cap_resolve;`, `call mount_op_invoke;`, `call mount_record_
classify_mount_errno;` are all bare unqualified cross-file references,
matching every other cross-file call already in this repo (main.pdx's
own calls into `argv.pdx` / `elevate.pdx` / `volume_cap.pdx` /
`mount_op.pdx` / `mount_record.pdx` use the identical convention).

## Files

- **`test_happy_mnt.pdx`** (M4-001, #11) — drives the pipeline for
  `<volume-cap>=cap:volume:0x42`, `<mount-point>=/mnt/user`, no
  `--dry-run` (a real, non-dry-run invocation). Asserts `mount_point_
  class` returns `MPC_USER_SUBTREE` (no elevate reached), `volume_cap_
  resolve` returns `VC_OK`, and `mount_op_invoke` returns either
  `MOUNT_OP_OK` (the real success path, unreachable today per `src/
  mount_op.pdx`'s own kernel-gap #1) or `MOUNT_OP_ERR_KERNEL` with the
  captured raw errno classifying to `MR_RESULT_ENOSYS` (the actual,
  observed outcome today, since `dispatch_mount` is still an
  unconditional `-ENOSYS` stub) — a strictly more precise assertion than
  this issue's own "or KERNEL_ERROR" allowance, since M3-004 (#10) gave
  ENOSYS its own distinct code. Returns `0` on both outcomes; a distinct
  nonzero code per failing assertion otherwise.
- **`test_elevate_system.pdx`** (M4-002, #12) — same pipeline for
  `/system/foo`. Asserts `mount_point_class` returns `MPC_SYSTEM_PATH`
  and `mount_elev_require_system` returns `MOUNT_ELEV_DENY` (the only
  value reachable at this landing — see `src/elevate.pdx`'s own module
  header for the fail-closed posture), which is exactly the
  `result_code: ELEVATION_STUB` `main.pdx`'s own dispatch would emit for
  this input. Returns `0` on match, a distinct nonzero code otherwise.
- **`test_failure_matrix.pdx`** (M4-003, #13) — four deliberately-invalid
  or elevate/kernel-gated inputs, each asserted against a DIFFERENT
  `MR_RESULT_*` code the real pipeline would select: a malformed
  `<volume-cap>` hex tail (`MR_RESULT_BAD_VOLUME_CAP`), a mount point
  matching none of the six known prefixes (`MR_RESULT_INVALID_MOUNT_
  POINT`), a `/system/**` mount point (`MR_RESULT_ELEVATION_STUB`), and
  a well-formed real-mount attempt against the still-unwired kernel
  (`MR_RESULT_ENOSYS`). Returns `0` if all four match, else the 1-based
  ordinal of the first case that failed.
- **`test_elevate_timeout.pdx`** (M4-004, #14) — **STUB**. No caller in
  this repo (`src/elevate.pdx`'s `mount_elev_require_system`) ever
  actually dispatches an `elevate_client_acquire` / `elevate_client_
  request_ex` call — the fail-closed posture (module header,
  `src/elevate.pdx`) means there is no wired timeout path to exercise at
  all: `libpdx-elevate`'s own real timeout machinery
  (`elevate_client_recv_reply`'s bounded poll, `elevate_client_set_
  human_timeout` / `_fast_timeout`) is real and mature, but nothing in
  this repo calls into it. `run()` always returns
  `TET_DEFERRED = 0xFFFFFFFFFFFFFFFF` — a sentinel deliberately distinct
  from `0` (pass) so a future harness walking driver return codes does
  not mistake "nothing to test yet" for "tested and passed" without
  reading this driver's own header. Re-open this test once `src/
  elevate.pdx` gains a real broker-endpoint cap and an actual
  `elevate_client_acquire` call site to time out.

## What a full QEMU smoke matrix still needs

- **M4-001 / M4-002 / M4-003** are fully self-contained today: all three
  drivers exercise real, non-stub bodies (`argv_parse`, `mount_point_
  class`, `mount_elev_require_system`, `volume_cap_resolve`, `mount_op_
  invoke`, `mount_record_classify_mount_errno`) entirely through `.bss`
  and caller-supplied pointers, with no real kernel dependency beyond
  the syscalls those bodies themselves issue transparently. A future
  consumer tool (this repo's own `tools/run-smoke.sh`, once one exists
  for a standalone CLI tool the way `paideia-os`'s own kernel-level
  `tools/run-smoke.sh` exists for the kernel image) linking `src/`
  alongside these three drivers and printing their return codes is the
  only thing missing before these run under real QEMU boot.
- **M4-004** needs `src/elevate.pdx` to gain a real
  `KIND_ELEVATE_CHANNEL` broker-endpoint cap and an actual dispatched
  `elevate_client_acquire` call before a genuine timeout scenario can be
  constructed at all — see that file's own module header.
