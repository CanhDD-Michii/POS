# Docker & Docker Compose — POS (local)

Chỉ Docker hóa **PostgreSQL 17** và **API Node** (port 3000). **Frontend chạy trên máy** bằng Vite (`npm run dev`) — không dùng Nginx/container web.

File `DB.sql` (dump PG 17) được **restore tự động lần đầu** khi volume database còn trống.

## Yêu cầu

- Docker Engine + Docker Compose plugin (v2)
- File `DB.sql` nằm **cùng thư mục** với `docker-compose.yml`
- Node.js trên máy để chạy frontend (khuyến nghị 20+)

## Chạy nhanh

**1) Database + API**

```bash
cd /path/to/POS
cp .env.example .env
# Sửa POSTGRES_PASSWORD và JWT_SECRET trong .env

docker compose up -d --build
```

- API: `http://localhost:3000` (REST dưới `http://localhost:3000/api/...`)
- Ảnh upload: `http://localhost:3000/uploads/...`
- PostgreSQL: `localhost:5432` (theo `.env`)

**2) Frontend (máy local)**

```bash
cd frontend
npm install
# Mặc định api.js dùng http://localhost:3000/api — đủ nếu API map cổng 3000
npm run dev
```

Mở URL Vite in ra (thường `http://localhost:5173`).

Nếu API chạy cổng khác, tạo `frontend/.env.local`:

```env
VITE_API_BASE_URL=http://localhost:3000/api
VITE_UPLOADS_ORIGIN=http://localhost:3000
```

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

Frontend: cấu hình qua `frontend/.env.local` (`VITE_*`), không nằm trong Compose.

---

## Xử lý sự cố

- **API không kết nối DB:** `docker compose logs db api`, đợi `db` healthy.
- **Frontend không gọi được API:** CORS đang mở; kiểm tra URL trong `frontend/src/config/constants.js` / `.env.local` và cổng `API_PORT`.
- **Lỗi build API (bcrypt):** thử image `node:20-bookworm` + `build-essential` trong `backend/Dockerfile`.

---

## Cấu trúc file liên quan

```
docker-compose.yml          # db + api
docker/postgres/restore.sh  # Init: import DB.sql (lần đầu)
backend/Dockerfile
.env.example
DB.sql
```
