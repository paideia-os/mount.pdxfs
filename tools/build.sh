#!/usr/bin/env bash
# Per-repo build script. Runs paideia-as build over every .pdx source, then
# links the resulting objects into build-out/mount.pdxfs.elf via link.ld
# (paideia-os#1976/#1977 satellite-tool ELF-linking phase).
#
# Resolves paideia-as via (in order):
#   1. $PAIDEIA_AS env var
#   2. paideia-os checkout sibling to this repo: ../paideia-os/tools/paideia-as/target/release/paideia-as
#   3. $HOME/Development/PaideiaOS/tools/paideia-as/target/release/paideia-as
#   4. paideia-as on $PATH (must be >= 0.21.0)
#
# Requires paideia-as >= 0.21.0. The 0.9.0 shipped in $PATH by default does not
# accept the syntax used in this repo.
#
# Linking: once every src/*.pdx compiles cleanly, the resulting objects
# (NOT the build-out/tests-*.o scaffolding, which is unit-test-only and
# never part of the linked binary) are linked with GNU ld against link.ld
# into build-out/mount.pdxfs.elf, mirroring paideia-os's own
# tools/build-user.sh convention (`ld -nostdlib --warn-common
# --fatal-warnings -T <script> -o <out> <objects>`). Pass one or more
# repeatable --extra-obj-dir DIR flags to fold in additional .o files
# built out-of-tree (e.g. a libpdx-* support object); each DIR is globbed
# for "*.o" at link time -- a DIR that does not exist or has no .o files
# contributes nothing and is NOT an error. Linking runs whenever
# compilation succeeded and produced at least one object, independent of
# whether any --extra-obj-dir was given.
#
# Usage: tools/build.sh [--extra-obj-dir DIR]...

set -euo pipefail
cd "$(dirname "$0")/.."

EXTRA_OBJECTS=()
OWN_OBJECTS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --extra-obj-dir)
            [ "$#" -ge 2 ] || { echo "[build] FAIL: --extra-obj-dir requires an argument" >&2; exit 2; }
            EXTRA_OBJ_DIR="$2"
            shopt -s nullglob
            for extra_obj in "$EXTRA_OBJ_DIR"/*.o; do
                [ -f "$extra_obj" ] || continue
                EXTRA_OBJECTS+=("$extra_obj")
            done
            shopt -u nullglob
            shift 2
            ;;
        *)
            echo "[build] FAIL: unrecognized argument: $1" >&2
            exit 2
            ;;
    esac
done

MIN_VERSION="0.21.0"

resolve_paideia_as() {
    if [ -n "${PAIDEIA_AS:-}" ] && [ -x "$PAIDEIA_AS" ]; then
        echo "$PAIDEIA_AS"; return
    fi
    for cand in \
        "../paideia-os/tools/paideia-as/target/release/paideia-as" \
        "$HOME/Development/PaideiaOS/tools/paideia-as/target/release/paideia-as"
    do
        if [ -x "$cand" ]; then
            echo "$cand"; return
        fi
    done
    if command -v paideia-as >/dev/null 2>&1; then
        command -v paideia-as; return
    fi
    return 1
}

version_ge() {
    # $1 = have, $2 = want ; returns 0 if have >= want
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

PA="$(resolve_paideia_as || true)"
if [ -z "$PA" ]; then
    echo "[build] FAIL: paideia-as not found. Set PAIDEIA_AS or clone paideia-os as a sibling." >&2
    exit 2
fi
VER="$("$PA" --version | awk '{print $2}')"
if ! version_ge "$VER" "$MIN_VERSION"; then
    echo "[build] FAIL: paideia-as $VER is too old, need >= $MIN_VERSION (found $PA)" >&2
    exit 2
fi
echo "[build] paideia-as $VER at $PA"

BUILD_DIR="build-out"
mkdir -p "$BUILD_DIR"

FAIL=0
COUNT=0
for pdx in src/*.pdx; do
    [ -f "$pdx" ] || continue
    COUNT=$((COUNT + 1))
    obj="$BUILD_DIR/$(basename "$pdx" .pdx).o"
    if ! "$PA" build --emit elf64 "$pdx" -o "$obj" 2>&1; then
        FAIL=$((FAIL + 1))
    else
        OWN_OBJECTS+=("$obj")
    fi
done

if [ -d tests ]; then
    for pdx in tests/*.pdx; do
        [ -f "$pdx" ] || continue
        COUNT=$((COUNT + 1))
        obj="$BUILD_DIR/tests-$(basename "$pdx" .pdx).o"
        if ! "$PA" build --emit elf64 "$pdx" -o "$obj" 2>&1; then
            FAIL=$((FAIL + 1))
        fi
    done
fi

echo "[build] $COUNT source(s), $FAIL failure(s)"
[ "$FAIL" -eq 0 ] || exit 1
echo "[build] OK"

if [ "$FAIL" -eq 0 ] && [ "${#OWN_OBJECTS[@]}" -gt 0 ]; then
    echo "[link] ld -T link.ld -> $BUILD_DIR/mount.pdxfs.elf"
    ld -nostdlib --warn-common --fatal-warnings \
        -T link.ld \
        -o "$BUILD_DIR/mount.pdxfs.elf" \
        "${OWN_OBJECTS[@]}" "${EXTRA_OBJECTS[@]}"
    echo "[link] OK -> $BUILD_DIR/mount.pdxfs.elf"

    if command -v objcopy >/dev/null 2>&1; then
        objcopy -O binary "$BUILD_DIR/mount.pdxfs.elf" "$BUILD_DIR/mount.pdxfs.bin"
        echo "[link] OK -> $BUILD_DIR/mount.pdxfs.bin"
    fi
fi
