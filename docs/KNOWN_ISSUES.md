# Known issues

- WHPX feature enablement and a Windows restart are required for VM boot.
- Native compilation and OS memory/API tests are still in progress.
- The upstream Objective-C behavior-lock runner targets macOS; its recorded
  results are not evidence of Windows guest behavior.
- GPU import capability, lifetime and read-only-view behavior must be checked
  on the actual Windows NVIDIA driver before guest use.
- No Tahoe desktop, Liquid Glass visual comparison, restart or FPS measurement
  has yet been obtained. Do not treat compilation or ROM creation as that proof.
