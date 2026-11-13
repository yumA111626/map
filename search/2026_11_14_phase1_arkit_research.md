# フェーズ1：ARKit基盤の実装調査

調査日: 2026-11-14

## 1. フェーズ1の目的

独自VPSを実装する前段として、iPhoneのカメラ映像とARKitのVisual-Inertial Odometry（VIO）を利用し、次の情報を安定して取得・表示できる基盤を作る。

- カメラ映像
- ARSessionの稼働状態
- トラッキング品質
- ARKitローカル座標系での端末位置と向き
- セッションの中断・再開・エラー
- カメラ権限と端末対応状況

このフェーズではCore MLモデル、画像保存、ARWorldMapの保存、地理座標への変換は実装しない。

## 2. 調査結果の要点

### ARKitが提供する姿勢

`ARWorldTrackingConfiguration`は、カメラ画像とモーションセンサーを組み合わせて端末の位置・向きを推定する。結果は各`ARFrame`の`camera.transform`に4x4行列として格納される。

- 平行移動: `transform.columns.3`のx、y、z
- 回転: `camera.eulerAngles`のroll、pitch、yaw
- 単位: 位置はメートル、角度はラジアン
- 座標: セッション開始時に作られるARKitのローカル世界座標

この座標は緯度・経度ではない。将来のVPSフェーズで、VPSマップの座標系との変換を推定する。

### SwiftUIへのカメラ表示

RealityKitの`ARView`はUIKitのビューであるため、SwiftUIでは`UIViewRepresentable`でラップする。SwiftUIと`ARSessionDelegate`の間はCoordinatorまたは専用Controllerで接続する。

VPSでは構成やフレーム取得を制御する必要があるため、次の初期化を採用する。

```swift
ARView(
    frame: .zero,
    cameraMode: .ar,
    automaticallyConfigureSession: false
)
```

自動構成を無効にした場合は、アプリ側が`ARWorldTrackingConfiguration`を作り、`ARSession.run`を呼ぶ。

### セッション構成

フェーズ1では追加機能を増やさず、VIOの確認に必要な最小構成にする。

```swift
let configuration = ARWorldTrackingConfiguration()
configuration.worldAlignment = .gravity
session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
```

平面検出、シーン再構成、人物セグメンテーションなどは計算負荷を増やすため、必要になるフェーズまで有効化しない。

開始前に`ARWorldTrackingConfiguration.isSupported`を確認する。ARKitはSimulatorでは動作しないため、検証は対応するiPhone実機で行う。

### カメラ権限

自動生成Info.plistを使用している現在のプロジェクトでは、TargetのInfo設定またはBuild Settingsへ次を追加する。

```text
Privacy - Camera Usage Description
VPSで周囲の映像を解析し、端末の位置と向きを推定するためにカメラを使用します。
```

ビルド設定上のキーは`INFOPLIST_KEY_NSCameraUsageDescription`、Info.plist上のキーは`NSCameraUsageDescription`となる。

起動時に`AVCaptureDevice.authorizationStatus(for: .video)`で状態を確認する。

- `authorized`: ARSessionを開始
- `notDetermined`: `requestAccess(for: .video)`で要求
- `denied`: 設定アプリへの案内を表示
- `restricted`: 利用制限の説明を表示

権限説明キーなしでカメラへアクセスするとアプリが終了するため、セッション実装より先に設定する。

### トラッキング状態

`ARSessionObserver`の`session(_:cameraDidChangeTrackingState:)`を使い、状態をSwiftUIへ渡す。

| ARKitの状態 | 日本語表示 | 利用者への案内 |
|---|---|---|
| `notAvailable` | 利用できません | 対応端末・カメラ状態を確認 |
| `limited(.initializing)` | 初期化中 | 端末をゆっくり動かす |
| `limited(.excessiveMotion)` | 動きが速すぎます | 端末をゆっくり動かす |
| `limited(.insufficientFeatures)` | 特徴点が不足しています | 模様や物体がある方向を映す |
| `limited(.relocalizing)` | 再認識中 | 以前映した場所へカメラを向ける |
| `normal` | 正常 | 位置・向きを利用可能 |

起動直後は通常、`notAvailable`、`limited(.initializing)`、`normal`の順で変化する。`limited`を直ちにエラー扱いせず、理由に応じた案内を出す。

### フレーム更新とUI更新頻度

`session(_:didUpdate:)`ではカメラフレームごとに情報を受け取れる。カメラは高頻度で更新されるため、フレームごとにSwiftUIの状態を更新すると不要な再描画が増える。

- ARSessionからのフレーム取得: 全フレーム
- 画面上の姿勢表示: 5〜10Hz程度へ間引く
- 将来の画像保存・推論: 個別のレート制御を設ける

Delegate callbackからSwiftUI状態を変更するときはMainActorへ戻す。

## 3. 推奨構成

```text
map/
├── App/
│   └── MyApp.swift
├── Features/
│   └── ARTracking/
│       ├── ARTrackingView.swift
│       ├── ARViewContainer.swift
│       ├── ARSessionController.swift
│       ├── TrackingState.swift
│       └── CameraPose.swift
└── ContentView.swift
```

既存プロジェクトはファイル数が少ないため、最初から過度に分割する必要はない。ただし、`ARView`の生成、セッション状態、SwiftUI表示は分ける。将来Core ML推論を追加するときに、UIから推論処理を切り離せる構成にする。

### 各コンポーネントの責務

#### `ARSessionController`

- カメラ権限の確認
- 対応端末の確認
- セッション開始・停止・リセット
- `ARSessionDelegate`イベントの受け取り
- 最新姿勢・トラッキング状態・エラーの公開

#### `ARViewContainer`

- `UIViewRepresentable`として`ARView`を生成
- `ARView.session`をControllerへ接続
- ビュー破棄時にセッションを停止

#### `TrackingState`

ARKit型を直接UI全体へ広げず、アプリ用の状態へ変換する。

```text
idle
requestingPermission
starting
tracking
limited(reason)
interrupted
failed(message)
unsupported
permissionDenied
```

#### `CameraPose`

画面表示や後続フェーズで扱いやすい値型にする。

```text
position: x, y, z（メートル）
orientation: roll, pitch, yaw（画面では度）
timestamp
```

内部計算では変換行列とラジアンを維持し、表示時だけ丸めて度へ変換する。

## 4. 画面案

カメラ映像の上に最小限のデバッグ情報を重ねる。

```text
┌─────────────────────────────┐
│ トラッキング: 正常           │
│ X: 0.14  Y: 1.22  Z: -0.83  │
│ Roll: 1° Pitch: -8° Yaw: 42°│
│                             │
│        カメラ映像            │
│                             │
│              [リセット]      │
└─────────────────────────────┘
```

権限拒否、非対応端末、セッションエラーでは、カメラ画面とは別に理由と対応方法を表示する。

## 5. ライフサイクル

- 画面表示かつ権限取得済み: セッション開始
- 画面から離れる: `session.pause()`
- バックグラウンド移行: ARKitから中断通知を受け、UIを中断状態にする
- フォアグラウンド復帰: 自動再開後の状態を監視する
- 回復できない場合: リセット操作を提供

`sessionWasInterrupted(_:)`内で追加の`pause()`は呼ばない。Appleの説明では、中断通知そのものが一時停止相当であり、そこで手動停止すると中断終了通知を受け取れなくなる可能性がある。

フェーズ1では保存済みワールドマップがないため、中断後に座標整合性が失われた場合は、`.resetTracking`と`.removeExistingAnchors`を指定してリセットする。

## 6. プラットフォーム方針

現在のターゲットはiOS、iOS Simulator、macOS、visionOSを含んでいる。しかし、VPS用の背面カメラARセッションを同一実装で全プラットフォームへ展開すると条件分岐が増え、学習目的がぼやける。

フェーズ1ではiPhone実機を主対象にすることを推奨する。

- iPhone/iPad: 実装・実機検証対象
- iOS Simulator: 非対応画面の確認のみ
- macOS/visionOS: 対象外とするか、コンパイル条件で代替画面を表示

プロジェクトの対応プラットフォーム自体を変更するか、`#if os(iOS)`で分岐するかは実装開始時に決定する。

## 7. 実装順

1. カメラ利用目的の文字列を追加
2. iOS実機をフェーズ1の対象として明確化
3. カメラ権限状態を表す型と権限確認処理を作成
4. `ARViewContainer`でカメラ映像を表示
5. `ARWorldTrackingConfiguration`を手動開始
6. トラッキング状態を日本語表示
7. `camera.transform`から位置・向きを表示
8. 中断、復帰、エラー、リセットを実装
9. UI更新を間引く
10. 対応するiPhone実機で検証

## 8. 完了条件

- 初回起動時に日本語のカメラ権限説明が表示される
- 許可後、実機で背面カメラ映像が表示される
- トラッキング状態が初期化中から正常へ変化する
- 端末を動かすとx、y、zと姿勢表示が更新される
- 動かしすぎ、暗所、無地の壁で適切な案内が表示される
- 権限拒否時にクラッシュせず案内を表示する
- バックグラウンド移行と復帰で状態が破綻しない
- リセット操作で座標原点を再設定できる
- Simulatorまたは非対応環境でクラッシュしない
- Xcodeビルドが成功する

## 9. 検証項目

### 権限

- 初回許可
- 初回拒否
- 設定アプリで許可を変更してから復帰
- 制限状態

### トラッキング

- 明るく特徴の多い場所
- 暗い場所
- 無地の壁
- 端末を急激に動かす
- 端末を約1m移動し、表示値が概ね追従するか
- 同じ場所へ戻ったときのドリフト

### ライフサイクル

- ホーム画面へ移動して復帰
- 別アプリがカメラを使用する状況
- 画面ロックと解除
- セッションリセット

## 10. 注意点

- ARKitの位置は開始時原点に対する相対値であり、GPS座標ではない。
- Euler角は表示には便利だが、姿勢計算には変換行列またはQuaternionを使用する。
- `ARSessionDelegate`の全フレームで重い処理をしない。
- フェーズ1ではカメラ画像を保存しない。
- Simulatorのみで完了判定しない。
- VPSのモデル作成は、安定して画像・姿勢・内部パラメータを取得できてから開始する。

## 11. 参照資料

- [Managing Session Life Cycle and Tracking Quality](https://developer.apple.com/documentation/arkit/managing-session-life-cycle-and-tracking-quality)
- [ARCamera](https://developer.apple.com/documentation/arkit/arcamera)
- [ARSession](https://developer.apple.com/documentation/arkit/arsession/)
- [ARView](https://developer.apple.com/documentation/realitykit/arview)
- [UIViewRepresentable](https://developer.apple.com/documentation/swiftui/uiviewrepresentable)
- [Requesting authorization to capture and save media](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)
- [Verifying Device Support and User Permission](https://developer.apple.com/documentation/arkit/verifying_device_support_and_user_permission)
- [Tracking and visualizing planes](https://developer.apple.com/documentation/arkit/tracking-and-visualizing-planes)
