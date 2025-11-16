# SignPath Code Signing

## Overview

[SignPath](https://signpath.io) is a code signing service that provides Authenticode signing for Windows binaries. We use it to sign Enu's Windows distribution artifacts, ensuring users can verify the authenticity and integrity of downloaded files.

## Signing Workflow

The Windows CI build (`dist_win.yaml`) performs a two-stage signing process:

1. **Sign the zip archive** (deep signing)
   - Upload unsigned zip to SignPath
   - SignPath extracts, signs `enu.exe` and `enu.dll` inside, then repackages
   - Extract signed exe/dll from signed zip
   - Replace unsigned files in dist directory

2. **Build and sign the installer**
   - Build InnoSetup installer using the signed exe/dll
   - Upload installer to SignPath
   - SignPath signs the installer executable

This ensures all distributed binaries are signed:
- `enu.exe` and `enu.dll` inside the zip
- `enu.exe` and `enu.dll` inside the installer
- The installer executable itself

## Artifact Configurations

SignPath uses artifact configurations to define which files to sign and how. These are managed in the SignPath web UI under the `enu` project:

### `enu-zip`
- **Purpose**: Deep sign the Windows distribution zip
- **Files signed**: `enu.exe`, `enu.dll` inside `enu-*-windows-x64.zip`
- **Pattern**: `enu-*-windows-x64.zip` → `enu-*/enu.exe`, `enu-*/enu.dll`
- **Method**: Authenticode signing

### `enu-installer`
- **Purpose**: Sign the InnoSetup installer executable
- **Files signed**: `enu-*-installer.exe`
- **Pattern**: `enu-*-installer.exe`
- **Method**: Authenticode signing

## Signing Policy

Both artifact configurations use the `test-signing` policy, which:
- Uses SignPath's test certificate (not trusted by Windows, for testing only)
- Requires trusted build system verification (GitHub Actions)
- Verifies origin from `https://github.com/getenu/enu.git`

**For production releases**, switch to `release-signing` policy with a proper code signing certificate.

## Modifying Configurations

To update artifact configurations:

1. Log in to [SignPath](https://signpath.io)
2. Navigate to the `enu` project
3. Select the artifact configuration to modify
4. Update the XML configuration
5. Save changes

The configurations use standard Authenticode signing - no special options beyond specifying which PE files to sign.

## GitHub Secrets

The workflow requires these repository secrets:

- `SIGNPATH_API_TOKEN` - API token with submitter permissions
- `SIGNPATH_ORGANIZATION_ID` - Your SignPath organization ID
- `SIGNPATH_PROJECT_SLUG` - Project slug (`enu`)
- `SIGNPATH_SIGNING_POLICY_SLUG` - Policy slug (`test-signing`)

## Verification

The build logs include SHA256 checksums showing:
- Checksums of unsigned files before signing
- Checksums of signed files after extraction
- Checksums after replacing files in dist directory

These should differ between unsigned and signed versions, confirming the signing process worked correctly.
