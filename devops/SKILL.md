---
name: devops
description: Standards for container split, Dockerfile, docker-compose runtime, and CI build/push to GHCR with pull-only VPS deploy. Use when adding a service, changing Docker/CI/compose, or reviewing deploy setup for compliance.
license: Complete terms in LICENSE.txt
---

# DevOps — tách container, đóng image, CI build, VPS chỉ pull + up

Skill này chuẩn hoá quy trình đưa ứng dụng lên VPS yếu: đóng image duy nhất trên GitHub Actions, đẩy lên GHCR theo tag nhánh, VPS chỉ kéo image về và chạy. Áp dụng cho mọi team, mọi stack phổ biến (Node.js/Next.js/Nuxt, Python, Go, Java). Mọi giá trị cụ thể dưới đây (tên image, port, tên service) chỉ là minh hoạ — khi áp dụng, thay bằng giá trị thật của repo.

Thuật ngữ giữ tiếng Anh: image, tag, stage, healthcheck, stack, tunnel, registry cache, pull policy.

## 1. Luật bất biến

1. **Build duy nhất trên CI.** VPS yếu chỉ `pull` + `up` — cấm khai `build:` trong file compose chạy production.
2. **Một service là một image immutable theo tag nhánh.** Tag ánh xạ một-một với nhánh: `main` sinh `:prod` (kèm `:latest`), `dev` sinh `:dev`. Không dùng tag trôi nổi cho production cần tái hiện.
3. **Secret chỉ service cần giữ.** Service API giữ chuỗi kết nối cơ sở dữ liệu, khoá API, secret OAuth. Ứng dụng web trình diễn chỉ giữ URL trỏ sang API, không chạm trực tiếp vào cơ sở dữ liệu.
4. **Compose là mô tả runtime duy nhất.** Image, ánh xạ port, healthcheck, volume, network, biến môi trường inline đều nằm trong một file `docker-compose.yml`. Không mô tả runtime ở nơi khác rồi để lệch nhau.
5. **CI là chuẩn cho tag.** Tài liệu nói tag nào thì workflow phải sinh đúng tag đó; tài liệu sai thì sửa tài liệu, không sửa CI cho khớp lối viết sai.
6. **Không commit file env.** Mọi `.env*` chỉ nằm trên máy dev, trên UI của công cụ quản trị VPS, hoặc trong secret của CI. Không đưa secret thô vào image (build arg), vào compose, hay vào log CI.
7. **Phát hiện lệch thì sửa đúng phạm vi, verify xanh** (xem mục 8). Không refactor ngoài phạm vi của task deploy.

## 2. Bước 1 — khảo sát codebase

Đọc theo checklist, output là bảng evidence `file:line`. Không kết luận bằng đoán mò.

| Đọc gì | Tìm gì | Ghi nhận điều gì |
|---|---|---|
| `*/package.json` (mục `scripts`) | runtime + port dev + lệnh build/start | framework nào, lệnh khởi động production là gì |
| `*/next.config.ts` hoặc `*/nuxt.config.ts` | `output: standalone` hay server thường | có thư mục standalone sau build không |
| `*/Dockerfile` | số stage, user chạy, CMD, port expose | đã multi-stage, đã non-root, đã có healthcheck chưa |
| `*/go.mod` + entrypoint `cmd/*/main.go` | module, bản Go, port mặc định | binary tĩnh hay cần runtime ngoài |
| `*/requirements.txt` / `*/pyproject.toml` | trình chạy (`uvicorn`, `gunicorn`) | cần builder riêng để cài dependency không |
| `*/pom.xml` / `*/build.gradle` | bản Java, file `jar` đầu ra | chạy bằng `java -jar` trên image JRE gọn |
| `*/.env.example` | secret nằm ở đâu | service nào giữ secret, service nào chỉ giữ URL |
| `docker-compose.yml` | services, image, port, healthcheck, volume | có `build:` sót không, tag có theo biến `TAG` không |
| `.github/workflows/*.yml` | trigger, matrix, tag | nhánh nào sinh tag nào, có deploy trong CI không |
| `*/.dockerignore` | có file này mỗi context không | context có lọt `node_modules`, `.git`, thư mục build không |

Cây quyết định nhận diện runtime GENERIC:

- Có `output: standalone` và sinh `server.js` sau build → **Next/Nuxt standalone**: image multi-stage, chạy `node server.js`, cần bind `0.0.0.0` (xem mục 4).
- Có `package.json` + lệnh `node server.js` / `npm start` nhưng không có standalone → **Node server thường**: image multi-stage, copy `node_modules` production hoặc chạy `npm ci --omit=dev`, CMD dạng exec-form.
- Có `go.mod` và build bằng `CGO_ENABLED=0 go build` → **Go binary tĩnh**: image hai stage (builder Go + runner tối giản), khuyến nghị non-root và `HEALTHCHECK` bắt buộc.
- Có `requirements.txt` / `pyproject.toml` và chạy `uvicorn` / `gunicorn` → **Python server**: image hai stage (builder cài dependency + runner slim), chạy non-root, CMD exec-form, quản lý dependency bằng `venv` hoặc `uv`.
- Có `pom.xml` / `build.gradle` và file `jar` → **Java jar**: image hai stage (builder Maven/Gradle + runner JRE gọn), chạy non-root bằng `java -jar`.
- Còn lại (web tĩnh, server đơn giản) → giữ một image tối thiểu, vẫn phải có healthcheck và non-root; không chế biến thành ngoại lệ để né chuẩn.

## 3. Bước 2 — tách container

- **Mỗi deployable là một container.** Một ứng dụng web, một API, một site công khai là ba deployable khác nhau thì là ba container, ba image. Không nhét hai runtime vào một image.
- Ví dụ minh hoạ (giá trị trung tính): service `web` (ứng dụng web) + service `api` (API phía sau) + service `worker` (xử lý nền) là ba services, ba image `ghcr.io/<owner>/<repo>-web|api|worker`.
- Tách thêm container khi: tác vụ nền có đời sống độc lập (worker, cron), tiến trình phụ cần scale riêng, tiến trình realtime (socket, SSE hub) cần tài nguyên riêng, hoặc tunnel/reverse-proxy cần vòng đời và quyền riêng.
- Không tách theo chức năng nghiệp vụ (ví dụ tách riêng xác thực, tách riêng đơn hàng) khi vẫn chung một deployable — đó là việc của code, không phải của container.
- Giao tiếp giữa container qua **tên service** trong network của compose (ví dụ `API_URL=http://api:8080`), không hardcode địa chỉ IP, không gọi vòng qua domain public từ trong compose.

## 4. Bước 3 — Dockerfile chuẩn

Nguyên tắc chung cho mọi runtime: ít stage nhưng đủ (builder + runner), layer cài dependency đứng trước layer copy code để tận dụng cache, chạy bằng user thường (non-root), CMD dạng exec-form (JSON array), `HEALTHCHECK` bắt buộc, không nhúng secret vào image, port chỉ là minh hoạ (ví dụ `3000`, `8080`).

### 4.1 Node multi-stage (Next.js/Nuxt standalone hoặc Node server thường)

```dockerfile
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production PORT=3000 HOSTNAME=0.0.0.0
RUN addgroup -S -g 1001 nodejs && adduser -S -u 1001 -G nodejs appuser
COPY --from=builder --chown=appuser:nodejs /app/.next/standalone ./
COPY --from=builder --chown=appuser:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=appuser:nodejs /app/public ./public
USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD node -e "require('http').get('http://127.0.0.1:3000/',r=>process.exit(r.statusCode===200||r.statusCode===307||r.statusCode===308?0:1)).on('error',()=>process.exit(1))"
CMD ["node", "server.js"]
```

Lưu ý: với Next.js standalone, `HOSTNAME=0.0.0.0` là bắt buộc — framework bind theo biến này, còn Docker tự đặt `HOSTNAME` thành ID container nên thiếu biến này server chỉ nghe IP container, healthcheck gọi localhost sẽ bị từ chối kết nối. Build production không cần secret: nội dung động do lớp proxy runtime chuyển tiếp theo biến môi trường trỏ sang API.

### 4.2 Go binary tĩnh (non-root + HEALTHCHECK bắt buộc)

```dockerfile
FROM golang:1.24-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/api ./cmd/api
FROM alpine:3.20
WORKDIR /srv
RUN addgroup -S -g 1001 appgroup && adduser -S -u 1001 -G appgroup appuser
COPY --from=builder /out/api ./api
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD wget -qO- http://localhost:8080/healthz || exit 1
CMD ["./api"]
```

Lưu ý: giữ nguyên entrypoint thật của repo (`./cmd/api` ở trên chỉ là minh hoạ); port `8080` là minh hoạ, port thật do biến môi trường quyết định. Thiếu `USER` (chạy root) hoặc thiếu `HEALTHCHECK` là lệch chuẩn, phải bổ sung.

### 4.3 Python gọn (builder + runner slim, non-root)

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt
FROM python:3.12-slim AS runner
WORKDIR /srv
RUN addgroup --gid 1001 appgroup && adduser --uid 1001 --gid 1001 --disabled-password appuser
COPY --from=builder /install /usr/local
COPY ./src ./src
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz').status==200 else 1)"
CMD ["python", "-m", "src.main"]
```

Lưu ý: module khởi động (`src.main` ở trên) chỉ là minh hoạ, thay bằng entry thật của repo. Dùng `--no-cache-dir` để image gọn; nếu dùng `uv` thì stage builder cài bằng `uv sync`, stage runner chỉ copy `.venv` và code.

## 5. Bước 4 — docker-compose.yml chuẩn

Mẫu đầy đủ với ba service trung tính (`web`, `api`, `worker`). Tên image, port, tên volume dưới đây là minh hoạ — thay bằng giá trị thật của repo khi áp dụng.

```yaml
services:
  api:
    image: ghcr.io/<owner>/<repo>-api:${TAG:-latest}
    restart: unless-stopped
    pull_policy: always
    environment:
      PORT: 8080
      DATABASE_URL: ${DATABASE_URL}
      MEDIA_DIR: ${MEDIA_DIR:-/srv/data/media} # đổi MEDIA_DIR thì đổi luôn target của volume
    ports:
      - "${API_PORT:-8080}:8080"
    volumes:
      - app-data:/srv/data/media
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3
  web:
    image: ghcr.io/<owner>/<repo>-web:${TAG:-latest}
    restart: unless-stopped
    pull_policy: always
    environment:
      NODE_ENV: production
      PORT: 3000
      HOSTNAME: 0.0.0.0
      API_URL: ${API_URL:-http://api:8080}
    ports:
      - "${WEB_PORT:-3000}:3000"
    healthcheck:
      test: ["CMD", "node", "-e", "require('http').get('http://127.0.0.1:3000/',r=>process.exit(r.statusCode===200||r.statusCode===307||r.statusCode===308?0:1)).on('error',()=>process.exit(1))"]
      interval: 30s
      timeout: 5s
      start_period: 15s
      retries: 3
  worker:
    image: ghcr.io/<owner>/<repo>-worker:${TAG:-latest}
    restart: unless-stopped
    pull_policy: always
    environment:
      API_URL: ${API_URL:-http://api:8080}
      QUEUE_URL: ${QUEUE_URL}
    volumes:
      - app-data:/srv/data/media
    healthcheck:
      test: ["CMD-SHELL", "pgrep -f worker || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
volumes:
  app-data:
```

Quy tắc: không khai `build:` trong compose production; image luôn từ registry với `${TAG:-latest}` để stack prod/dev chỉ khác nhau biến `TAG`. Không đặt `container_name` cố định — compose tự sinh tên `<project>-<service>-N` nên hai stack prod+dev sống chung một host được; chỉ đặt `container_name` khi thật sự cần và phải tham số hoá (`${STACK_NAME:-my-app}-api`). `pull_policy: always` để công cụ quản trị VPS luôn lấy image mới nhất của tag khi redeploy; `restart: unless-stopped` để container tự sống lại sau reboot. Gọi nhau qua tên service (`http://api:8080`), không hardcode IP, không gọi vòng qua domain public. Biến môi trường truyền inline ở mục `environment:` (không dùng `env_file:` cho production — env do giao diện quản trị stack cấp khi deploy). Port ngoài map qua biến (`${WEB_PORT}`, `${API_PORT}`) để hai stack chung một host không đụng port; port trong container là port ứng dụng thật sự nghe. Healthcheck dùng `127.0.0.1` cho image Node Alpine (tránh phân giải `localhost` ra `::1` gây fail oan); chấp nhận thêm `307`/`308` nếu `/` là redirect.

Bẫy thường gặp: container nghe port khác port dev (ví dụ dev chạy một port, production chạy port khác) — lấy port container làm chuẩn cho `EXPOSE` và vế phải của `ports:`, không copy port dev vào compose. Thiếu `HOSTNAME=0.0.0.0` cho Next.js standalone: healthcheck gọi localhost bị từ chối kết nối dù app vẫn sống (xem mục 4.1). Volume ghi dữ liệu (upload, media, sqlite) phải là volume đặt tên để sống sót qua redeploy; không mount bind đường dẫn máy dev vào VPS. Service `worker` không mở port ra ngoài; chỉ cần env trỏ sang `api` và dùng chung volume khi cần đọc file.

## 6. Bước 5 — .github/workflows chuẩn

Mẫu workflow: trigger hai nhánh `main` + `dev` kèm chạy tay, matrix theo từng service, đăng nhập GHCR bằng `GITHUB_TOKEN`, tag theo nhánh, build `linux/amd64`, cache registry, không deploy trong CI.

```yaml
name: deploy
on:
  push:
    branches: [main, dev]
  workflow_dispatch:
permissions:
  contents: read
  packages: write
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: true
env:
  REGISTRY: ghcr.io
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        include:
          - { service: "web", context: "./web", dockerfile: "./web/Dockerfile" }
          - { service: "api", context: "./api", dockerfile: "./api/Dockerfile" }
          - { service: "worker", context: "./worker", dockerfile: "./worker/Dockerfile" }
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Compute image name
        run: echo "IMAGE=${{ env.REGISTRY }}/${GITHUB_REPOSITORY,,}-${{ matrix.service }}" >> $GITHUB_ENV
      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ env.IMAGE }}
          tags: |
            type=raw,value=prod,enable=${{ github.ref == 'refs/heads/main' }}
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}
            type=raw,value=dev,enable=${{ github.ref == 'refs/heads/dev' }}
      - uses: docker/build-push-action@v6
        with:
          context: ${{ matrix.context }}
          file: ${{ matrix.dockerfile }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          platforms: linux/amd64
          cache-from: type=registry,ref=${{ env.IMAGE }}:buildcache
          cache-to: type=registry,ref=${{ env.IMAGE }}:buildcache,mode=max
```

Quy ước tag-nhánh: push `main` sinh `:prod` kèm `:latest` (stack prod đặt `TAG=prod`); push `dev` sinh `:dev` (stack dev đặt `TAG=dev`). CI chỉ build và đẩy image — việc kéo image về và chạy là của VPS (mục 7). Thêm service mới thì thêm một dòng vào matrix, không copy cả job.

## 7. Bước 6 — VPS: hai cách chạy + checklist sau deploy

VPS chỉ pull image đã build sẵn rồi up. Hai cách đều hợp lệ, chọn một theo đội ngũ quản trị; không ép dùng công cụ nào.

### Cách A — Portainer stack (kéo compose + env trên UI)

Tạo hai stack từ cùng file compose của repo (tham chiếu theo nhánh): stack prod trỏ nhánh `main` kèm env `TAG=prod`; stack dev trỏ nhánh `dev` kèm env `TAG=dev`. Cấp env qua **mục environment của stack trên giao diện Portainer**, không commit file env: `TAG`, các `*_PORT`, chuỗi kết nối cơ sở dữ liệu, URL trỏ giữa service, secret OAuth/AI. Hai stack chung host phải đặt port ngoài khác nhau. Nhấn pull + redeploy trên UI sau mỗi lần CI build xong.

### Cách B — docker compose thuần qua SSH

Copy file `docker-compose.yml` lên VPS (một thư mục mỗi stack, ví dụ `/srv/my-app-prod` và `/srv/my-app-dev`). Đặt file `.env` cạnh compose trên VPS (không commit): khai `TAG=prod` (hoặc `TAG=dev`), các `*_PORT`, secret, URL nội bộ. Chạy `TAG=prod docker compose up -d` (stack dev dùng `TAG=dev`), cập nhật bằng `docker compose pull && docker compose up -d`.

### Tunnel / reverse-proxy trỏ domain

Đặt tunnel hoặc reverse-proxy phía trước compose, trỏ từng domain về đúng port ngoài đã map: domain API về service `api`, domain web về service `web`. Worker không expose domain. Ghi địa chỉ tunnel trong báo cáo deploy, không link tới tài liệu chưa tồn tại.

### Checklist sau deploy

1. Healthcheck mọi service xanh; `docker ps` hiện `Up (healthy)`.
2. Đọc log ngay sau up: service fail-fast vì thiếu env (ví dụ thiếu chuỗi kết nối cơ sở dữ liệu) thì bổ sung env rồi redeploy, không sửa code cho chạy thiếu cấu hình.
3. Mở domain kiểm tra trang chính và một mutation mẫu (ví dụ tạo một bản ghi) để xác nhận biến URL nội bộ giữa các service đã đúng.
4. Kiểm tra volume dữ liệu còn nguyên sau redeploy (tải lại file đã upload trước đó).

## 8. Bước 7 — rà soát theo chuẩn (review checklist)

| # | Check | Cách verify (pattern generic, chạy được ở mọi repo) |
|---|---|---|
| 1 | Compose production không có `build:` | `rg "build:" docker-compose.yml` phải trống |
| 2 | Tag CI khớp compose | `rg "value=prod\|value=latest\|value=dev" .github/workflows` có đủ ba tag; `rg "TAG" docker-compose.yml` thấy image dùng `${TAG` |
| 3 | Mọi service có healthcheck | `rg "healthcheck:" docker-compose.yml` đủ số service; `rg "HEALTHCHECK" */Dockerfile` có dòng tương ứng mỗi image |
| 4 | Image chạy non-root | `rg "^USER " <context>/Dockerfile` trúng ở mọi Dockerfile (trừ dòng comment) |
| 5 | Mỗi build context có `.dockerignore` | `rg --files -g ".dockerignore"` liệt kê đủ một file mỗi service |
| 6 | Secret không nằm ở web | `rg -i "DATABASE_URL\|DB_URI\|PRIVATE_KEY\|CLIENT_SECRET" web/ site/ public/` phải trống (trừ comment và tài liệu) |
| 7 | Compose không chứa secret thô | `rg -i "password\s*:\s*[^$\s]\|secret\s*:\s*[^$\s]" docker-compose.yml` phải trống (mọi secret phải qua `${BIEN}`) |
| 8 | Port ngoài qua biến | `rg -A2 "ports:" docker-compose.yml` mọi dòng map đều chứa `${` |
| 9 | File env không lọt git | `rg --files -g ".env"` chỉ còn `.env.example`; `git status --short` không hiện `.env` |
| 10 | Tài liệu được trích dẫn phải tồn tại | mở từng đường dẫn file được nhắc trong compose/workflow/docs, không để link chết |
| 11 | Không hardcode IP nội bộ | `rg "192\.168\.\|10\.\d+\.\d+\.\d+\|172\.1[6-9]\." docker-compose.yml */Dockerfile` phải trống (gọi nhau qua tên service) |

Quy tắc sửa: lệch ở file nào thì sửa file đó, đúng phạm vi; tài liệu sai thì sửa tài liệu (CI và compose là chuẩn); xong chạy lại toàn bộ lệnh verify của mục này cho xanh.

## 9. Mẫu báo cáo sau mỗi lần áp skill

- **Đã khảo sát:** liệt kê bảng evidence `file:line` theo checklist mục 2 (runtime gì, port nào, env nào bắt buộc).
- **Tách container:** mấy container, mỗi container chạy runtime gì, vì sao tách hoặc vì sao giữ nguyên.
- **File đổi:** liệt kê từng file và dòng đổi (Dockerfile, compose, workflow, `.dockerignore`, tài liệu).
- **Verify:** dán kết quả từng lệnh ở checklist mục 8 (grep trống, healthcheck xanh, `docker ps`, CI chạy xanh kèm số build).
- **Gap còn lại:** mục checklist chưa đạt kèm file cần tạo hoặc sửa, và bước tiếp theo để đóng gap.
