# mount.pdxfs v1.0.0 — release note + mirror-push workflow (M5-001/M5-002)

**Repo:** github.com/paideia-os/mount.pdxfs
**Wave:** R53 volume tooling
**Version at first release:** 1.0.0
**Upstream policy:** `design/tooling/plan.md` §6.3 (paideia-os) — package
repository layout; `design/02-development-environment.md` §1140 + §1164
(paideia-os) — hybrid Ed25519+ML-DSA-65 signing, release-line key
custody; `design/tooling/volume-tooling-ux.md` §9.3 (paideia-os) —
M5-001/M5-002 scope.

This document is both the **release note** for what v1.0.0 ships and
the operator runbook for cutting the signed release and pushing it to
the paideia-os package mirror at
`https://pkgs.paideia-os/main/mount.pdxfs/1.0.0/`. The workflow mirrors
`libpdx-volume`'s own `release/RELEASE-1.0.0.md` (this wave's other
satellite repo, first through M5) and `mkfs.pdxfs`'s own M3 landing
posture — see those for the worked templates this one follows.

The actual `git tag v1.0.0` + `git push` is a **manual step main
performs separately from this milestone**. This document describes
exactly what that tag would contain so a future operator (or main,
later) can cut it without re-deriving scope from STATUS.md and five
milestones of design-doc flags.

---

## 1. What v1.0.0 ships

Everything landed at M1..M4 (see `CHANGELOG.md` for the itemised list,
`STATUS.md` for the per-issue checklist):

- **`Argv::argv_parse`** — the long-flag CLI surface (`--ro`,
  `--noexec`, `--verbose`, `--dry-run`, `<volume-cap>`, `<mount-point>`).
- **`VolumeCap::volume_cap_resolve`** — `cap:volume:0xNN` URI parse +
  narrow via `libpdx-volume.vol_kind_narrow` (validate-and-passthrough,
  not a kernel-enforced derivation).
- **`Elevate::mount_point_class`** — the real §4.2 four-class
  mount-point table (`MPC_USER_SUBTREE` / `MPC_SYSTEM_PATH` /
  `MPC_CROSS_USER`, unreachable / `MPC_INVALID`).
- **`Elevate::mount_elev_require_system`** — a documented fail-closed
  `libpdx-elevate` call site; always `MOUNT_ELEV_DENY` at this release
  (no broker-endpoint cap provisioned — see §2 below).
- **`MountOp::mount_op_invoke`** — the designed cap-slot-ABI `sys_mount`
  call, a documented stub given the kernel's `dispatch_mount` is still
  unwired (`-ENOSYS`).
- **`AuditWire::mount_audit_begin` / `mount_audit_commit`** — real
  `libpdx-audit` INTENT/RESULT record pair, one shared `audit_id` per
  invocation.
- **`PipeWire::mount_pipe_emit_result`** — the semantic-pipe emit,
  documented deferral fallback (line-based rendering + header) pending
  `libpdx-schema-registry`.
- **`MountRecord::mount_record_emit_result` /
  `mount_record_classify_mount_errno`** — the full fifteen-code
  `MR_RESULT_*` failure taxonomy.
- **Four test drivers** (`tests/test_happy_mnt.pdx`,
  `tests/test_elevate_system.pdx`, `tests/test_failure_matrix.pdx`,
  `tests/test_elevate_timeout.pdx`) exercising every real (non-stub)
  body above through the pipeline-replay convention `tests/README.md`
  documents.
- **`doc/mount.pdxfs.pdxdoc`** — the source-form user-facing
  documentation this milestone adds.

## 2. What v1.0.0 explicitly does NOT ship (deferred)

Consumers relying on this tool at v1.0.0 must know these gaps are real
and by design, not oversights:

- **A real, end-to-end `sys_mount`.** `dispatch_mount` (sysno 75) is
  still an unconditional `-ENOSYS` stub kernel-side
  (`src/mount_op.pdx`'s own KERNEL GAP #1); even once wired, its real
  ABI does not accept a `KIND_VOLUME` cap slot (KERNEL GAP #2) —
  confirm with osarch which ABI sysno 75 should grow into.
- **`KIND_PDXFS_MOUNT_TABLE` row append.** `PMT_OP_APPEND_ROW` is a
  reserved-but-refused ordinal kernel-side.
- **A real `libpdx-elevate` dispatch.** No `KIND_ELEVATE_CHANNEL`
  broker-endpoint cap is provisioned; `mount_elev_require_system`
  always denies. `libpdx-elevate` itself is real and mature — the gap
  is entirely on this repo's side (no cap to acquire from).
- **A real `libpdx-semantic-pipe` bind.** Blocked on
  `paideia-os#2000` (`svc.schema-registry` standing up); every record
  stays the line-based fallback.
- **Cross-user `/home/**` distinction.** No `KIND_USER` identity lookup
  exists; `MPC_CROSS_USER` is a defined but unreachable classification.
- **Dual-signed `manifest.pdxsig` + mirror push** — see §3/§4 below;
  this is the one item this milestone (M5-001/M5-002) lands the *source
  form* and *documentation* of but does not execute.

## 3. Substrate readiness (blocking the actual signed release)

**S1 — paideia-as toolchain ≥ 0.21.0 reachable.** The release build
invokes `paideia-as build` to compile `src/*.pdx` and `tests/*.pdx`, and
`paideia-pq-sign::sign_release_artifact` for the dual-signature step.
STATUS.md tracks the toolchain version this repo is tested against.

**S2 — `pkgs.paideia-os` mirror endpoint reachable.** Does not exist as
of this landing — same status every other satellite repo's own runbook
documents. Until it stands, the release is "cut but not mirrored" — the
signed `manifest.pdxsig` still lands in the GitHub release attachment
set for out-of-band consumers.

**S3 — a live ML-DSA-65 release-line seed key.** `manifest.pdxsig` is
left with the `SIGNATURE_PLACEHOLDER_PENDING_LIVE_SIGN` sentinel in
every signature slot precisely because that key material is
release-line custody (hardware-backed TPM 2.0 / cloud KMS per
`design/02-development-environment.md` §1164), never repo-resident.

**S4 — `doc` M2 reachable.** The compiled `.pdxdoc` at
`/pkgs/mount.pdxfs-1.0.0/doc/mount.pdxfs.pdxdoc` is produced by the
`doc compile` subcommand of the `doc` tool at doc.M2 (not landed as of
this milestone). The source form at `doc/mount.pdxfs.pdxdoc` in this
repo is the input; consumers render it verbatim until then.

**S5 — a `KIND_ELEVATE_CHANNEL` broker-endpoint cap for this tool.**
Not a build-time substrate gap, but a real functional one: v1.0.0 ships
with `mount_elev_require_system` permanently denying every elevate-
required mount until this is provisioned — see §2.

---

## 4. Cut-a-release procedure

Identical shape to `libpdx-volume`'s / `libpdx-audit`'s runbooks (same
tooling, same release-line key custody). Reproduced here with this
repo's own artifact names.

**Pre-flight.**

    git fetch origin
    git switch main
    git pull --ff-only
    git status                    # MUST be clean
    gh issue list --milestone M5 --state open --repo paideia-os/mount.pdxfs
                                  # MUST be empty

**Step 1 — Version bump + CHANGELOG close.** Already done at M5-001 —
`CHANGELOG.md`'s `## 1.0.0` entry is the one a future tag points at.

**Step 2 — Tag.** (Manual, main-performed; NOT run as part of this
milestone.)

    git tag -a v1.0.0 -m "mount.pdxfs v1.0.0 — R53 M1..M5 close"
    git push origin v1.0.0

**Step 3 — Build the compiled artifact set.**

    paideia-as build src/argv.pdx          -o build/mount.pdxfs.o
    paideia-as build src/elevate.pdx       -o build/mount.pdxfs.o
    paideia-as build src/volume_cap.pdx    -o build/mount.pdxfs.o
    paideia-as build src/mount_op.pdx      -o build/mount.pdxfs.o
    paideia-as build src/mount_record.pdx  -o build/mount.pdxfs.o
    paideia-as build src/audit_wire.pdx    -o build/mount.pdxfs.o
    paideia-as build src/pipe_wire.pdx     -o build/mount.pdxfs.o
    paideia-as build src/main.pdx          -o build/mount.pdxfs.o
    paideia-as link  build/mount.pdxfs.o \
        --with libpdx-volume --with libpdx-audit --with libpdx-elevate \
        -o build/mount.pdxfs
    doc compile       doc/mount.pdxfs.pdxdoc -o build/mount.pdxfs.pdxdoc

**Step 4 — Recompute the manifest.**

    paideia-release fill-manifest \
        --source release/manifest.pdxsig.txt \
        --tree   . \
        --tag    v1.0.0 \
        --output build/manifest.pdxsig.filled.txt

**Step 5 — Dual-sign.**

    paideia-release sign \
        --manifest build/manifest.pdxsig.filled.txt \
        --key-ed25519  release-line-ed25519.sk \
        --key-ml-dsa65 release-line-ml-dsa-65.sk \
        --output   build/manifest.pdxsig

**Step 6 — Mirror push (M5-002).**

    paideia-release mirror-push \
        --repo   https://pkgs.paideia-os/main/ \
        --pkg    mount.pdxfs \
        --version 1.0.0 \
        --files  build/mount.pdxfs \
                 build/mount.pdxfs.pdxdoc \
                 caps.decl \
                 build/manifest.pdxsig

Expected mirror layout after push:

    /pkgs/mount.pdxfs-1.0.0/
        bin/mount.pdxfs
        doc/mount.pdxfs.pdxdoc
        caps.decl
        manifest.pdxsig

**Step 7 — Update `index.pdxsig`.** Atomic as part of Step 6, per
`libpdx-audit`'s / `libpdx-volume`'s own runbooks.

**Step 8 — GitHub release.**

    gh release create v1.0.0 \
        --title "mount.pdxfs v1.0.0" \
        --notes-file CHANGELOG.md \
        build/manifest.pdxsig \
        build/mount.pdxfs \
        build/mount.pdxfs.pdxdoc \
        caps.decl

---

## 5. Distribution (M5-002) — NOT PERFORMED at this milestone

Per §3 S2 above, `pkgs.paideia-os` does not exist as a reachable mirror
endpoint as of this landing. This milestone lands the documentation and
runbook (§4 above) a future operator needs to execute the push once the
mirror stands and S1/S3 also go green — it does NOT perform any actual
network push, `git tag`, or signing operation. No code in this repo
attempts to reach `pkgs.paideia-os` at build or runtime; `tools/
build.sh` remains the single-file-compile, no-link, no-network gate it
has been since M1.

## 6. Consumers who can rely on this release today

No standalone tool or shell integration in this org links `mount.pdxfs`
as a library — it is a terminal CLI, invoked directly. A consumer
(a shell, an install script, or a human operator) invoking the compiled
binary at v1.0.0 can rely on:

- `--dry-run` never touching the kernel and always printing a real
  four-field preview.
- Every terminal outcome (dry-run, success, every failure-taxonomy
  code) being wrapped in one shared `libpdx-audit` `audit_id`.
- A `/system/**`/`/boot/**`/`/dev/**` mount point always refusing with
  `result_code: ELEVATION_STUB`, never silently proceeding.

A consumer must NOT rely on:

- A real mount ever actually completing — every non-dry-run,
  non-elevate-gated invocation observes `result_code: ENOSYS` today
  (§2 above).
- `mount_elev_require_system` ever returning `MOUNT_ELEV_GRANT` — it is
  fail-closed by construction until a broker-endpoint cap exists.
- The emitted `PdxFsMountRecord@0.1` line being framed as a real
  semantic-pipe wire record — it is line-based text, preceded by a
  documented deferral header.

## 7. Verification (consumer side)

    pkg install mount.pdxfs --verify-only     # dry run, no install
    pkg keys show paideia-release-line         # inspect the signer

AND-semantics per the hybrid scheme: both Ed25519 and ML-DSA-65 MUST
verify; either failure REJECTS the package. Not runnable until the
placeholder signature block in `manifest.pdxsig` is replaced by a real
dual-sign pass per §3/§4 above.

---

## 8. What lands at M5-001/M5-002 (this milestone)

Repo-side, this milestone lands the source form of the release:

- `CHANGELOG.md` — v1.0.0 entry summarising M1..M5.
- `doc/mount.pdxfs.pdxdoc` — source-form `.pdxdoc` for `doc mount.pdxfs`.
- `release/manifest.pdxsig.txt` — release manifest source form, every
  hash and every signature slot a documented placeholder.
- `release/RELEASE-1.0.0.md` — this document.
- `STATUS.md` — M5-001/M5-002 marked landed.

**Not performed at this milestone:** the git tag itself (main's manual
step, once this landing is reviewed), the actual `paideia-as build` +
link compile pass, the dual-sign pass (no live seed key in this repo —
see §3 S3 above), and the mirror push (mirror endpoint does not exist
yet — §3 S2 above, §5 above).
