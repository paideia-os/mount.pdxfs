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
  stub that unconditionally returns "not required" (see §5 below).
  `mkfs.pdxfs` has no direct analogue to this file (its own elevate
  concern is scoped to M3-005 with no M1 placeholder file) — this
  repo's task brief explicitly asks for the placeholder to exist from
  M1 so the M3-001 call site has somewhere to land without an ABI
  change to `main.pdx`.

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
