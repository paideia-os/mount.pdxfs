# mount.pdxfs — architecture

**Wave:** R53 tool (design/tooling/volume-tooling-ux.md §2.2 + §4 + §9.2)
**Repo:** github.com/paideia-os/mount.pdxfs
**Upstream design:** `design/tooling/volume-tooling-ux.md` §4 (CLI spec)
+ §9.2 (milestone breakdown) and
`design/tooling/volume-lifecycle-mechanism.md` (mount/unmount kernel
mechanism, needed from M2 onward) in
[paideia-os](https://github.com/paideia-os/paideia-os).

This document describes the internal shape of `mount.pdxfs`. It does
not repeat the wave-level rationale from the paideia-os plan doc; read
that first for why volume tooling needs three CLIs plus one shared
library (`libpdx-volume`) and for the R52/R53 boundary. It also
deliberately mirrors the shape of `mkfs.pdxfs`'s own
`design/architecture.md` — same wave, same repo conventions, same
"module per public-entry-point family" granularity — and calls out
where mount.pdxfs's own task brief diverges from that sibling tool.

## 1. What this tool is

`mount.pdxfs` is a standalone ring-3 ELF — a `_start`-based executable,
**not** a shared library like `libpdx-volume` or `libpdx-audit`. It
performs its own syscalls directly (self-contained inlined-syscall
pattern), matching `src/user/true.pdx` / `cat.pdx` / `mkdir.pdx` and
this wave's own sibling tool `mkfs.pdxfs`, rather than delegating every
kernel touch to a linked library. The one library it will link,
`libpdx-volume`, supplies the `vol_kind_narrow` sub-cap narrowing and
`mount_table_snapshot` row lookup — not process lifecycle, argv, or
output.

`mount.pdxfs` attaches a `KIND_VOLUME` cap to a VFS mount point via a
future `sys_mount` syscall, appending a row to the kernel's
`KIND_PDXFS_MOUNT_TABLE`, per `design/tooling/volume-tooling-ux.md` §4.
The invoker supplies both the volume cap and the mount point as
positional argv; the tool resolves rights, optionally elevates, and
(from M3 onward) journals an INTENT record before the syscall and a
RESULT record after.

## 2. Module split

Four source files, one per major concern (matches `mkfs.pdxfs`'s own
four-file split and `libpdx-volume`'s/`libpdx-audit`'s "one module per
public-entry-point family" granularity):

- **`src/main.pdx`** (`Main`) — `_start`. Wires argv parsing → the M1
  dry-run emit path, or falls through to a `not yet implemented`
  diagnostic. Owns the `ParsedArgv` scratch struct's storage
  (`mount_argv_out`, `.bss`) and the three fd-2 diagnostic message
  literals.
- **`src/argv.pdx`** (`Argv`) — the long-flag CLI parser (`argv_parse`)
  plus one pure-leaf helper it calls (`argv_streq`). Owns the
  `ParsedArgv` out-struct layout constants (`PA_OFF_*`, `PA_FLAG_*`) and
  every flag literal. Simpler than `mkfs.pdxfs`'s own `argv.pdx`: all
  four of this tool's flags are boolean (no `--flag=value` surface at
  M1), so there is no `argv_prefix_match` or `argv_parse_u64_dec`
  counterpart.
- **`src/mount_record.pdx`** (`MountRecord`) — `mount_record_emit_
  dry_run`, the M1 `PdxFsMountRecord@0.1` line-based text emitter, plus
  its own private `mount_record_strlen` helper. Directly analogous to
  `mkfs.pdxfs`'s `format_record.pdx`.
- **`src/elevate.pdx`** (`Elevate`) — `elevate_needed`, an M1 scaffold
  stub that unconditionally returned "not required" (see §5 below for
  the original M1 posture; §10 for the real M2-003 classifier that
  replaced it). `mkfs.pdxfs` has no direct analogue to this file (its
  own elevate concern is scoped to M3-005 with no M1 placeholder file)
  — this repo's task brief explicitly asked for the placeholder to
  exist from M1 so the M3-001 call site has somewhere to land without
  an ABI change to `main.pdx`.
- **`src/volume_cap.pdx`** (`VolumeCap`) — new at M2-001. `volume_cap_
  parse_slot` (a `cap:volume:0xNN` URI decoder) and `volume_cap_resolve`
  (composes the parse with `libpdx-volume.vol_kind_narrow`). See §10.1.
- **`src/mount_op.pdx`** (`MountOp`) — new at M2-002. `mount_op_invoke`
  (the real-vs-dry-run `sys_mount` call) and `mount_op_append_row` (the
  `KIND_PDXFS_MOUNT_TABLE` row-append stub). See §10.2 for the three
  kernel-side gaps this file documents in full, with source citations.

Kept as four separate files rather than one `main.pdx` monolith for the
same reason `mkfs.pdxfs` gives: each has a distinct, independently
growable contract (argv parsing, record emission, and elevate policy
are three different problems `M2`/`M3` will each grow independently —
`elevate.pdx` grows the real mount-point-class table at M3-001,
`mount_record.pdx` grows the full 10-field semantic-pipe emit at
M3-003, `argv.pdx` potentially gets replaced wholesale by a
`libpdx-argv`-backed rewrite — none of which should require touching
the other three files).

## 3. `libpdx-argv` / `libpdx-elevate` availability — confirmed absent, minimal fallbacks shipped instead

Same situation `mkfs.pdxfs.M1-002`'s own `design/architecture.md` §3
documents, re-confirmed for this landing: a `grep -rl libpdx-argv` and
`grep -rl libpdx-elevate` across the paideia-os monorepo and every repo
under `paideia-satellites/` finds **zero implementation files** for
either — only design-doc *mentions* of both as planned R49-wave shared
libraries (`design/tooling/r49-r50-plan.md` §3.2). No repo named either
exists under `paideia-satellites/` as of this landing (the only repos
there are `libpdx-audit`, `libpdx-volume`, `mkfs.pdxfs`, and this one).

Per the task brief's own fallback instruction, `src/argv.pdx` therefore
implements a **minimal long-flag parser inline**, in the identical
shape `mkfs.pdxfs.M1-002` landed: `Argv::argv_parse` takes `(argc,
argv, out_ptr)` and returns a status code, writing a 24-byte
`ParsedArgv` struct (three u64-aligned slots: `flags`,
`volume_cap_ptr`, `mount_point_ptr`) to `out_ptr`. This is deliberately
the same shape a future `libpdx-argv`-backed rewrite would present —
swapping `argv_parse`'s body would not require `main.pdx` to change at
its one call site.

`src/elevate.pdx` similarly ships a minimal scaffold ahead of
`libpdx-elevate`'s existence: `elevate_needed(mount_point_ptr) -> u64`
is the shape a future real classification + `KIND_ELEVATE_CHANNEL`
round-trip would present, but the M1 body is a two-instruction stub
(`xor rax, rax; ret`) that never inspects its argument. Unlike
`argv.pdx` (which has a real body doing real work at M1, just a minimal
one), `elevate.pdx`'s body is a true placeholder — no caller in this
repo invokes it yet, so there is nothing for it to get right or wrong
at M1 beyond "compile and always answer permissively."

The argv parser supports exactly the four flags/two positionals this
tool's task brief documents (`--ro`, `--noexec`, `--verbose`,
`--dry-run`, `<volume-cap>`, `<mount-point>`) via one shared compare
subroutine (`argv_streq`, exact-match only — no prefix matching needed
since every flag here is boolean). It does not implement short flags,
flag clustering, value-flags, or the 9-flag "standard vocabulary"
(`--help`, `--version`, `--json`, ...) `design/tooling/r49-r50-plan.md`
§3.3 describes for the eventual `libpdx-argv` — out of scope for this
issue's "minimal" instruction, inherited for free from a real
`libpdx-argv` link once one exists.

## 4. `PdxFsMountRecord@0.1` — what M1 actually prints

`design/tooling/volume-tooling-ux.md` §7.2 defines the full 10-field
schema (`audit_id`, `mount_id`, `volume_uuid`, `volume_cap_uri`,
`mount_point`, `flags`, `invoker_user`, `result_code`, `elevate_id`,
`ts_ns`). The task brief's own acceptance text asks for a much smaller
slice:

```
PdxFsMountRecord@0.1 { volume: <cap>, mount_point: <path>,
                       flags: <flags>, result_code: DRY_RUN }
```

`src/mount_record.pdx`'s `mount_record_emit_dry_run` prints exactly
this four-field line, via a fixed sequence of `sys_write(1, ...)` calls
(literal chunk, then dynamic value, repeated) — no schema-registry
binding, no `KIND_IPC_ENDPOINT` framing, matching `mkfs.pdxfs`'s own
`format_record_emit_dry_run` structure exactly. Three of the four
fields printed are the caller's real arguments (the actual
`<volume-cap>` string, the actual `<mount-point>` string, a real
decimal conversion of the actual `ParsedArgv.flags` bitmask); only
`result_code` is a fixed literal (`DRY_RUN`) — correct at the one call
site that exists at M1, since `main.pdx` only reaches this function on
the `--dry-run` branch. What is deferred to `mount.pdxfs.M3-003` is the
remaining six schema fields (most of which need substrate this repo
does not have at M1: a real `sys_mount` for `mount_id`/`volume_uuid`, a
`KIND_USER` lookup for `invoker_user`, an elevate round-trip for
`elevate_id`, a clock read for `ts_ns`) and the semantic-pipe binary
framing itself.

## 5. `elevate.pdx`'s M1 scope — a permissive stub, not a policy

`design/tooling/volume-tooling-ux.md` §4.2 describes a mount-point-
class table gating whether `mount.pdxfs` must request elevation via
`KIND_ELEVATE_CHANNEL` before calling `sys_mount` (always-elevate for
`/system`, `/boot`, `/dev`; never for `/mnt`, own-subtree `/home`,
`/tmp`; founder-only-elevate for cross-user `/home` and the
conservative default). None of that table exists at M1 — this repo's
own scaffold instruction scopes `elevate.pdx` as a "placeholder for
elevate-channel logic (M2+)."

`Elevate::elevate_needed` implements the narrowest possible stub:
`ELEVATE_NOT_REQUIRED` unconditionally, regardless of
`mount_point_ptr`'s value. This is safe precisely because nothing in
this repo calls `sys_mount` yet — a permissive stub cannot cause an M1
caller to skip a real safety check that does not exist. The real
mount-point-class classification and `KIND_ELEVATE_CHANNEL`
request/response exchange is `mount.pdxfs.M3-001`, unchanged from the
design doc's own scoping.

## 6. `KIND_VOLUME` op-catalog gap (flagged for main)

`caps.decl` documents this in full; summarized here for visibility.
`design/tooling/volume-tooling-ux.md` §4.2 phrases this tool's required
`KIND_VOLUME` rights as "mount+query". The landed
`src/kernel/core/cap/kind_volume.pdx` op catalog has ten ordinals:
`VOL_OP_QUERY_DEVICE_SLOT`(0) through `VOL_OP_QUERY_SIG_KEY_SLOT`(8)
plus `VOL_OP_DEBUG_PRINT`(9) (`VOL_OP_MAX = 9`) — there is **no**
`VOL_OP_MOUNT` ordinal among them. Unlike `mkfs.pdxfs`'s
`KIND_BLOCK_DEVICE` gap (a whole kind missing under the design doc's
placeholder name) and `libpdx-volume`'s `KIND_PDXFS_MOUNT_TABLE`
row-shape gap (both flagged in those repos' own architecture docs),
this is a narrower, single-op gap: the KIND itself, and every other
kind this tool declares, already exists at the exact ordinal the design
doc expects. "Mount+query" most plausibly describes the RIGHTS band a
mount operation needs (`R_VOL_READ | R_VOL_INVOKE` at minimum, per
`kind_volume.pdx`'s `R_VOL_*` constants) rather than a specific
cap-invoke op — the actual attach action is expected to arrive via a
dedicated `sys_mount` syscall (not yet landed; owned by this design
doc's companion osarch half) taking a `KIND_VOLUME` cap slot as a plain
argument, not via a `KIND_VOLUME.cap_invoke` call. **Confirm with
osarch before `mount.pdxfs.M2-001`** implements a real
`vol_kind_narrow` + `sys_mount` call pair.

## 7. Register-preservation discipline (a correctness note, not upstream-sourced)

Every public entry point in this repo that repurposes a SysV
callee-save register (`rbx`, `r12`-`r15`) for cross-syscall or
cross-nested-call state explicitly `push`es it on entry and `pop`s it
(in reverse order) immediately before its `ret` — `Argv::argv_parse` (5
registers) and `MountRecord::mount_record_emit_dry_run` (3 registers)
both do this, matching `mkfs.pdxfs`'s own discipline (itself matching
`libpdx-audit`'s `audit_send_record`). Every pure-leaf helper in this
repo (`argv_streq`, `mount_record_strlen`, `elevate_needed`) touches
only caller-save registers and needs no push/pop.

## 8. What M1 explicitly does not do

Called out here so a reader of M1 code does not mistake absence for
bug:

- No real volume-cap resolution or narrowing — `argv_parse` only holds
  the raw argv pointer to `<volume-cap>`'s URI string (§3, §6).
- No `sys_mount` call, no mount-table row append — all `mount.pdxfs.M2`.
- No mount-point-class table, no `libpdx-elevate` call — `elevate.pdx`
  is a permissive stub (§5) — all `mount.pdxfs.M3-001`.
- No `libpdx-audit` journaling, no INTENT/RESULT record pair — M1's
  `--dry-run` path writes directly to stdout with no audit-first gate;
  acceptable at M1 for the same reason `mkfs.pdxfs`'s own architecture
  doc gives — M1 performs no real operation, so there is nothing an
  audit-first gate would be protecting.
- No semantic-pipe binary framing — only the four-field text line (§4)
  — `mount.pdxfs.M3-003`.
- No failure-taxonomy encoding (§4.4 of the upstream design) —
  `mount.pdxfs.M3-004`. M1's only two outcomes are `DRY_RUN` (always,
  on `--dry-run`) and the unconditional `not yet implemented` exit 1
  otherwise; none of `SIG_INVALID` / `ALREADY_MOUNTED` / etc. can occur
  because no code path reaches a real `sys_mount`.
- No `libpdx-volume` link yet. The real volume-cap narrow at
  `mount.pdxfs.M2-001` is this tool's first `libpdx-volume` link.

## 9. What M2/M3 need before they can open

- `mount.pdxfs.M2-001` (volume-cap resolve + narrow) needs the
  `KIND_VOLUME` op-catalog gap (§6) resolved with osarch, and
  `libpdx-volume`'s `vol_kind_narrow` confirmed linkable (real body
  landed as of `libpdx-volume.M2` per that repo's own `caps.decl` —
  validation + passthrough, not a kernel-enforced derivation, since no
  `cap_narrow` primitive exists for `KIND_VOLUME` yet).
- `mount.pdxfs.M2-002` (real `sys_mount` + mount-table row append)
  needs a `sys_mount` syscall to exist kernel-side — not confirmed
  landed as of this M1 landing; confirm with osarch before opening.
- `mount.pdxfs.M3-001` (elevate) needs a `libpdx-elevate` implementation
  to exist — as of this landing it has the same "design-doc-mentioned,
  not yet bootstrapped" status `libpdx-argv` had per §3 above; confirm
  before M3-001 opens whether it should also ship a minimal inline
  fallback (mirroring `mkfs.pdxfs`'s own open question for its
  M3-005).

## 10. M2 landing — volume-cap resolve, sys_mount stub, elevate classifier

M2 (issues #4, #5, #6) replaces M1's `--dry-run`-only / "not yet
implemented" pair in `main.pdx` with the real pipeline: elevate-classify
→ volume-cap resolve+narrow → `sys_mount` attempt (or dry-run skip) →
one unified `PdxFsMountRecord@0.1` emit. Two new files
(`src/volume_cap.pdx`, `src/mount_op.pdx`), one file rewritten in place
(`src/elevate.pdx`, its M1 stub replaced with a real body — same public
signature, so no other file needed an ABI change), one file extended
(`src/mount_record.pdx`), and `main.pdx`'s `_start` rewritten to wire
all four together.

### 10.1 `volume_cap.pdx` — resolve + narrow, two open gaps

`VolumeCap::volume_cap_parse_slot` decodes a `<volume-cap>` URI string
(`cap:volume:0x0042`) into a raw cap-slot number via a hand-rolled
byte-loop hex parser (prefix-match the literal `cap:volume:0x`, then
accumulate hex digits via `shl 4; or`, never `imul`). `VolumeCap::
volume_cap_resolve` composes that with libpdx-volume's `vol_kind_narrow`
(`(cap_slot, requested_ops_mask, out_narrowed_cap_slot) -> u64`, a
real M2-004 body per that repo's own `vol_kind.pdx` — a documented
validate-and-passthrough, not a kernel-enforced derivation, since no
`cap_narrow` primitive exists for `KIND_VOLUME` yet).

Two gaps carried forward from M1, now concretely encountered rather
than merely anticipated:

- **No independent kind check.** This issue's brief asked for a
  `cap_check_kind`-style validation that the slot is actually a
  `KIND_VOLUME` before narrowing it. A monorepo-wide grep for
  `cap_check_kind` / `cap_slot_kind` / any kind-query primitive finds
  nothing — `cap_invoke`'s own per-kind dispatch decodes a slot's kind
  internally but does not expose that decode as a standalone query.
  `volume_cap_resolve` therefore performs no such check; it trusts the
  caller-supplied slot number entirely.
- **`ops_mask` has no real meaning yet.** Per this issue's own
  instruction, `VC_OPS_MOUNT_QUERY = 0x3` (bits 0-1) stands in for
  "VOL_MOUNT|VOL_QUERY" — but the landed `KIND_VOLUME` op catalog
  (§6 above) has no `VOL_OP_MOUNT` ordinal, so bits 0-1 just happen to
  land on `VOL_OP_QUERY_DEVICE_SLOT`/`VOL_OP_QUERY_MOUNT_SLOT`. The mask
  passes `vol_kind_narrow`'s own gate (`VK_OPS_VALID_MASK = 0x3FF`) but
  carries no enforced semantics beyond that.

libpdx-volume's own README lists `mount.pdxfs` under "declared but not
yet linked" for `vol_kind_mint`/`vol_kind_narrow`/`mount_table_snapshot`
— `volume_cap.pdx` calls `vol_kind_narrow` by bare symbol,
matching this repo's own intra-file call convention, but neither this
repo's `tools/build.sh` (confirmed, by reading it, to compile each
`src/*.pdx` file to its own standalone `.o` with no link step at all)
nor any other script performs the actual cross-repo link. That edge is
still open.

### 10.2 `mount_op.pdx` — a documented stub, not a working syscall

Per this issue's own instruction ("if [sys_mount] can already accept a
KIND_VOLUME cap slot + mount-point path, wire against that; if not,
STUB the invocation ... and flag the kernel gap"), `mount_op.pdx`'s own
file header documents THREE independent kernel-side gaps found by
reading the live kernel source, each with an exact citation:

1. **`sys_mount` (sysno 75) is dispatch-unwired.** The live dispatch
   table (`src/kernel/core/syscall/dispatch.pdx` L506-509) routes sysno
   75 to a label `dispatch_mount` (L1975) that is STILL an
   unconditional `mov rax, 0xFFFFFFFFFFFFFFDA (-ENOSYS); ret` — it reads
   no argument register at all. This is despite `sys_mount_body` /
   `sys_mount_shim` (`sys_mount.pdx`) already being a complete, real,
   audit-emitting implementation; the dispatch-table wiring connecting
   the two (the same shape `dispatch_open` / `dispatch_blkdev_cap_
   request` already use for their own shims) was simply never landed.
   A ring-3 caller cannot reach `sys_mount_body` through any syscall
   today.
2. **Two incompatible target ABIs for the same sysno.** `dispatch.pdx`'s
   own forward-declaration comment (L1951-1962) documents an
   ASPIRATIONAL cap-slot-based contract for sysno 75 (`a0=volume_cap_
   slot, a1=mountpoint_path_va, a2=flags, a3=fstype`) — the shape
   mount.pdxfs's own design targets. But `sys_mount_body`'s REAL,
   already-landed signature (`dev_path_ptr, dev_path_len, mount_point_
   ptr, mount_point_len, backend_id`) takes a raw device-path STRING,
   not a cap slot, and has no code path that reads one. Confirming
   which ABI sysno 75 should actually grow into is now the concrete,
   sourced version of the "confirm with osarch" flag M1's own §6/§9
   already raised.
3. **`KIND_PDXFS_MOUNT_TABLE` has no working `APPEND_ROW`.**
   `kind_pdxfs_mount_table.pdx`'s cap-invoke handler refuses every op
   (including the reserved `PMT_OP_APPEND_ROW = 2`) with
   `INVOKE_UNSUPPORTED`. Compounding this, no `_init_caps`-style
   convention anywhere in the codebase seeds a standalone, one-shot
   CLI tool (as opposed to a long-running IPC server, the only
   precedent found) with a cap slot for this kind.

Given (1) alone, `mount_op_invoke`'s real (non-`--dry-run`) branch
issues its syscall using the ABI from gap (2)'s documented contract,
receives `-ENOSYS` today, and classifies the return via a generous
"plausible mount_id" ceiling (< 65536) rather than matching a specific
errno bit pattern — deliberately, since gap (2) means the eventual real
failure mode may not even be `-ENOSYS`. Every non-dry-run invocation
therefore reports `MOUNT_OP_ERR_KERNEL` today; this is the correct,
documented M2 landing behaviour. `mount_op_append_row`'s `cap_invoke`
call (gap 3) is issued against a hardcoded, explicitly-flagged
placeholder cap slot and its result is discarded — best-effort, the
same posture every `audit_emit` call site in the kernel already takes
toward its own side-channel record.

### 10.3 `elevate.pdx` — a real classifier, narrower than §4.2's own table

`Elevate::elevate_needed`'s M1 stub (§5 above) is replaced with a real
three-bucket prefix classifier: `/home/`, `/mnt/`, `/tmp/` →
`ELEVATE_NOT_REQUIRED`; `/system/`, `/boot/`, `/dev/` →
`ELEVATE_REQUIRED`; anything else → a new `ELEVATE_INVALID`. This is
this issue's own (M2-003) scope, and it is deliberately NARROWER than
§4.2's real five-class table in two ways, both flagged in the file's
own header for M3-001 to close: every `/home/**` path is treated as
never-elevate (§4.2 only exempts the invoker's OWN subtree — this tool
has no `KIND_USER` identity lookup yet to tell `/home/alice/` from
`/home/bob/`), and there is no founder-only-elevate bucket at all
(§4.2's own unmatched default) — `ELEVATE_INVALID` is a refusal
instead. `main.pdx` treats `ELEVATE_REQUIRED` as a hard stop
(`result_code: ELEVATION_REQUIRED`, exit 4) and folds `ELEVATE_INVALID`
into the same `KERNEL_ERROR` bucket (§10.2) uses (exit 3).

### 10.4 `mount_record.pdx` — one unified emitter

`MountRecord::mount_record_emit_result(volume_cap_ptr, mount_point_ptr,
flags, result_code, mount_id)` replaces M1's dry-run-only call site in
`main.pdx` (the old `mount_record_emit_dry_run` is kept, unmodified, as
a still-valid standalone M1 shape — nothing in this repo requires
removing it). Four `MR_RESULT_*` codes (`DRY_RUN`, `OK`,
`ELEVATION_REQUIRED`, `KERNEL_ERROR`) select one of four label strings
at segment 8; `mount_id` prints only on `MR_RESULT_OK`. A shared
`mount_record_print_decimal` leaf, factored out of the old inline
digit-conversion loop byte-for-byte, backs both the `flags` field
(present since M1) and the new `mount_id` field so the div-by-10 loop
exists exactly once in this file.

## 11. M3 landing — real classifier + elevate stub, audit-first, semantic-pipe deferral, failure taxonomy

M3 (issues #7, #8, #9, #10) replaces M2's narrow three-bucket elevate
classifier and single `KERNEL_ERROR` catch-all with a real four-class
`§4.2` mount-point table (still fail-closed at the broker hop), a real
libpdx-audit INTENT/RESULT wrap sharing one `audit_id`, a documented
semantic-pipe deferral (mirroring mkfs.pdxfs's own M3-003 finding
byte-for-byte), and an eleven-code failure taxonomy sourced directly
from `sys_mount.pdx`'s real errno set. Two new files (`src/audit_wire.
pdx`, `src/pipe_wire.pdx`), three files extended in place (`src/
elevate.pdx`, `src/mount_record.pdx`, `src/mount_op.pdx`), and `src/
main.pdx`'s `_start` rewritten to wire all six modules together.

### 11.1 `elevate.pdx` — real four-class table, fail-closed libpdx-elevate stub

`Elevate::mount_point_class(mount_point_ptr) -> u64` replaces main.pdx's
M2 call site to `elevate_needed` (kept, unmodified, no remaining
caller) with a §4.2-matching four-value vocabulary: `MPC_USER_SUBTREE`
(0), `MPC_SYSTEM_PATH` (1), `MPC_CROSS_USER` (2, defined but never
actually produced — see below), `MPC_INVALID` (3). The body is
byte-for-byte the same three-prefix-group logic `elevate_needed`
already had; only the return-value NAMES changed to this issue's own
class vocabulary, so `MPC_SYSTEM_PATH` and `MPC_CROSS_USER` can be
treated identically by main.pdx's dispatch (both "need elevate") even
though this landing's classifier structurally cannot yet tell them
apart — doing so needs the invoker's own `KIND_USER` identity, which
this tool has never had at any landing (M2-003's own header flagged
this gap for "M3-001 to close"; it remains open).

`Elevate::mount_elev_require_system(mount_point_ptr, mpc_class) -> u64`
is the new libpdx-elevate call site this issue asks for. A full read of
`libpdx-elevate`'s real, mature (v1.1.0-in-progress) source confirms the
identical gap `mkfs.pdxfs`'s own `src/elevate_wire.pdx` (M3-005, #12)
already documented over the SAME library: `ElevateClientAcquire::
elevate_client_acquire` requires a `KIND_IPC_ENDPOINT` cap over
`svc.elevate-broker` at its `mint_ctx_buf.parent_ep_slot` field, a
prerequisite libpdx-elevate's own README says is "declared by whatever
the caller links this library into" — and `caps.decl`'s own
`KIND_ELEVATE_CHANNEL = 0x191` has been a PLACEHOLDER since M1, unchanged
by any landing including this one. `mount_elev_require_system` is
therefore a documented fail-closed stub: `MOUNT_ELEV_DENY` (0)
unconditionally. `MOUNT_ELEV_GRANT` (1) and the GRANT arm of main.pdx's
dispatch are real, wired code kept for the day a broker-endpoint cap
exists.

### 11.2 `audit_wire.pdx` — real INTENT/RESULT pair, one shared audit_id

New file, mirroring `mkfs.pdxfs`'s own `audit_wire.pdx` (M3-004, #11)
shape exactly: `AuditWire::mount_audit_begin(mount_point_ptr, dry_run_
flag) -> audit_id` (real `AuditClient::audit_begin` call, op_name
selected between `"mount.pdxfs.mount"` / `"mount.pdxfs.mount.dry_run"`
by the caller's own flag) and `AuditWire::mount_audit_commit(audit_id,
exit_code) -> ()` (real `AuditClient::audit_commit`, skipped entirely
when `audit_id == 0`). `main.pdx` calls `mount_audit_begin` once, right
after argv parses, BEFORE any dispatch — every terminal branch
therefore gets the same audit wrapping, and every branch's own `call
mount_audit_commit` shares that ONE `audit_id`, which is this issue's
own "shared audit_id" requirement. `audit_commit`'s real signature has
no `parent_audit_id` parameter (that name belongs to a DIFFERENT entry
point, `audit_set_parent`, meant for cross-process parent/child audit
trees, not this issue's INTENT/RESULT pairing) — the shared `audit_id`
itself, round-tripped through `audit_begin` then `audit_commit`, is
libpdx-audit's own real correlation mechanism for exactly this need.

### 11.3 `pipe_wire.pdx` — one wrapper, not two, over the same deferred registry

New file, mirroring `mkfs.pdxfs`'s own `pipe_wire.pdx` (M3-003, #10)
finding over the SAME schema-registry gap (`paideia-os#2000`,
`Registry::bind_by_name` confirmed inert): `PipeWire::mount_pipe_emit_
result` prints one documented deferral header line then delegates all
five arguments to `MountRecord::mount_record_emit_result`. Unlike
mkfs.pdxfs (which still carries two wrappers, a leftover of its own M1/
M2 emitter split), mount.pdxfs's M2 landing had already unified its
record emission into ONE function (`mount_record_emit_result`, dry-run
included as just another `result_code` value) — so this file needs
only ONE wrapper. `main.pdx` calls this one wrapper on every terminal
path; no code path calls `MountRecord::mount_record_emit_result`
directly any more.

### 11.4 `mount_record.pdx` / `mount_op.pdx` — the failure taxonomy

`src/mount_record.pdx` gains eleven new `MR_RESULT_*` codes (4..14) and
a new pure-leaf classifier, `MountRecord::mount_record_classify_mount_
errno(raw_errno) -> u64`. Four codes are policy refusals this repo's
own pipeline already detects (`ELEVATION_STUB`, `INVALID_MOUNT_POINT`,
`BAD_VOLUME_CAP`, `NARROW_FAILED`) — previously all folded into the
single M2 `KERNEL_ERROR` catch-all, now each its own code, wired
directly into `main.pdx`'s own dispatch. Seven more come from `sys_
mount.pdx`'s real, kernel-landed errno set (`grep -n "pub let SYS_
MOUNT_" src/kernel/core/syscall/sys_mount.pdx`, six sentinels
`0xFFFFED60..65`) plus raw `-ENOSYS` — `mount_record_classify_mount_
errno` compares a captured raw syscall return against all seven via
register-staged 64-bit compares (the same imm32-sign-extension trap
`VolumeCap::volume_cap_resolve`'s own `VC_PARSE_ERR` check already
avoids), falling back to the original `KERNEL_ERROR` (3) for anything
unrecognised. `MR_RESULT_AUDIT_FAIL` (15) is reserved, unused by any
M3 call site, mirroring mkfs.pdxfs's own `FR_RESULT_AUDIT_FAIL`.

`src/mount_op.pdx`'s `MountOp::mount_op_invoke` grows a 5th parameter,
`out_raw_errno_ptr`, staged into the newly-pushed callee-save `r15`
(NOT left in the caller-save `r8` it arrives in, since the real-path
`syscall` is subject to the kernel's #743 caller-save-zeroing hardening)
— written `0` on the dry-run/success paths, the raw syscall return
verbatim on `MOUNT_OP_ERR_KERNEL`. Given `dispatch_mount` is still an
unconditional `-ENOSYS` stub (`src/mount_op.pdx`'s own KERNEL GAP #1,
unchanged since M2), `mount_record_classify_mount_errno` observes
exactly ONE real value today — `MR_RESULT_ENOSYS` (14) — for every
non-dry-run invocation; the other six `SYS_MOUNT_*` classification arms
are real, wired code kept ready for the day `dispatch_mount` is wired
for real.

### 11.5 `main.pdx` — six-module dispatch, one shared audit_id, per-cause result codes

`_start`'s register plan reuses `r13` (dead `argv` after `argv_parse`)
to hold the `audit_id` for the rest of the function, the identical
reuse trick `mkfs.pdxfs`'s own M3 `main.pdx` applies to its `r12`.
Every terminal branch (`MPC_INVALID`, the elevate-stub DENY, `VC_ERR_
BAD_URI`, `VC_ERR_NARROW_FAILED`, every `mount_record_classify_mount_
errno` outcome, and both success sub-branches) follows the identical
three-step shape: emit via `pipe_wire.pdx`, commit via `audit_wire.pdx`
sharing the one `audit_id`, `sys_exit` the real status. The M2-era
single shared `mount_main_kernel_error` label is gone entirely —
replaced by one small, distinct block per failure cause, each choosing
its own `MR_RESULT_*` code rather than funnelling through one generic
catch-all.
