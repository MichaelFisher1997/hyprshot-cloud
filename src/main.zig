const std = @import("std");
const crypto = std.crypto;
const list_buckets = @import("list_buckets.zig");
const list_objects = @import("list_objects.zig");
const create_bucket = @import("create_bucket.zig");
const delete_bucket = @import("delete_bucket.zig");
const delete_object = @import("delete_object.zig");

pub const Config = struct {
    access_key_id: []const u8,
    secret_access_key: []const u8,
    endpoint: []const u8,
    region: []const u8,
};

/// Format timestamp as YYYYMMDD
pub fn formatDate(allocator: std.mem.Allocator, timestamp: i64) ![]u8 {
    const date = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const year_day = date.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const year = year_day.year;
    const month = month_day.month.numeric();
    const day = month_day.day_index + 1; // day_index is 0-based, so add 1
    
    return std.fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}", .{ year, month, day });
}

/// Format timestamp as ISO 8601 format for x-amz-date header
pub fn formatAmzDate(allocator: std.mem.Allocator, timestamp: i64) ![]u8 {
    const date = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const year_day = date.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const year = year_day.year;
    const month = month_day.month.numeric();
    const day = month_day.day_index + 1; // day_index is 0-based, so add 1
    const time = date.getDaySeconds();
    const hour = time.getHoursIntoDay();
    const minute = time.getMinutesIntoHour();
    const second = time.getSecondsIntoMinute();
    
    return std.fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z", .{ year, month, day, hour, minute, second });
}

/// Calculate SHA256 hash of payload
pub fn hashPayload(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var hash: [crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(data, &hash, .{});
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hash)});
}

/// Derive signing key for AWS Signature V4
pub fn deriveSigningKey(allocator: std.mem.Allocator, key: []const u8, date_stamp: []const u8, region_name: []const u8, service_name: []const u8) ![]u8 {
    // kSecret = "AWS4" + secret access key
    const k_secret = try std.fmt.allocPrint(allocator, "AWS4{s}", .{key});
    defer allocator.free(k_secret);

    // kDate = HMAC-SHA256(kSecret, date)
    var k_date: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    crypto.auth.hmac.sha2.HmacSha256.create(&k_date, date_stamp, k_secret);

    // kRegion = HMAC-SHA256(kDate, region)
    var k_region: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    crypto.auth.hmac.sha2.HmacSha256.create(&k_region, region_name, &k_date);

    // kService = HMAC-SHA256(kRegion, service)
    var k_service: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    crypto.auth.hmac.sha2.HmacSha256.create(&k_service, service_name, &k_region);

    // kSigning = HMAC-SHA256(kService, "aws4_request")
    var k_signing: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    crypto.auth.hmac.sha2.HmacSha256.create(&k_signing, "aws4_request", &k_service);

    // Return a copy of the signing key
    const result = try allocator.alloc(u8, k_signing.len);
    std.mem.copyForwards(u8, result, &k_signing);
    return result;
}

/// Create canonical request for AWS Signature V4
pub fn createCanonicalRequest(allocator: std.mem.Allocator, http_method: []const u8, canonical_uri: []const u8, canonical_query_string: []const u8, canonical_headers: []const u8, signed_headers: []const u8, payload_hash: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}\n{s}\n{s}\n{s}\n{s}\n{s}", .{
        http_method,
        canonical_uri,
        canonical_query_string,
        canonical_headers,
        signed_headers,
        payload_hash,
    });
}

/// Create string to sign for AWS Signature V4
pub fn createStringToSign(allocator: std.mem.Allocator, algorithm: []const u8, amz_date: []const u8, credential_scope: []const u8, canonical_request_hash: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}\n{s}\n{s}\n{s}", .{
        algorithm,
        amz_date,
        credential_scope,
        canonical_request_hash,
    });
}

/// Calculate signature for AWS Signature V4
pub fn calculateSignature(allocator: std.mem.Allocator, signing_key: []const u8, string_to_sign: []const u8) ![]u8 {
    var hmac: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    crypto.auth.hmac.sha2.HmacSha256.create(&hmac, string_to_sign, signing_key);
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hmac)});
}

/// Create authorization header for AWS Signature V4
pub fn createAuthorizationHeader(allocator: std.mem.Allocator, access_key: []const u8, credential_scope: []const u8, signed_headers: []const u8, signature: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "AWS4-HMAC-SHA256 Credential={s}/{s}, SignedHeaders={s}, Signature={s}", .{
        access_key,
        credential_scope,
        signed_headers,
        signature,
    });
}

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
            std.debug.print("Usage: hyprshot-cloud [OPTIONS] <COMMAND>\n", .{});
            std.debug.print("A CLI tool for managing S3-compatible buckets.\n\n", .{});
            std.debug.print("Commands:\n", .{});
            std.debug.print("  upload <IMAGE>     Upload an image to a bucket\n", .{});
            std.debug.print("  list-buckets       List all buckets\n", .{});
            std.debug.print("  list-objects       List objects in a bucket\n", .{});
            std.debug.print("  create-bucket      Create a new bucket\n", .{});
            std.debug.print("  delete-bucket      Delete a bucket\n", .{});
            std.debug.print("  delete-object      Delete an object from a bucket\n\n", .{});
            std.debug.print("Options:\n", .{});
            std.debug.print("  -h, --help         Show this help message\n", .{});
            std.debug.print("  --version          Show version information\n", .{});
            std.debug.print("\nUse 'hyprshot-cloud <COMMAND> --help' for more information about a command.\n", .{});
            return;
        }

        if (std.mem.eql(u8, args[1], "--version")) {
            std.debug.print("hyprshot-cloud 0.1.0\n", .{});
            return;
        }
    }

    // Check that we have at least a command
    if (args.len < 2) {
        std.debug.print("Error: No command provided\n", .{});
        std.debug.print("Usage: hyprshot-cloud [OPTIONS] <COMMAND>\n", .{});
        return error.NoCommandProvided;
    }

    const command = args[1];
    
    // Load configuration
    const config = try loadConfig(allocator);
    defer {
        allocator.free(config.access_key_id);
        allocator.free(config.secret_access_key);
        allocator.free(config.endpoint);
        allocator.free(config.region);
    }
    
    // Handle commands
    if (std.mem.eql(u8, command, "upload")) {
        if (args.len < 3) {
            std.debug.print("Error: No image file provided\n", .{});
            std.debug.print("Usage: hyprshot-cloud upload <IMAGE> --bucket <BUCKET>\n", .{});
            return error.NoImageProvided;
        }
        
        const image_path = args[2];
        // For now, we'll need to parse flags to get the bucket name
        // This is a simplified version - we'll implement proper flag parsing later
        var bucket: ?[]const u8 = null;
        
        // Simple flag parsing for --bucket or -b
        for (args[3..], 0..) |arg, i| {
            if (std.mem.eql(u8, arg, "--bucket") or std.mem.eql(u8, arg, "-b")) {
                if (i + 1 < args.len - 3) {
                    bucket = args[3 + i + 1];
                }
            }
        }
        
        if (bucket == null) {
            std.debug.print("Error: Bucket name is required\n", .{});
            std.debug.print("Usage: hyprshot-cloud upload <IMAGE> --bucket <BUCKET>\n", .{});
            return error.NoBucketProvided;
        }
        
        try uploadImage(allocator, image_path, bucket.?, config);
    } else if (std.mem.eql(u8, command, "list-buckets")) {
        try list_buckets.listBuckets(allocator, config);
    } else if (std.mem.eql(u8, command, "list-objects")) {
        // Parse flags for bucket name and optional prefix
        var bucket: ?[]const u8 = null;
        var prefix: ?[]const u8 = null;
        
        // Simple flag parsing for --bucket/-b and --prefix
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--bucket") or std.mem.eql(u8, args[i], "-b")) {
                if (i + 1 < args.len) {
                    bucket = args[i + 1];
                    i += 1; // Skip the next argument as it's the bucket name
                }
            } else if (std.mem.eql(u8, args[i], "--prefix")) {
                if (i + 1 < args.len) {
                    prefix = args[i + 1];
                    i += 1; // Skip the next argument as it's the prefix
                }
            }
        }
        
        if (bucket == null) {
            std.debug.print("Error: Bucket name is required\n", .{});
            std.debug.print("Usage: hyprshot-cloud list-objects --bucket <BUCKET> [--prefix <PREFIX>]\n", .{});
            return error.NoBucketProvided;
        }
        
        try list_objects.listObjects(allocator, bucket.?, prefix, config);
    } else if (std.mem.eql(u8, command, "create-bucket")) {
        // Parse flags for bucket name
        var bucket: ?[]const u8 = null;
        
        // Simple flag parsing for --bucket/-b
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--bucket") or std.mem.eql(u8, args[i], "-b")) {
                if (i + 1 < args.len) {
                    bucket = args[i + 1];
                    i += 1; // Skip the next argument as it's the bucket name
                }
            }
        }
        
        if (bucket == null) {
            std.debug.print("Error: Bucket name is required\n", .{});
            std.debug.print("Usage: hyprshot-cloud create-bucket --bucket <BUCKET>\n", .{});
            return error.NoBucketProvided;
        }
        
        try create_bucket.createBucket(allocator, bucket.?, config);
    } else if (std.mem.eql(u8, command, "delete-bucket")) {
        // Parse flags for bucket name
        var bucket: ?[]const u8 = null;
        
        // Simple flag parsing for --bucket/-b
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--bucket") or std.mem.eql(u8, args[i], "-b")) {
                if (i + 1 < args.len) {
                    bucket = args[i + 1];
                    i += 1; // Skip the next argument as it's the bucket name
                }
            }
        }
        
        if (bucket == null) {
            std.debug.print("Error: Bucket name is required\n", .{});
            std.debug.print("Usage: hyprshot-cloud delete-bucket --bucket <BUCKET>\n", .{});
            return error.NoBucketProvided;
        }
        
        try delete_bucket.deleteBucket(allocator, bucket.?, config);
    } else if (std.mem.eql(u8, command, "delete-object")) {
        // Parse flags for bucket name and object key
        var bucket: ?[]const u8 = null;
        var key: ?[]const u8 = null;
        
        // Simple flag parsing for --bucket/-b and --key/-k
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--bucket") or std.mem.eql(u8, args[i], "-b")) {
                if (i + 1 < args.len) {
                    bucket = args[i + 1];
                    i += 1; // Skip the next argument as it's the bucket name
                }
            } else if (std.mem.eql(u8, args[i], "--key") or std.mem.eql(u8, args[i], "-k")) {
                if (i + 1 < args.len) {
                    key = args[i + 1];
                    i += 1; // Skip the next argument as it's the key
                }
            }
        }
        
        if (bucket == null) {
            std.debug.print("Error: Bucket name is required\n", .{});
            std.debug.print("Usage: hyprshot-cloud delete-object --bucket <BUCKET> --key <KEY>\n", .{});
            return error.NoBucketProvided;
        }
        
        if (key == null) {
            std.debug.print("Error: Object key is required\n", .{});
            std.debug.print("Usage: hyprshot-cloud delete-object --bucket <BUCKET> --key <KEY>\n", .{});
            return error.NoKeyProvided;
        }
        
        try delete_object.deleteObject(allocator, bucket.?, key.?, config);
    } else {
        std.debug.print("Error: Unknown command '{s}'\n", .{command});
        std.debug.print("Usage: hyprshot-cloud [OPTIONS] <COMMAND>\n", .{});
        return error.UnknownCommand;
    }
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
    };
}

fn uploadImage(allocator: std.mem.Allocator, image_path: []const u8, bucket: []const u8, config: Config) !void {
    // Open the image file
    var file = std.fs.cwd().openFile(image_path, .{}) catch |err| {
        std.debug.print("Error: Could not open image file at {s}\n", .{image_path});
        return err;
    };
    defer file.close();
    
    // Read file content
    const file_content = try file.readToEndAlloc(allocator, 100 * 1024 * 1024); // 100MB limit
    defer allocator.free(file_content);
    
    // Get file info for content length
    const stat = try file.stat();
    const content_length = stat.size;
    
    // Extract filename from path
    const filename = std.fs.path.basename(image_path);
    
    // Generate date-based filename to avoid conflicts
    const timestamp = std.time.timestamp();
    const dated_filename = try std.fmt.allocPrint(allocator, "{d}_{s}", .{ timestamp, filename });
    defer allocator.free(dated_filename);
    
    std.debug.print("Uploading {s} to {s}/{s}...\n", .{ filename, bucket, dated_filename });
    
    // Create the S3 object key path
    const object_key = dated_filename;
    
    // Get current time for signing
    const current_time = std.time.timestamp();
    
    // Format dates for signing
    const date_str = try formatDate(allocator, current_time);
    defer allocator.free(date_str);
    
    const amz_date = try formatAmzDate(allocator, current_time);
    defer allocator.free(amz_date);
    
    // Calculate payload hash
    const payload_hash = try hashPayload(allocator, file_content);
    defer allocator.free(payload_hash);
    
    // Create canonical request components
    const canonical_uri = try std.fmt.allocPrint(allocator, "/{s}/{s}", .{ bucket, object_key });
    defer allocator.free(canonical_uri);
    
    const canonical_query_string = "";
    
    // Extract host from endpoint (remove protocol)
    const host = if (std.mem.indexOf(u8, config.endpoint, "//")) |protocol_end| 
        config.endpoint[protocol_end + 2..] 
    else 
        config.endpoint;
    
    const canonical_headers = try std.fmt.allocPrint(allocator, 
        "content-length:{d}\ncontent-type:image/png\nhost:{s}\nx-amz-content-sha256:{s}\nx-amz-date:{s}\n", 
        .{ content_length, host, payload_hash, amz_date });
    defer allocator.free(canonical_headers);
    
    const signed_headers = "content-length;content-type;host;x-amz-content-sha256;x-amz-date";
    
    // Create canonical request
    const canonical_request = try createCanonicalRequest(
        allocator,
        "PUT",
        canonical_uri,
        canonical_query_string,
        canonical_headers,
        signed_headers,
        payload_hash,
    );
    defer allocator.free(canonical_request);
    
    // Hash canonical request
    const canonical_request_hash = try hashPayload(allocator, canonical_request);
    defer allocator.free(canonical_request_hash);
    
    // Create credential scope
    const credential_scope = try std.fmt.allocPrint(allocator, "{s}/{s}/s3/aws4_request", .{ date_str, config.region });
    defer allocator.free(credential_scope);
    
    // Create string to sign
    const string_to_sign = try createStringToSign(
        allocator,
        "AWS4-HMAC-SHA256",
        amz_date,
        credential_scope,
        canonical_request_hash,
    );
    defer allocator.free(string_to_sign);
    
    // Derive signing key
    const signing_key = try deriveSigningKey(allocator, config.secret_access_key, date_str, config.region, "s3");
    defer allocator.free(signing_key);
    
    // Calculate signature
    const signature = try calculateSignature(allocator, signing_key, string_to_sign);
    defer allocator.free(signature);
    
    // Create authorization header
    const authorization_header = try createAuthorizationHeader(
        allocator,
        config.access_key_id,
        credential_scope,
        signed_headers,
        signature,
    );
    defer allocator.free(authorization_header);
    
    // Use curl to upload the file to S3 with proper AWS Signature V4
    const cmd = try std.fmt.allocPrint(allocator, 
        "curl -X PUT -T {s} " ++
        "-H \"Host: {s}\" " ++
        "-H \"Content-Type: image/png\" " ++
        "-H \"Content-Length: {d}\" " ++
        "-H \"X-Amz-Date: {s}\" " ++
        "-H \"X-Amz-Content-Sha256: {s}\" " ++
        "-H \"Authorization: {s}\" " ++
        "{s}/{s}/{s}", 
        .{ image_path, host, content_length, amz_date, payload_hash, authorization_header, config.endpoint, bucket, object_key });
    defer allocator.free(cmd);
    
    const result = std.process.Child.run(.{ 
        .allocator = allocator, 
        .argv = &.{ "sh", "-c", cmd }
    });
    
    if (result) |run_result| {
        defer allocator.free(run_result.stdout);
        defer allocator.free(run_result.stderr);
        
        if (run_result.term.Exited == 0) {
            std.debug.print("Successfully uploaded {s} to {s}/{s}\n", .{ filename, bucket, object_key });
            std.debug.print("Public URL: {s}/{s}/{s}\n", .{ config.endpoint, bucket, object_key });
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
