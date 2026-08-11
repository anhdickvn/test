# ChatApp (iOS) — Minecraft chat client (kiểu ChatCraft)

App SwiftUI đơn giản, chỉ tập trung vào chat Minecraft — không có tính năng chat AI.

Có 2 tab:
- **Accounts**: quản lý danh sách username offline/cracked (thêm/xoá, có thể tạo
  nhiều tài khoản khác nhau để dùng cho nhiều server khác nhau).
- **Servers**: quản lý danh sách server đã lưu (tên, địa chỉ, cổng, tài khoản dùng để
  đăng nhập), bấm vào 1 server để mở màn hình chat, bấm "Kết nối" để mở kết nối TCP
  thật tới server, nói đúng giao thức Minecraft Java Edition (handshake → login →
  play), nhận toàn bộ sự kiện chat/hệ thống theo thời gian thực (packet Chat Message,
  Keep Alive, Disconnect...) và gửi tin nhắn lên server.

Giới hạn hiện tại: chỉ hỗ trợ server offline-mode (không yêu cầu tài khoản Microsoft/Mojang thật),
không có bản đồ mini-map, không di chuyển nhân vật, không xem inventory — chỉ chat. Toàn bộ logic
giao thức nằm trong `Sources/ChatApp/MCClient.swift`, `MCVarInt.swift` và `MCModels.swift`.

Client tự dò protocol version của server trước khi login (giống Server List Ping). Nếu server
không chạy đúng **Minecraft 1.12 – 1.12.2**, app sẽ báo lỗi ngay lập tức "chưa hỗ trợ phiên bản
này" thay vì cố kết nối rồi treo/lỗi khó hiểu — vì ID gói tin (packet ID) của Minecraft đổi khác
nhau giữa các phiên bản (đặc biệt từ 1.13 và 1.19 trở đi), dùng nhầm bảng ID sẽ khiến app đọc/gửi
chat sai chứ không chỉ là "không vào được". Muốn hỗ trợ thêm phiên bản khác thì cần thêm bảng ID
gói tin riêng cho từng phiên bản đó trong `MCClient.swift` (`handleLoginPacket`/`handlePlayPacket`).

Nếu server yêu cầu tài khoản Minecraft/Microsoft thật (online-mode), app cũng báo lỗi ngay thay vì
treo — trường hợp này ngoài phạm vi hỗ trợ hiện tại (cần thêm luồng xác thực Microsoft OAuth riêng).

---

## PHẦN 1 — Build ra file .ipa bằng GitHub Actions (không cần Mac)

### Bước 1: Đưa code lên GitHub
1. Tạo tài khoản GitHub (nếu chưa có): https://github.com
2. Tạo 1 repo mới, ví dụ đặt tên `ChatApp` (để **Private** cho an toàn API key/cấu hình).
3. Upload toàn bộ nội dung thư mục này lên repo đó. Cách dễ nhất nếu không quen `git`:
   - Vào repo trên GitHub → "Add file" → "Upload files" → kéo thả cả thư mục vào.
   - Hoặc cài Git for Windows, mở PowerShell tại thư mục này rồi chạy:
     ```
     git init
     git add .
     git commit -m "init"
     git branch -M main
     git remote add origin https://github.com/<username>/ChatApp.git
     git push -u origin main
     ```

### Bước 2: Chạy workflow build
1. Vào repo trên GitHub → tab **Actions**.
2. Chọn workflow **"Build IPA"** → bấm **"Run workflow"** → **Run workflow** (nhánh `main`).
3. Đợi khoảng 3–5 phút (macOS runner của GitHub, miễn phí trong giới hạn hàng tháng).
4. Khi job chạy xong (dấu tích xanh), bấm vào job đó → kéo xuống mục **Artifacts** →
   tải file **ChatApp-ipa.zip** → giải nén ra được **ChatApp.ipa**.

File `.ipa` này **chưa được ký (unsigned)** — bạn không cài trực tiếp qua iTunes/Finder được.
Bước tiếp theo dùng AltStore/SideStore để tự ký bằng Apple ID miễn phí của bạn rồi cài lên máy.

---

## PHẦN 2 — Cài lên iPhone bằng AltStore (dùng Windows, Apple ID miễn phí)

### Chuẩn bị
- Tải **iTunes for Windows** từ trang chủ Apple (KHÔNG lấy bản Microsoft Store) — AltServer cần driver Apple Mobile Device từ đây.
- Tải **AltServer** cho Windows: https://altstore.io
- 1 Apple ID (dùng ID thường của bạn cũng được, không cần trả phí).

### Các bước
1. Cài iTunes for Windows xong, mở nó lên 1 lần để cài driver, rồi tắt cũng được.
2. Cài AltServer, chạy nó (icon nằm ở khay hệ thống, gần đồng hồ).
3. Cắm iPhone vào máy bằng cáp, mở khóa máy, chọn **Trust** khi được hỏi.
4. Click icon AltServer ở khay hệ thống → **Install AltStore** → chọn iPhone của bạn →
   nhập Apple ID + mật khẩu (dùng App-specific password nếu bật 2FA, AltServer sẽ hướng dẫn).
5. Trên iPhone: **Settings → General → VPN & Device Management** → tin tưởng (Trust)
   profile của Apple ID bạn vừa dùng.
6. Mở app **AltStore** vừa được cài trên iPhone → tab **My Apps** → góc trên bên trái có nút **+**
   → chọn file **ChatApp.ipa** đã tải ở Phần 1 (chuyển file qua iPhone qua AirDrop/iCloud Drive/cáp).
7. AltStore sẽ tự ký và cài app — xong, mở app ra dùng bình thường.

### Duy trì app không bị hết hạn (7 ngày/lần)
- Apple ID miễn phí giới hạn app chỉ chạy được 7 ngày rồi cần ký lại.
- AltServer sẽ **tự động ký lại khi iPhone và máy tính Windows cùng chung 1 mạng Wi-Fi**
  (AltServer chạy nền trên Windows). Nên cứ để AltServer chạy nền khi ở nhà là app tự làm mới.
- Muốn chủ động: mở app **AltStore** trên iPhone → **My Apps** → **Refresh**.

### Nếu muốn ít lệ thuộc máy tính hơn: SideStore
SideStore (https://sidestore.io) là bản thay thế cho phép **tự làm mới app trên chính
iPhone** mà không cần bật máy tính mỗi 7 ngày (dùng cơ chế VPN nội bộ trên máy).
Bước cài đặt ban đầu vẫn cần 1 lần dùng máy tính (Windows/Mac) để pair, sau đó gần như
không cần đụng tới máy tính nữa. Nếu bạn thấy việc bật AltServer mỗi tuần phiền, cân nhắc
chuyển sang SideStore — cách cài chi tiết xem tại trang chủ của họ vì quy trình có thể
thay đổi theo phiên bản iOS mới.

---

## Tuỳ chỉnh
- Đổi tên app / bundle id: sửa trong `project.yml`.
- Đổi giao diện, thêm hỗ trợ nhiều phiên bản protocol, lưu log chat ra file,...
  đều sửa trong các file `.swift` ở `Sources/ChatApp/`.


## Bản cập nhật GUI / texture / chạy nền

- GUI server đọc `display.Name` và `display.Lore` từ NBT của từng item.
- Item có menu `...` với **Chuột trái / Chuột phải / Xem tooltip-Lore**; trên iPad/iPhone có thêm context menu.
- Server gửi Resource Pack sẽ được app tự tải, giải nén và dùng PNG/model trong `assets/minecraft` để hiển thị icon. Có nút `📦` để người dùng import `.zip` texture pack thủ công nếu server không gửi pack.
- Khi chưa có texture phù hợp, app vẫn fallback sang emoji để GUI không bị mất item.
- Socket có cơ chế tự reconnect khi mạng chập chờn, bao gồm POSIX error 53, thay vì giữ trạng thái lỗi và làm người chơi bị văng.
- Khi app đi background, `UIBackgroundModes=audio` + silent audio được dùng để cố giữ TCP sống. **Force-quit bằng cách vuốt app khỏi App Switcher vẫn không thể được iOS cho phép chạy nền vô hạn**; chỉ bấm Home/chuyển app mới có thể giữ phiên theo cơ chế này.
- Nút `Ngắt` là cách chủ động disconnect. App không còn tự disconnect chỉ vì `MCChatView` `onDisappear`.

> Lưu ý: icon vanilla đầy đủ nhất nên dùng resource pack 1.12.x tương ứng. App không nhúng nguyên bộ asset Minecraft vào IPA; texture server/user-provided được tải hoặc import lúc chạy.
