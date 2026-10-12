# Native Windows validation

| Check | Result |
|---|---|
| Project-only process environment | Passed |
| Rust pin | 1.98.1 GNU installed and executed |
| UCRT64 Clang Windows executable | Compiled and ran |
| EFI driver link | Passed |
| ROM object relocations | None; native binary extraction passed |
| metal2vulkan runtime check | Passed with 8 Windows exit-guard warnings |
| Initial SDL3 build | Failed with existing GCC; switched to native Clang/Ninja |
| Initial metallib check | Failed on CRLF sources; LF checkout restored |
| Initial xtask tests | 33 passed, 5 platform-specific failures; fixes in progress |
| WHPX capability | Hypervisor absent, feature disabled |
| VM and Liquid Glass tests | Not run; WHPX prerequisite blocked |

Logs are private in `.work/diagnostics/`. These are intermediate results.
