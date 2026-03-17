# screenshot_subprocess

A minimal Dart HTTP server that the `flutter_webrtc` Linux screenshot plugin
runs as a child process.  It captures the screen using native Linux tools and
returns the image bytes over a loopback HTTP connection.

## Endpoints

| Method | Path        | Description                                     |
|--------|-------------|-------------------------------------------------|
| GET    | `/status`   | Health-check – returns `{"status":"ok"}`        |
| POST   | `/capture`  | Capture a screenshot and return the image bytes |
| POST   | `/shutdown` | Stop the server gracefully                      |

### `/capture` request body (optional JSON)

| Field         | Type    | Default | Description                                          |
|---------------|---------|---------|------------------------------------------------------|
| `interactive` | `bool`  | `true`  | Show a region-selection UI before capturing          |
| `format`      | `string`| `"png"` | Image format: `"png"` or `"jpeg"`                   |

## Dependencies

### X11

Install **scrot** for full-screen and interactive region capture:
```bash
sudo apt install scrot
```

### Wayland

Install **grim** (capture) and **slurp** (region selection):
```bash
sudo apt install grim slurp
```

## Running manually

```bash
dart run bin/main.dart --port 8765
```

The process prints `SCREENSHOT_SERVER_PORT:<port>` to stdout when it is ready.
