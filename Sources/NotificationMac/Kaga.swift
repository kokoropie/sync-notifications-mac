import Foundation
import CryptoKit

/// Port của Kaga.php — phải giữ giống hệt bản Node (kaga.js) và Kotlin (Kaga.kt).
/// Định dạng: <b64(header [a,b,c,d])>.<rev(b64(flip(b64(mảng số)) + salt))>.<hmac-sha256 hex>
enum Kaga {
    private static let A = 3, B = 5, C = 7, D = 3

    private static func mul(_ i: Int, _ b: Int) -> Int { (i + 1) % b == 0 ? 1 : (i + 1) % b }

    private static func b64e(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func b64d(_ s: String) -> [UInt8]? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.utf8.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t).map { [UInt8]($0) }
    }

    private static func flip(_ s: [UInt8], _ c: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(s.count)
        for start in stride(from: 0, to: s.count, by: c) {
            out.append(contentsOf: s[start..<min(start + c, s.count)].reversed())
        }
        return out
    }

    private static func hmac(_ data: String, _ salt: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: SymmetricKey(data: Data(salt.utf8)))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Salt đã xử lý từ key: base64url(8 ký tự cuối của md5 hex).
    static func salt(for key: String) -> String {
        let hex = Insecure.MD5.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return b64e(Array(hex.suffix(8).utf8))
    }

    /// `salt` là kết quả của `salt(for:)`.
    static func encode(_ input: String, salt: String) -> [UInt8] {
        let s = Array(b64e(Array((salt + input).utf8)).utf8)
        var json = "["
        for (i, byte) in s.enumerated() {
            var v = Int(byte)
            if D >= 1 { v <<= (i % A) }
            if D >= 2 { v *= mul(i, B) }
            if D >= 3 { v ^= i }
            if i > 0 { json += "," }
            json += String(v)
        }
        json += "]"
        let r = flip(Array(b64e(Array(json.utf8)).utf8), C)
        let mid = String(b64e(r + Array(salt.utf8)).reversed())
        let head = "\(b64e(Array("[\(A),\(B),\(C),\(D)]".utf8))).\(mid)"
        return Array("\(head).\(hmac(head, salt))".utf8)
    }

    /// nil nếu sai salt / bị sửa / hỏng.
    static func decode(_ input: [UInt8], salt: String) -> String? {
        let parts = String(decoding: input, as: UTF8.self).components(separatedBy: ".")
        guard parts.count == 3, parts[2] == hmac("\(parts[0]).\(parts[1])", salt),
              let hb = b64d(parts[0]),
              let p = try? JSONSerialization.jsonObject(with: Data(hb)) as? [Int], p.count == 4,
              p[0...2].allSatisfy({ (1...8).contains($0) }), (0...3).contains(p[3]),
              let eb = b64d(String(parts[1].reversed())) else { return nil }
        let (a, b, c, d) = (p[0], p[1], p[2], p[3])
        let saltBytes = Array(salt.utf8)
        guard eb.count >= saltBytes.count, Array(eb.suffix(saltBytes.count)) == saltBytes,
              let jb = b64d(String(decoding: flip(Array(eb.dropLast(saltBytes.count)), c), as: UTF8.self)),
              let arr = try? JSONSerialization.jsonObject(with: Data(jb)) as? [Int] else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(arr.count)
        for (i, value) in arr.enumerated() {
            var v = value
            if d >= 3 { v ^= i }
            if d >= 2 { v /= mul(i, b) }
            if d >= 1 { v >>= (i % a) }
            guard (0...255).contains(v) else { return nil }
            bytes.append(UInt8(v))
        }
        guard let ob = b64d(String(decoding: bytes, as: UTF8.self)), ob.starts(with: saltBytes) else { return nil }
        return String(bytes: ob.dropFirst(saltBytes.count), encoding: .utf8)
    }
}
