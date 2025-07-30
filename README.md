# hyprshot-cloud

A CLI tool written in Zig for managing S3-compatible buckets and objects.

## Features

- Multi-command CLI with subcommands similar to git/kubectl
- Upload images to S3-compatible storage services
- List buckets and objects
- Create and delete buckets
- Delete objects
- Implements AWS Signature V4 for secure, authenticated requests
- Reads configuration from `~/.config/hyprshot-cloud/config.json`
- Built with Nix flake for easy installation

## Installation

### Using Nix

```bash
# Clone the repository
git clone <repository-url>
cd hyprshot-cloud

# Build and install
nix profile install .
```

### Manual build

```bash
# Install Zig (0.11.0 or later)

# Build
zig build

# Install
sudo cp zig-out/bin/hyprshot-cloud /usr/local/bin/
```

## Configuration

Create a configuration file at `~/.config/hyprshot-cloud/config.json`:

```json
{
  "access_key_id": "YOUR_ACCESS_KEY_ID",
  "secret_access_key": "YOUR_SECRET_ACCESS_KEY",
  "endpoint": "https://s3.example.com",
  "region": "us-east-1"
}
```

For Mega.nz S4, use:

```json
{
  "access_key_id": "YOUR_MEGA_ACCESS_KEY_ID",
  "secret_access_key": "YOUR_MEGA_SECRET_ACCESS_KEY",
  "endpoint": "https://s3.g.s4.mega.io",
  "region": "g"
}
```

## Usage

hyprshot-cloud uses a subcommand structure similar to git or kubectl:

```bash
hyprshot-cloud [GLOBAL_FLAGS] <COMMAND> [COMMAND_FLAGS] [ARGS]
```

### Global Flags

- `-h, --help`: Show help message
- `--version`: Show version information

### Commands

#### upload

Upload an image to an S3 bucket.

```bash
hyprshot-cloud upload [FLAGS] <IMAGE_PATH>
```

**Flags:**
- `-b, --bucket`: Bucket name (required)
- `-k, --key`: Object key (optional, auto-generated if not provided)

**Example:**
```bash
hyprshot-cloud upload -b my-bucket screenshot.png
hyprshot-cloud upload -b my-bucket -k my-screenshot.png screenshot.png
```

#### list-buckets

List all S3 buckets.

```bash
hyprshot-cloud list-buckets
```

**Example:**
```bash
hyprshot-cloud list-buckets
```

#### list-objects

List objects in an S3 bucket.

```bash
hyprshot-cloud list-objects [FLAGS]
```

**Flags:**
- `-b, --bucket`: Bucket name (required)
- `--prefix`: Prefix to filter objects

**Example:**
```bash
hyprshot-cloud list-objects -b my-bucket
hyprshot-cloud list-objects -b my-bucket --prefix screenshots/
```

#### create-bucket

Create an S3 bucket.

```bash
hyprshot-cloud create-bucket [FLAGS]
```

**Flags:**
- `-b, --bucket`: Bucket name (required)

**Example:**
```bash
hyprshot-cloud create-bucket -b my-new-bucket
```

#### delete-bucket

Delete an S3 bucket.

```bash
hyprshot-cloud delete-bucket [FLAGS]
```

**Flags:**
- `-b, --bucket`: Bucket name (required)

**Example:**
```bash
hyprshot-cloud delete-bucket -b my-old-bucket
```

#### delete-object

Delete an object from an S3 bucket.

```bash
hyprshot-cloud delete-object [FLAGS]
```

**Flags:**
- `-b, --bucket`: Bucket name (required)
- `-k, --key`: Object key (required)

**Example:**
```bash
hyprshot-cloud delete-object -b my-bucket -k screenshot.png
```

## Public Access

**Important**: Uploaded objects are not automatically publicly accessible.

### For Mega.nz S4

To make uploaded objects publicly accessible on Mega.nz S4, you need to set a bucket policy. Use the following policy document:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::your-bucket-name/*"
    }
  ]
}
```

You can apply this policy using the AWS CLI or any S3-compatible tool that supports bucket policies:

```bash
aws s3api put-bucket-policy --bucket your-bucket-name --policy file://policy.json
```

### Alternative: Presigned URLs

If you prefer not to make objects publicly accessible, you can generate presigned URLs for temporary access. This feature is not currently implemented in hyprshot-cloud but could be added in a future version.

## Integration with hyprshot

You can integrate this tool with hyprshot by configuring it as a custom upload command in your hyprshot configuration:

```bash
bind = ALT, C, exec, bash -c 'IMG="/home/user/Pictures/hyprshots/shot_$(date +%s).png"; hyprshot -m region -o "$IMG" && wl-copy < "$IMG" && hyprshot-cloud upload -b your-bucket-name "$IMG"'
```

## Dependencies

- Zig 0.11.0 or later
- curl
- OpenSSL

## License

MIT
