const std = @import("std");
const crypto = std.crypto;

const Config = @import("main.zig").Config;

/// List all S3 buckets
pub fn listBuckets(allocator: std.mem.Allocator, config: Config) !void {
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
    const canonical_uri = "/";
    const canonical_query_string = "";
    
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
    
    // Use curl to list buckets with proper AWS Signature V4
    const cmd = try std.fmt.allocPrint(allocator, 
        "curl -X GET " ++
        "-H \"Host: {s}\" " ++
        "-H \"X-Amz-Date: {s}\" " ++
        "-H \"X-Amz-Content-Sha256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\" " ++
        "-H \"Authorization: {s}\" " ++
        "{s}/", 
        .{ host, amz_date, authorization_header, config.endpoint });
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
            try parseAndDisplayBuckets(allocator, run_result.stdout);
        } else {
            std.debug.print("List buckets failed with exit code: {d}\n", .{run_result.term.Exited});
            std.debug.print("stderr: {s}\n", .{run_result.stderr});
            return error.ListBucketsFailed;
        }
    } else |err| {
        std.debug.print("Error executing curl command: {}\n", .{err});
        return err;
    }
}

/// Parse and display buckets from XML response
fn parseAndDisplayBuckets(allocator: std.mem.Allocator, xml_response: []const u8) !void {
    _ = allocator; // Mark as used
    // Simple XML parsing - in a real implementation, we would use a proper XML parser
    // For now, we'll do basic string parsing
    
    std.debug.print("Buckets:\n", .{});
    
    // Find all <Name> tags, accounting for possible namespace prefixes
    var start_index: usize = 0;
    while (std.mem.indexOfScalarPos(u8, xml_response, start_index, '<')) |tag_start| {
        // Look for either <Name> or <...Name> where ... is a namespace prefix
        if (tag_start + 5 < xml_response.len) {
            const after_open_bracket = xml_response[tag_start + 1..];
            var name_tag_start: ?usize = null;
            
            // Check for direct <Name> tag
            if (after_open_bracket.len >= 5 and std.mem.eql(u8, after_open_bracket[0..5], "Name>")) {
                name_tag_start = 0;
            } 
            // Check for namespaced <...Name> tag
            else if (std.mem.indexOf(u8, after_open_bracket, ":Name>")) |colon_pos| {
                if (colon_pos > 0) {
                    name_tag_start = colon_pos + 1;
                }
            }
            
            if (name_tag_start) |name_start_offset| {
                const actual_name_start = tag_start + 1 + name_start_offset + 5; // +5 for "Name>"
                
                // Find the closing tag
                const close_tag_search_start = actual_name_start;
                if (std.mem.indexOf(u8, xml_response[close_tag_search_start..], "</")) |relative_close_tag| {
                    const close_tag_pos = close_tag_search_start + relative_close_tag;
                    
                    // Check if it's a closing Name tag (with or without namespace)
                    const after_close_bracket = xml_response[close_tag_pos + 2..];
                    var is_name_close_tag = false;
                    
                    if (after_close_bracket.len >= 5 and std.mem.eql(u8, after_close_bracket[0..5], "Name>")) {
                        is_name_close_tag = true;
                    } else if (std.mem.indexOf(u8, after_close_bracket, ":Name>")) |colon_pos| {
                        if (colon_pos > 0) {
                            is_name_close_tag = true;
                        }
                    }
                    
                    if (is_name_close_tag) {
                        const bucket_name = xml_response[actual_name_start..close_tag_pos];
                        std.debug.print("  {s}\n", .{bucket_name});
                        start_index = close_tag_pos + 1;
                        continue;
                    }
                }
            }
        }
        start_index = tag_start + 1;
    }
}

// Import helper functions from main.zig
const formatDate = @import("main.zig").formatDate;
const formatAmzDate = @import("main.zig").formatAmzDate;
const hashPayload = @import("main.zig").hashPayload;
const createCanonicalRequest = @import("main.zig").createCanonicalRequest;
const createStringToSign = @import("main.zig").createStringToSign;
const deriveSigningKey = @import("main.zig").deriveSigningKey;
const calculateSignature = @import("main.zig").calculateSignature;
const createAuthorizationHeader = @import("main.zig").createAuthorizationHeader;
