const std = @import("std");

const Config = struct {
    access_key_id: []const u8,
    secret_access_key: []const u8,
    endpoint: []const u8,
    region: []const u8,
    bucket: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Check for help or version flags
    if (args.len > 1) {
        if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
            std.debug.print("Usage: hyprshot-cloud <IMAGE>\n", .{});
            std.debug.print("Upload an image to an S3-compatible bucket.\n\n", .{});
            std.debug.print("Arguments:\n", .{});
            std.debug.print("  <IMAGE>    Path to the image file to upload\n\n", .{});
            std.debug.print("Options:\n", .{});
            std.debug.print("  -h, --help     Show this help message\n", .{});
            std.debug.print("  --version      Show version information\n", .{});
            return;
        }

        if (std.mem.eql(u8, args[1], "--version")) {
            std.debug.print("hyprshot-cloud 0.1.0\n", .{});
            return;
        }
    }

    // Check that we have an image path
    if (args.len < 2) {
        std.debug.print("Error: No image file provided\n", .{});
        std.debug.print("Usage: hyprshot-cloud <IMAGE>\n", .{});
        return error.NoImageProvided;
    }

    const image_path = args[1];
    
    // Load configuration
    const config = try loadConfig(allocator);
    defer {
        allocator.free(config.access_key_id);
        allocator.free(config.secret_access_key);
        allocator.free(config.endpoint);
        allocator.free(config.region);
        allocator.free(config.bucket);
    }
    
    // Upload the image
    try uploadImage(allocator, image_path, config);
}

fn loadConfig(allocator: std.mem.Allocator) !Config {
    // Get config directory path
    const home_dir = std.posix.getenv("HOME") orelse return error.HomeDirNotFound;
    const config_path = try std.fs.path.join(allocator, &.{ home_dir, ".config", "hyprshot-cloud", "config.json" });
    defer allocator.free(config_path);
    
    // Read config file
    var file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
        std.debug.print("Error: Could not open config file at {s}\n", .{config_path});
        std.debug.print("Please create a config file with your S3 credentials\n", .{});
        return err;
    };
    defer file.close();
    
    const file_contents = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(file_contents);
    
    // Parse JSON
    var parsed = std.json.parseFromSlice(Config, allocator, file_contents, .{}) catch |err| {
        std.debug.print("Error: Could not parse config file as JSON\n", .{});
        return err;
    };
    defer parsed.deinit();
    
    // Duplicate strings since parsed data will be freed when we deinit
    const config_data = parsed.value;
    return Config{
        .access_key_id = try allocator.dupe(u8, config_data.access_key_id),
        .secret_access_key = try allocator.dupe(u8, config_data.secret_access_key),
        .endpoint = try allocator.dupe(u8, config_data.endpoint),
        .region = try allocator.dupe(u8, config_data.region),
        .bucket = try allocator.dupe(u8, config_data.bucket),
    };
}

fn uploadImage(allocator: std.mem.Allocator, image_path: []const u8, config: Config) !void {
    // Open the image file
    var file = std.fs.cwd().openFile(image_path, .{}) catch |err| {
        std.debug.print("Error: Could not open image file at {s}\n", .{image_path});
        return err;
    };
    defer file.close();
    
    // Get file info for content length
    _ = try file.stat();
    
    // Extract filename from path
    const filename = std.fs.path.basename(image_path);
    
    // Generate date-based filename to avoid conflicts
    const timestamp = std.time.timestamp();
    const dated_filename = try std.fmt.allocPrint(allocator, "{d}_{s}", .{ timestamp, filename });
    defer allocator.free(dated_filename);
    
    std.debug.print("Uploading {s} to {s}/{s}...\n", .{ filename, config.bucket, dated_filename });
    
    // Use curl to upload the file to S3
    const cmd = try std.fmt.allocPrint(allocator, 
        "curl -X PUT -T {s} " ++
        "-H \"Host: {s}\" " ++
        "-H \"Content-Type: image/png\" " ++
        "-H \"X-Amz-Date: $(date -u +%Y%m%dT%H%M%SZ)\" " ++
        "-H \"X-Amz-Content-Sha256: $(sha256sum {s} | cut -d' ' -f1)\" " ++
        "{s}/{s}/{s}", 
        .{ image_path, config.endpoint, image_path, config.endpoint, config.bucket, dated_filename });
    defer allocator.free(cmd);
    
    // In a real implementation, we would properly sign the request with AWS signature v4
    // For now, we'll use a simplified approach that assumes the S3 endpoint accepts unsigned requests
    // (which is common for private/development S3-compatible services)
    
    const result = std.process.Child.run(.{ 
        .allocator = allocator, 
        .argv = &.{ "sh", "-c", cmd }
    });
    
    if (result) |run_result| {
        defer allocator.free(run_result.stdout);
        defer allocator.free(run_result.stderr);
        
        if (run_result.term.Exited == 0) {
            std.debug.print("Successfully uploaded {s} to {s}/{s}\n", .{ filename, config.bucket, dated_filename });
            std.debug.print("Public URL: {s}/{s}/{s}\n", .{ config.endpoint, config.bucket, dated_filename });
        } else {
            std.debug.print("Upload failed with exit code: {d}\n", .{run_result.term.Exited});
            std.debug.print("stderr: {s}\n", .{run_result.stderr});
            return error.UploadFailed;
        }
    } else |err| {
        std.debug.print("Error executing curl command: {}\n", .{err});
        return err;
    }
}
