import AVFoundation

/// カメラ権限に関する、アプリ内で扱う状態です。
enum CameraPermissionState: Equatable, Sendable {
    /// まだ権限を確認していません。
    case unknown

    /// ユーザーへ権限を要求する前の状態です。
    case notDetermined

    /// 権限ダイアログへの応答を待っています。
    case requesting

    /// カメラの使用が許可されています。
    case authorized

    /// ユーザーがカメラの使用を拒否しています。
    case denied

    /// ペアレンタルコントロールなどにより使用が制限されています。
    case restricted

    init(authorizationStatus: AVAuthorizationStatus) {
        switch authorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        @unknown default:
            self = .unknown
        }
    }

    /// ARセッションを開始できるかどうかを返します。
    var canUseCamera: Bool {
        self == .authorized
    }

    /// 画面へ表示する状態名です。
    var title: String {
        switch self {
        case .unknown:
            "確認前"
        case .notDetermined:
            "未確認"
        case .requesting:
            "確認中"
        case .authorized:
            "許可済み"
        case .denied:
            "拒否されています"
        case .restricted:
            "制限されています"
        }
    }

    /// 状態に応じてユーザーへ提示する案内です。
    var guidance: String {
        switch self {
        case .unknown:
            "カメラの利用状態を確認します。"
        case .notDetermined:
            "VPSを開始するにはカメラへのアクセス許可が必要です。"
        case .requesting:
            "カメラへのアクセス許可を確認しています。"
        case .authorized:
            "カメラを使用できます。"
        case .denied:
            "設定アプリで、このアプリのカメラアクセスを許可してください。"
        case .restricted:
            "この端末ではカメラの利用が制限されています。"
        }
    }
}
