const std = @import("std");

pub const io_mode = .evented;

pub fn main() !void {
    var cpu: u64 = try std.Thread.getCpuCount();

    std.debug.print("CPUS online... {d} \n", .{cpu});

    // Allocate room for an async frame for every
    // logical cpu core
    var promises =
        try std.heap.page_allocator.alloc(@Frame(worker), cpu);
    defer std.heap.page_allocator.free(promises);

    // Start a worker on every cpu
    var completion_token: bool = false;
    while (cpu > 0) : (cpu -= 1) {
        promises[cpu - 1] =
            async worker(cpu, &completion_token);
    }

    std.debug.print("Working...\n", .{});

    // Wait for a worker to find the solution
    for (promises) |*future| {
        var result = await future;
        if (result != 0) {
            std.debug.print("The answer is {x}\n", .{result});
        }
    }
}

fn worker(seed: u64, completion_token: *bool) u64 {
    // Inform the event loop we're cpu bound.
    // This effectively puts a worker on every logical core.
    std.event.Loop.startCpuBoundOperation();

    // Seed the random number generator so each worker
    // look at different numbers
    var prng = std.rand.DefaultPrng.init(seed);

    while (true) {
        var attempt = prng.random.int(u64);

        // We're looking for a number whose N lower bits
        // are zero. Feel free to change the constant to
        // make this take a longer or shorter amount of time.
        if (attempt & 0xffffff == 0) {
            // Tell other workers we're done
            @atomicStore(bool, completion_token, true, std.builtin.AtomicOrder.Release);
            std.debug.print("I found the answer!\n", .{});
            return attempt;
        }

        // Check if another worker has solved it, in which
        // case we stop working on the problem.
        if (@atomicLoad(bool, completion_token, std.builtin.AtomicOrder.Acquire)) {
            std.debug.print("Another worker won\n", .{});
            break;
        }
    }

    return 0;
}
