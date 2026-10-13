# Windows / WHPX の Apple Account 認証状況

2026-10-13、macOS Tahoe 26.4 の Apple Account サインインは未解決。
SMBIOS を生成して反映したことと、Apple の認証が成功することは別の確認項目になる。

## この VM で確認したこと

- OpenCore のシリアル・MLB を生成し、ROM を VM の MAC アドレスに合わせた。
- インストール済みの SystemUUID とモデルは保持した。
- ゲストのシリアルと EFI の `system-id` は生成／保持した設定に一致した。
- SIP・AMFI・署名付き起動の設定は維持している。
- `kern.hv_vmm_present` は `1`。認証ログは AppleVirtualPlatform の Identity
  経路を選び、端末証明を利用できずに失敗している。

`akd` のログで確認した失敗の種類は以下。アカウント名、トークン、識別子や
生のログは公開しない。

| 段階 | エラー |
|---|---|
| DeviceIdentity / 端末の署名 | `com.apple.devicecheck.error.baa` / `-10000` |
| attestation ヘッダー取得 | `AKAuthenticationError` / `-7066` |
| Anisette の準備 | `AKAnisetteError` / `-8008` |
| ADI routing の取得 | `-45061`、上位で `AKAnisetteError -8025` |

この記録から、少なくとも現在の失敗はシリアルの入力欄やパスワードの判定だけで
説明できない。VM 用の端末証明を用意する経路が欠けている。
キーチェーンやアカウントのデータを消して解決したことにはしていない。

## Apple が提供する VM 向け iCloud 対応

Apple の [Using iCloud with macOS virtual machines](https://developer.apple.com/documentation/virtualization/using-icloud-with-macos-virtual-machines)
は、macOS 15 以降の Apple Silicon ホストで、Virtualization.framework が
ホストの Secure Enclave に由来する固有の VM 識別情報を構成する仕組みを説明している。
これは SMBIOS の文字列を生成する処理とは異なる。

現在の Windows / WHPX / QEMU 構成には、その Apple ホスト側の識別情報を
提供する実装がない。この構成で Apple Account が使えるとは案内しない。
SMBIOS の再生成を繰り返しても、対応した証明を作ったことにはならない。

今後対応を検討する場合は、実際に Apple が受け付ける認証まで確認する必要がある。
現時点の動作範囲は macOS の起動・デスクトップ・入力・VM 管理までであり、
Apple Account サインイン／iCloud は未対応として扱う。
