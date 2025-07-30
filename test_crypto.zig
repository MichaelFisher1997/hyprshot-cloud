const std = @import("std");

pub fn main() !void {
    std.debug.print("Testing crypto functions\n", .{});
    
    // Try to import crypto modules
    if (@hasDecl(std, "crypto")) {
        std.debug.print("std.crypto is available\n", .{});
        
        // Check for HMAC-SHA256 specifically
        if (@hasDecl(std.crypto.auth, "hmac")) {
            std.debug.print("std.crypto.auth.hmac is available\n", .{});
            
            // Check for SHA256
            if (@hasDecl(std.crypto.auth.hmac, "sha256")) {
                std.debug.print("std.crypto.auth.hmac.sha256 is available\n", .{});
            }
        }
    } else {
        std.debug.print("std.crypto is not available\n", .{});
    }
}
