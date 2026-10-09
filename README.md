# Sync Notification – Mac

<p align="center"><img src="https://raw.githubusercontent.com/kokoropie/sync-notifications/main/assets/logo-bell.png" width="96" alt="Sync Notification"></p>

App menu bar cho macOS: nhận thông báo và cuộc gọi từ điện thoại Android (qua server) và hiện thành thông báo trên Mac, kèm đồng bộ clipboard hai chiều.

Thuộc hệ thống [Sync Notification](https://github.com/kokoropie/sync-notifications):
[server](https://github.com/kokoropie/sync-notifications-server) · [android](https://github.com/kokoropie/sync-notifications-android) · **mac**

Yêu cầu: macOS 14 (Sonoma) trở lên. Hỗ trợ cả Apple Silicon và Intel.

## Cài đặt

1. Tải file `SyncNotification-<phiên bản>.dmg` ở trang [Releases](../../releases).
2. Mở DMG, kéo **Sync Notification** vào **Applications**.
3. Mở app lần đầu theo hướng dẫn ở mục [Gatekeeper](#gatekeeper--cảnh-báo-không-xác-minh-được-nhà-phát-triển) bên dưới.
4. Cho phép thông báo khi macOS hỏi (hoặc bật trong Cài đặt hệ thống → Thông báo → Sync Notification).
5. Bấm icon chuông trên menu bar → **Cài đặt…** và nhập:
   - **URL server**, ví dụ `https://sync.example.com`
   - **Account key** (`ntf_…`), do người quản trị server tạo bằng `npm run key:create`
   - Tên thiết bị (tùy chọn)

Biểu tượng chuông có gạch chéo nghĩa là chưa kết nối được server.

## Gatekeeper – cảnh báo "không xác minh được nhà phát triển"

Bản phát hành chưa được **công chứng (notarize)** bởi Apple, vì việc đó cần tài khoản Apple Developer trả phí. Vì vậy lần đầu mở, macOS Gatekeeper có thể báo:

> "Sync Notification" không thể mở vì Apple không thể kiểm tra phần mềm độc hại.
> hoặc: "Sync Notification" bị hỏng và không thể mở.

Đây là hành vi bình thường với app tải từ Internet mà chưa công chứng, không có nghĩa là file hỏng. Chọn **một** trong các cách (chỉ cần làm một lần):

### Cách 1: Mở bằng chuột phải (nên dùng)
1. Mở thư mục **Applications**.
2. **Chuột phải** (hoặc Control-click) vào **Sync Notification** → **Mở**.
3. Trong hộp thoại, bấm **Mở**.

### Cách 2: Cho phép trong Cài đặt hệ thống (macOS 15 trở lên)
1. Mở app một lần (sẽ bị chặn), rồi vào **Cài đặt hệ thống → Quyền riêng tư & Bảo mật**.
2. Kéo xuống phần **Bảo mật**, bấm **Vẫn mở** cạnh tên app, nhập mật khẩu nếu được hỏi.

### Cách 3: Gỡ cờ cách ly bằng Terminal
Dùng khi app báo "bị hỏng":

```bash
xattr -dr com.apple.quarantine "/Applications/Sync Notification.app"
```

> Chỉ làm các bước trên với bản bạn tải từ trang Releases của repo này (hoặc tự build). Đừng gỡ cách ly cho file không rõ nguồn gốc.

### Kiểm tra file tải về
Mỗi bản phát hành đều được build tự động bằng GitHub Actions từ mã nguồn trong repo. Bạn có thể tự build để chắc chắn (xem bên dưới).

## Tự cập nhật

Menu bar → **Kiểm tra cập nhật…** (và tự kiểm tra mỗi 24 giờ khi mở app, tắt được trong Cài đặt). App tải DMG mới từ GitHub Releases, kiểm tra chữ ký, thay thế chính nó rồi mở lại. Vì file do chính app tải nên **không bị gắn cờ quarantine** và Gatekeeper không hỏi lại: chỉ cần vượt Gatekeeper một lần ở lần cài đầu. Nếu app ký bằng chứng chỉ cố định (xem dưới), bản mới bắt buộc phải cùng chứng chỉ, nếu không sẽ bị từ chối.

## Về ký và công chứng (cho người phát hành)

| | Ad-hoc (mặc định) | Chứng chỉ tự ký cố định | Developer ID + công chứng |
|---|---|---|---|
| Cần Apple Developer (99 USD/năm) | Không | Không | Có |
| Danh tính app giữ nguyên giữa các bản | Không | **Có** (không bị hỏi lại quyền thông báo) | Có |
| Cảnh báo Gatekeeper khi tải thủ công | Có | Có | Không |
| Tự cập nhật không hỏi Gatekeeper | Có | Có | Có |

### Chứng chỉ tự ký cố định (khuyến nghị nếu không có Apple Developer)
Chạy **một lần** trên máy bạn:

```bash
./scripts/make-cert.sh
```

Script tạo `sync-notification-cert.p12` (hiệu lực 10 năm), in `MACOS_CERT_PASSWORD` và copy `MACOS_CERT_P12_BASE64` vào clipboard. Thêm hai secret đó vào repo (Settings → Secrets and variables → Actions). **Giữ file .p12 ở nơi an toàn và đừng tạo lại**: đổi chứng chỉ thì bản mới có danh tính khác, tự cập nhật sẽ từ chối và người dùng phải cài lại tay một lần.

### Developer ID + công chứng
Thêm các secrets sau (workflow `.github/workflows/release.yml` tự dùng nếu có, tự bỏ qua nếu thiếu):

| Secret | Nội dung |
|---|---|
| `MACOS_CERT_P12_BASE64` | Chứng chỉ **Developer ID Application** xuất ra `.p12`, mã hóa base64 (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERT_PASSWORD` | Mật khẩu của file `.p12` |
| `APPLE_ID` | Apple ID dùng để công chứng |
| `APPLE_TEAM_ID` | Team ID (10 ký tự) |
| `APPLE_APP_PASSWORD` | [Mật khẩu dành riêng cho app](https://support.apple.com/102654) của Apple ID |

Có hai `MACOS_CERT_*` thì app và DMG được ký (Developer ID nếu chứng chỉ là Developer ID, ngược lại ký bằng chứng chỉ tự ký); thêm ba secret còn lại thì DMG Developer ID được công chứng và staple.

## Quyền riêng tư

- App chỉ kết nối tới **server do bạn cấu hình**; không gửi dữ liệu đi đâu khác.
- Lịch sử thông báo lưu trên máy ở `~/Library/Application Support/NotificationMac/history.json`, icon app ở `~/Library/Caches/NotificationMac/`.
- Clipboard: nội dung nào được đánh dấu bí mật bởi trình quản lý mật khẩu (`org.nspasteboard.ConcealedType`) sẽ **không** được gửi đi. Tắt hẳn bằng công tắc "Đồng bộ clipboard" trong Cài đặt.

## Tự build

Cần Xcode (hoặc Command Line Tools) với Swift 5.9+.

```bash
./build.sh                      # build/NotificationMac.app (ký ad-hoc, kiến trúc máy hiện tại)
UNIVERSAL=1 ./build.sh          # cả arm64 + x86_64
VERSION=1.0.0 ./scripts/make-dmg.sh   # build/SyncNotification-1.0.0.dmg
open build/NotificationMac.app
```

Biến tùy chọn cho `build.sh`: `VERSION`, `UNIVERSAL=1`, `SIGN_IDENTITY="Developer ID Application: …"` hoặc tên chứng chỉ tự ký.

## Phát hành bằng GitHub Actions

- Dùng script: `./scripts/release.sh 1.0.0` (hoặc `patch` / `minor` / `major` để tăng từ tag mới nhất; thêm `-n` để chạy thử không tạo tag). Script kiểm tra đang ở `main`, không còn thay đổi chưa commit, đã đồng bộ `origin/main`, rồi tạo tag `v1.0.0` và push.
- Hoặc thủ công: push tag dạng `v*` → workflow build DMG và đăng lên Releases.
- Pull request hoặc chạy tay (`workflow_dispatch`) → build DMG, lưu ở mục Artifacts, không phát hành.

## Tính năng

- Thông báo của app Android hiện trên Mac, kèm logo app (ảnh bên phải thông báo).
- Cuộc gọi đến, cuộc gọi nhỡ.
- **Danh sách thông báo**: lịch sử nhóm theo app, có tìm kiếm và xóa theo nhóm.
- **Whitelist app**: chọn app được hiện banner; dùng chung với Android theo account key.
- Clipboard hai chiều với Android.
