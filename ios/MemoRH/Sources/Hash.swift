import Foundation
import CryptoKit

enum Hash {
    static func sha256Hex(_ data: Data) -> String {
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
