# hyprshot-cloud CLI Design Specification

## Overview
The hyprshot-cloud CLI will be expanded to support general S3 management operations beyond just uploading images. The CLI will use a subcommand structure similar to popular tools like `git` or `kubectl`.

## Command Structure
```
hyprshot-cloud [GLOBAL_FLAGS] <COMMAND> [COMMAND_FLAGS] [ARGS]
```

## Global Flags
- `-h, --help`: Show help message
- `--version`: Show version information
- `--config`: Path to config file (default: ~/.config/hyprshot-cloud/config.json)

## Commands

### upload
Upload an image to an S3 bucket.

**Usage:**
```
hyprshot-cloud upload [FLAGS] <IMAGE_PATH>
```

**Flags:**
- `-b, --bucket`: Bucket name (required)
- `-k, --key`: Object key (optional, auto-generated if not provided)

**Example:**
```
hyprshot-cloud upload -b my-bucket screenshot.png
hyprshot-cloud upload -b my-bucket -k my-screenshot.png screenshot.png
```

### list-buckets
List all S3 buckets.

**Usage:**
```
hyprshot-cloud list-buckets
```

**Example:**
```
hyprshot-cloud list-buckets
```

### list-objects
List objects in an S3 bucket.

**Usage:**
```
hyprshot-cloud list-objects [FLAGS]
```

**Flags:**
- `-b, --bucket`: Bucket name (required)
- `--prefix`: Prefix to filter objects

**Example:**
```
hyprshot-cloud list-objects -b my-bucket
hyprshot-cloud list-objects -b my-bucket --prefix screenshots/
```

### create-bucket
Create an S3 bucket.

**Usage:**
```
hyprshot-cloud create-bucket [FLAGS]
```

**Flags:**
- `-b, --bucket`: Bucket name (required)

**Example:**
```
hyprshot-cloud create-bucket -b my-new-bucket
```

### delete-bucket
Delete an S3 bucket.

**Usage:**
```
hyprshot-cloud delete-bucket [FLAGS]
```

**Flags:**
- `-b, --bucket`: Bucket name (required)

**Example:**
```
hyprshot-cloud delete-bucket -b my-old-bucket
```

### delete-object
Delete an object from an S3 bucket.

**Usage:**
```
hyprshot-cloud delete-object [FLAGS]
```

**Flags:**
- `-b, --bucket`: Bucket name (required)
- `-k, --key`: Object key (required)

**Example:**
```
hyprshot-cloud delete-object -b my-bucket -k screenshot.png
```

## Configuration
The configuration file will be updated to remove the bucket field since it will now be passed as a flag:

**Before:**
```json
{
  "access_key_id": "...",
  "secret_access_key": "...",
  "endpoint": "...",
  "region": "...",
  "bucket": "..."
}
```

**After:**
```json
{
  "access_key_id": "...",
  "secret_access_key": "...",
  "endpoint": "...",
  "region": "..."
}
```
