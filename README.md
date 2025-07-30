# hyprshot-cloud

A CLI tool written in Zig to upload hyprshot screenshots to an S3-compatible bucket.

## Features

- Uploads images to S3-compatible storage services
- Reads configuration from `~/.config/hyprshot-cloud/config.json`
- Generates unique filenames to avoid conflicts
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
  "region": "us-east-1",
  "bucket": "screenshots"
}
```

## Usage

```bash
hyprshot-cloud /path/to/image.png
```

This is typically used in combination with hyprshot:

```bash
bind = ALT, C, exec, bash -c 'IMG="/home/user/Pictures/hyprshots/shot_$(date +%s).png"; hyprshot -m region -o "$IMG" && wl-copy < "$IMG" && hyprshot-cloud "$IMG"'
```

## Dependencies

- Zig 0.11.0 or later
- curl
- OpenSSL

## License

MIT
