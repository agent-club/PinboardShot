# OCR plugins

PinboardShot keeps macOS Vision OCR as the default. An OCR plugin is a declarative JSON manifest that adapts one HTTP JSON API to PinboardShot's interactive OCR tool. It is intentionally narrower than an executable extension: plugin manifests cannot run code, read the API Key, choose an unrelated destination, or receive background capture history.

Remote OCR is used only when the user actively draws an OCR region in the annotation editor. History indexing and smart redaction always stay on-device.

## Install a plugin

1. Open **Settings → OCR Plugins**.
2. Click **Open Plugins Folder**.
3. Copy one `.json` manifest into that folder.
4. Click **Reload**, select the plugin, then enter its Base URL, model, and API Key.

The API Key is stored in macOS Keychain. Base URL and model are stored in preferences. Leaving the API Key field blank after one has been saved preserves the Keychain value.

## Manifest schema version 1

See [`docs/examples/ocr-plugins/openai-compatible.json`](examples/ocr-plugins/openai-compatible.json) for a complete example.

| Field | Required | Meaning |
| --- | --- | --- |
| `schemaVersion` | Yes | Must be `1`. |
| `id` | Yes | Stable lowercase identifier containing letters, digits, dots, or hyphens. |
| `name` | Yes | Name shown in Settings. |
| `endpoint` | Yes | Relative absolute path appended to the user-provided Base URL. It cannot contain another origin. |
| `authentication` | No | Keychain-backed API Key header and its prefix. |
| `headers` | No | Non-sensitive static HTTP headers. Authentication, cookie, host, and transport headers are rejected. |
| `request` | Yes | JSON request template. It must contain `{{imageDataURL}}`. |
| `responseTextPath` | Yes | Dot-separated path to a string in the JSON response. Numeric components address array elements. |
| `defaultBaseURL` | No | Initial Base URL shown before the user saves a value. |
| `defaultModel` | No | Initial model shown before the user saves a value. |

Two request placeholders are available:

- `{{imageDataURL}}`: a PNG data URL for the selected OCR region.
- `{{model}}`: the model entered in Settings. If the manifest uses it, the model field is required.

For example, `choices.0.message.content` reads the string at this response shape:

```json
{
  "choices": [
    {
      "message": {
        "content": "recognized text"
      }
    }
  ]
}
```

## Request security and limits

- Remote Base URLs must use HTTPS. `http://localhost`, `http://127.0.0.1`, and `http://[::1]` are allowed for local development.
- A plugin endpoint stays on the Base URL origin. Cross-origin redirects are rejected before authentication is forwarded.
- API Keys are injected only into the declared authentication header and are never substituted into the JSON template.
- Image request data is limited to 20 MB before Base64 encoding. JSON responses are limited to 5 MB. Requests time out after 60 seconds.
- PinboardShot does not retry failed OCR requests automatically.

Plugin authors should not place credentials or private service URLs in manifests. Use the Settings fields and Keychain-backed authentication instead.
