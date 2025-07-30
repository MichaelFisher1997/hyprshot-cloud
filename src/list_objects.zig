const std = @import("std");
const crypto = std.crypto;

const Config = @import("main.zig").Config;
const formatDate = @import("main.zig").formatDate;
const formatAmzDate = @import("main.zig").formatAmzDate;
const hashPayload = @import("main.zig").hashPayload;
const deriveSigningKey = @import("main.zig").deriveSigningKey;
const createCanonicalRequest = @import("main.zig").createCanonicalRequest;
const createStringToSign = @import("main.zig").createStringToSign;
const calculateSignature = @import("main.zig").calculateSignature;
const createAuthorizationHeader = @import("main.zig").createAuthorizationHeader;

/// List objects in an S3 bucket
pub fn listObjects(allocator: std.mem.Allocator, bucket: []const u8, prefix: ?[]const u8, config: Config) !void {
    // Get current timestamp
    const timestamp = std.time.timestamp();
    
    // Format dates for AWS Signature V4
    const date_str = try formatDate(allocator, timestamp);
    defer allocator.free(date_str);
    
    const amz_date = try formatAmzDate(allocator, timestamp);
    defer allocator.free(amz_date);
    
    // Extract host from endpoint
    const host = if (std.mem.indexOf(u8, config.endpoint, "//")) |protocol_end| 
        config.endpoint[protocol_end + 2..] 
    else 
        config.endpoint;
    
    // Create canonical request components
    const canonical_uri = try std.fmt.allocPrint(allocator, "/{s}", .{ bucket });
    defer allocator.free(canonical_uri);
    
    // Build query string with list-type=2 (ListObjectsV2) and prefix if provided
    var query_params = std.ArrayList(u8).init(allocator);
    defer query_params.deinit();
    
    try query_params.appendSlice("list-type=2");
    
    if (prefix) |p| {
        if (p.len > 0) {
            try query_params.appendSlice("&prefix=");
            // URL encode the prefix
            var encoded_prefix = std.ArrayList(u8).init(allocator);
            defer encoded_prefix.deinit();
            try urlEncode(allocator, &encoded_prefix, p);
            try query_params.appendSlice(encoded_prefix.items);
        }
    }
    
    const canonical_query_string = try allocator.dupe(u8, query_params.items);
    defer allocator.free(canonical_query_string);
    
    const canonical_headers = try std.fmt.allocPrint(allocator, 
        "host:{s}\nx-amz-content-sha256:{s}\nx-amz-date:{s}\n", 
        .{ host, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", amz_date });
    defer allocator.free(canonical_headers);
    
    const signed_headers = "host;x-amz-content-sha256;x-amz-date";
    
    // Create canonical request
    const canonical_request = try createCanonicalRequest(
        allocator,
        "GET",
        canonical_uri,
        canonical_query_string,
        canonical_headers,
        signed_headers,
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", // Empty payload hash
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
    
    // Use curl to make the request to S3
    // For path-style requests, we use the bucket in the path
    const url_with_params = try std.fmt.allocPrint(allocator, "{s}/{s}?{s}", .{ config.endpoint, bucket, canonical_query_string });
    defer allocator.free(url_with_params);
    
    const cmd = try std.fmt.allocPrint(allocator, 
        "curl -X GET " ++
        "-H \"Host: {s}\" " ++
        "-H \"X-Amz-Date: {s}\" " ++
        "-H \"X-Amz-Content-Sha256: {s}\" " ++
        "-H \"Authorization: {s}\" " ++
        "{s}", 
        .{ host, amz_date, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", authorization_header, url_with_params });
    defer allocator.free(cmd);
    
    const result = std.process.Child.run(.{ 
        .allocator = allocator, 
        .argv = &.{ "sh", "-c", cmd }
    });
    
    if (result) |run_result| {
        defer allocator.free(run_result.stdout);
        defer allocator.free(run_result.stderr);
        
        if (run_result.term.Exited == 0) {
            // Parse and display the XML response
            try parseAndDisplayObjects(allocator, run_result.stdout);
        } else {
            std.debug.print("List objects failed with exit code: {d}\n", .{run_result.term.Exited});
            std.debug.print("stderr: {s}\n", .{run_result.stderr});
            if (run_result.stdout.len > 0) {
                std.debug.print("Response: {s}\n", .{run_result.stdout});
            }
            return error.ListObjectsFailed;
        }
    } else |err| {
        std.debug.print("Error executing curl command: {}\n", .{err});
        return err;
    }
}

/// URL encode a string
fn urlEncode(allocator: std.mem.Allocator, output: *std.ArrayList(u8), input: []const u8) !void {
    _ = allocator; // Mark as used
    const hex_chars = "0123456789ABCDEF";
    
    for (input) |c| {
        switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => {
                try output.append(c);
            },
            else => {
                try output.append('%');
                try output.append(hex_chars[c >> 4]);
                try output.append(hex_chars[c & 0x0F]);
            },
        }
    }
}

/// Parse and display the XML response from S3 ListObjectsV2
fn parseAndDisplayObjects(allocator: std.mem.Allocator, xml_response: []const u8) !void {
    _ = allocator; // Mark as used
    
    std.debug.print("Objects in bucket:\n", .{});
    std.debug.print("====================\n", .{});
    
    // Simple XML parsing - in a real implementation, we would use a proper XML parser
    // For now, we'll do basic string parsing to extract key names
    
    var index: usize = 0;
    while (index < xml_response.len) {
        // Look for <Key> tags
        const maybe_start = std.mem.indexOf(u8, xml_response[index..], "<Key>");
        if (maybe_start) |relative_start| {
            const tag_start = index + relative_start;
            const key_start = tag_start + 5; // Length of "<Key>"
            const maybe_end = std.mem.indexOf(u8, xml_response[key_start..], "</Key>");
            if (maybe_end) |relative_end| {
                const tag_end = key_start + relative_end;
                const key_content = xml_response[key_start..tag_end];
                std.debug.print("{s}\n", .{key_content});
                index = tag_end + 6; // Length of "</Key>"
                continue;
            }
        }
        
        // Move to next character
        index += 1;
    }
}
