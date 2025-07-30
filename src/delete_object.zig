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

/// Delete an object from an S3 bucket
pub fn deleteObject(allocator: std.mem.Allocator, bucket: []const u8, key: []const u8, config: Config) !void {
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
    // For deleting an object, the URI is /{bucket}/{key}
    const canonical_uri = try std.fmt.allocPrint(allocator, "/{s}/{s}", .{ bucket, key });
    defer allocator.free(canonical_uri);
    
    const canonical_query_string = "";
    
    // Empty payload for object deletion
    const empty_payload_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
    
    const canonical_headers = try std.fmt.allocPrint(allocator, 
        "host:{s}\nx-amz-content-sha256:{s}\nx-amz-date:{s}\n", 
        .{ host, empty_payload_hash, amz_date });
    defer allocator.free(canonical_headers);
    
    const signed_headers = "host;x-amz-content-sha256;x-amz-date";
    
    // Create canonical request
    const canonical_request = try createCanonicalRequest(
        allocator,
        "DELETE",
        canonical_uri,
        canonical_query_string,
        canonical_headers,
        signed_headers,
        empty_payload_hash,
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
    const url = try std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ config.endpoint, bucket, key });
    defer allocator.free(url);
    
    const cmd = try std.fmt.allocPrint(allocator, 
        "curl -X DELETE " ++
        "-H \"Host: {s}\" " ++
        "-H \"X-Amz-Date: {s}\" " ++
        "-H \"X-Amz-Content-Sha256: {s}\" " ++
        "-H \"Authorization: {s}\" " ++
        "{s}", 
        .{ host, amz_date, empty_payload_hash, authorization_header, url });
    defer allocator.free(cmd);
    
    const result = std.process.Child.run(.{ 
        .allocator = allocator, 
        .argv = &.{ "sh", "-c", cmd }
    });
    
    if (result) |run_result| {
        defer allocator.free(run_result.stdout);
        defer allocator.free(run_result.stderr);
        
        if (run_result.term.Exited == 0) {
            // Check if the response indicates success
            // S3 returns 204 No Content for successful object deletion
            if (run_result.stdout.len > 0) {
                // Check for error in response
                if (std.mem.indexOf(u8, run_result.stdout, "<Error>") != null) {
                    std.debug.print("Object deletion failed: {s}\n", .{run_result.stdout});
                    return error.ObjectDeletionFailed;
                }
            }
            std.debug.print("Successfully deleted object: {s} from bucket: {s}\n", .{ key, bucket });
        } else {
            std.debug.print("Object deletion failed with exit code: {d}\n", .{run_result.term.Exited});
            std.debug.print("stderr: {s}\n", .{run_result.stderr});
            if (run_result.stdout.len > 0) {
                std.debug.print("Response: {s}\n", .{run_result.stdout});
            }
            return error.ObjectDeletionFailed;
        }
    } else |err| {
        std.debug.print("Error executing curl command: {}\n", .{err});
        return err;
    }
}
