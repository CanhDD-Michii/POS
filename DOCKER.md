# Docker & Docker Compose — POS

Stack: **PostgreSQL 17**, **API Node** (port 3000), **frontend** (build Vite + **nginx**, port `WEB_PORT` mặc định 8080).

File `DB.sql` (dump PG 17) được **restore tự động lần đầu** khi volume database còn trống.

## Yêu cầu

- Docker Engine + Docker Compose plugin (v2)
- File `DB.sql` nằm **cùng thư mục** với `docker-compose.yml`

## Chạy nhanh

```bash
cd /path/to/POS
cp .env.example .env
# Sửa POSTGRES_PASSWORD, JWT_SECRET; nếu đổi API_PORT thì sửa luôn VITE_* cho khớp

docker compose up -d --build
```

- **Giao diện:** `http://localhost:8080` (hoặc `WEB_PORT` trong `.env`)
- **API:** `http://localhost:3000` — REST: `http://localhost:3000/api/...`
- **Ảnh upload:** `http://localhost:3000/uploads/...`
- **PostgreSQL:** `localhost:5432` (theo `.env`)

`VITE_API_BASE_URL` / `VITE_UPLOADS_ORIGIN` là URL **trình duyệt trên máy bạn** dùng để gọi API (build time). Mặc định `localhost:3000` đúng khi publish cổng API ra host như trong compose.

**Dev frontend ngoài Docker (tùy chọn):** `cd frontend && npm run dev` — dùng `frontend/.env.local` với cùng `VITE_*` nếu cần.

Dừng Docker:

```bash
docker compose down
```

Xóa volume DB (import lại `DB.sql` lần sau):

```bash
docker compose down -v
```

---

## Restore database từ `DB.sql`

### 1) Tự động (khuyến nghị — chỉ khi volume mới)

Khi thư mục dữ liệu Postgres trong volume **chưa từng khởi tạo**, image Postgres chạy các file trong `/docker-entrypoint-initdb.d/`.

- `DB.sql` được mount vào `docker-entrypoint-initdb.d/seed/DB.sql`.
- `docker/postgres/restore.sh` **xoá dòng `\restrict ...`** (meta của `pg_dump` 17) rồi pipe vào `psql`.

**Lưu ý:** Volume đã tồn tại thì init **không chạy lại** — dùng mục (2) hoặc `docker compose down -v`.

### 2) Restore thủ công (volume đã có / cập nhật dump)

```bash
sed '/^\\restrict/d' DB.sql | docker compose exec -T db psql -U postgres -d pos_db -v ON_ERROR_STOP=1
```

User/db khác:

```bash
source .env
sed '/^\\restrict/d' DB.sql | docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1
```

- `sed '/^\\restrict/d'`: bỏ dòng `\restrict` đầu file dump PG 17.
- `-v ON_ERROR_STOP=1`: lỗi SQL thì dừng.
- `-T`: pipe từ host không cần TTY.

### 3) Restore qua file trong container

```bash
docker compose cp DB.sql db:/tmp/DB.sql
docker compose exec db sh -c "sed '/^\\restrict/d' /tmp/DB.sql | psql -U postgres -d pos_db -v ON_ERROR_STOP=1"
```

---

## Biến môi trường (Docker)

| Biến | Ý nghĩa |
|------|--------|
| `POSTGRES_*` | User, password, tên DB, cổng publish ra host |
| `JWT_SECRET` | Ký JWT đăng nhập API |
| `API_PORT` | Cổng host map vào API (mặc định 3000) |
| `WEB_PORT` | Cổng host map vào nginx frontend (mặc định 8080) |
| `VITE_API_BASE_URL` | URL API khi **build** image `web` (trình duyệt gọi từ máy host) |
| `VITE_UPLOADS_ORIGIN` | Origin `/uploads` tương ứng |

Đổi `API_PORT` hoặc domain → sửa `VITE_*` trong `.env` rồi **`docker compose build web --no-cache`** (hoặc `up --build`).

---

## Xử lý sự cố

- **`pos-db` unhealthy / `dependency failed to start`:** xem log `docker compose logs db`. Lần đầu restore `DB.sql` có thể **vài phút** — đã tăng `start_period` / `retries` trong compose. Nếu restore **lỗi SQL** (file dump lệch phiên bản), init hỏng: chạy `docker compose down -v` rồi `up` lại sau khi sửa dump. Healthcheck dùng `pg_isready` với user/db từ `.env` (mặc định `postgres` / `pos_db`).
- **API không kết nối DB:** `docker compose logs db api`, đợi `db` healthy.
- **Frontend (container) không gọi được API:** kiểm tra `VITE_API_BASE_URL` / `VITE_UPLOADS_ORIGIN` khớp cổng `API_PORT` trên host, rồi build lại `web`.
- **Lỗi build API (bcrypt):** thử image `node:20-bookworm` + `build-essential` trong `backend/Dockerfile`.

---

## Cấu trúc file liên quan

```
docker-compose.yml          # db + api + web
docker/postgres/restore.sh  # Init: import DB.sql (lần đầu)
backend/Dockerfile
frontend/Dockerfile
frontend/nginx.conf
.env.example
DB.sql
```
