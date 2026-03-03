#!/usr/bin/env julia
# ═══════════════════════════════════════════════════════════════════════
# Cleanup leaked POSIX shared memory segments from Tachikoma
#
# Tachikoma's Kitty graphics protocol (t=s) creates shm segments named
# /tach_k{pid}_{counter}.  If a process is killed or the terminal
# doesn't unlink them, they leak permanently.  On macOS there is no
# easy way to list POSIX shm segments — this script probes for them
# by name and unlinks any it finds.
#
# Strategy: for each PID 1..max_pid, probe index 0 and 1.  If either
# exists, scan sequentially upward until `gap` consecutive misses.
# The monotonic counter means indices are dense within a session, so
# a short gap reliably detects the end.
#
# Usage:
#   julia test/cleanup_shm.jl              # default scan
#   julia test/cleanup_shm.jl --dry-run    # report without unlinking
# ═══════════════════════════════════════════════════════════════════════

function cleanup_tach_shm(; max_pid::Int=99999, gap::Int=200, dry_run::Bool=false)
    total = 0
    O_RDONLY = Cint(0x0000)
    t0 = time()

    for pid in 1:max_pid
        # Quick probe: skip PIDs with no segments
        has_any = false
        for probe_idx in (0, 1, 2, 3)
            fd = ccall(:shm_open, Cint, (Cstring, Cint), "/tach_k$(pid)_$(probe_idx)", O_RDONLY)
            if fd >= 0
                ccall(:close, Cint, (Cint,), fd)
                has_any = true
                break
            end
        end
        has_any || continue

        # Scan sequentially until `gap` consecutive misses
        pid_count = 0
        consecutive_misses = 0
        idx = 0
        while consecutive_misses < gap
            name = "/tach_k$(pid)_$(idx)"
            fd = ccall(:shm_open, Cint, (Cstring, Cint), name, O_RDONLY)
            if fd >= 0
                ccall(:close, Cint, (Cint,), fd)
                if !dry_run
                    ccall(:shm_unlink, Cint, (Cstring,), name)
                end
                pid_count += 1
                consecutive_misses = 0
            else
                consecutive_misses += 1
            end
            idx += 1
        end
        if pid_count > 0
            action = dry_run ? "found" : "unlinked"
            println("  PID $(lpad(pid, 5)): $(pid_count) segments $(action) (scanned to idx $(idx - gap))")
            total += pid_count
        end
    end

    # Also check probe segments from _kitty_shm_probe!()
    probe_count = 0
    for pid in 1:max_pid
        name = "/tach_probe_$(pid)"
        fd = ccall(:shm_open, Cint, (Cstring, Cint), name, O_RDONLY)
        if fd >= 0
            ccall(:close, Cint, (Cint,), fd)
            if !dry_run
                ccall(:shm_unlink, Cint, (Cstring,), name)
            end
            probe_count += 1
        end
    end
    if probe_count > 0
        action = dry_run ? "found" : "unlinked"
        println("  Probe segments: $(probe_count) $(action)")
        total += probe_count
    end

    elapsed = time() - t0
    println()
    if total == 0
        println("✓ No leaked Tachikoma shm segments found (scanned PIDs 1–$(max_pid) in $(round(elapsed; digits=1))s)")
    else
        action = dry_run ? "found (dry run — not unlinked)" : "cleaned up"
        println("$(total) segments $(action) in $(round(elapsed; digits=1))s")
    end
    return total
end

# Parse CLI args
dry_run = "--dry-run" in ARGS || "-n" in ARGS
if dry_run
    println("Dry run mode — scanning only, no unlinking\n")
end
cleanup_tach_shm(; dry_run)
