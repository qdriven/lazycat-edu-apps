# 共享 PostgreSQL 改造指南

> 目标：让 DeepTutor 与 OpenMAIC 在懒猫微服上**共用一个 PostgreSQL 实例**。
> 本文先给出数据层现状的核实结论，再说明仓库改了什么、两个应用各自需要的
> 代码改造（fork），以及完整的部署与迁移步骤。

---

## 1. 先说清楚：两个应用现在都不用 PostgreSQL

| 应用 | 数据层现状（源码核实） | 能用 PG 的部分 | 不能进 PG 的部分 |
|---|---|---|---|
| **DeepTutor** v1.5.10 | **文件优先**：设置 JSON、知识库 FAISS/BM25 索引目录、记忆 md/jsonl；SQLite 仅用于 ① 聊天会话 `deeptutor/services/session/sqlite_store.py` ② 记忆快照 `deeptutor/services/memory/snapshot/adapters.py` ③ 多用户账户/认证 | 会话、记忆快照、账户/授权（grants/audit） | **FAISS 向量索引、文档原文、记忆文件、设置文件**——它们本质是文件，PG 装不下也不该装 |
| **OpenMAIC** v0.1.0 | **浏览器 IndexedDB（Dexie）**：`lib/utils/database.ts`、`chat-storage.ts`、`stage-storage.ts` 等；服务端（Next.js）**没有数据库层**，`/app/data` 只放少量服务端产物 | 需要**新增**服务端课程存储 | 纯浏览器缓存类状态无需上 PG |

**关键结论**：只在 manifest 里加 `DATABASE_URL` 环境变量，官方镜像**不会有任何变化**
（它们根本不读这个变量）。共用 PG = 「部署一个共享 PG」+「两个应用的 fork 版本真正读写 PG」，
二者缺一不可。本仓库完成前者与全部接线，fork 改造点在第 4、5 节给出精确位置。

## 2. 本仓库的修改内容

```text
apps/postgres/                   # 【新增】共享 PostgreSQL LPK 应用
├── package.yml                  #   cloud.lazycat.app.edu-postgres
├── lzc-manifest.yml             #   postgres:16-alpine，密码 stable_secret 生成
├── lzc-build.yml
└── icon.png

apps/deeptutor/lzc-manifest.yml  # 【修改】新增注释掉的可选 env：
                                 #   DEEPTUTOR_DATABASE_URL=postgresql://edu:<密码>@127.0.0.1:5432/edu_deeptutor
apps/openmaic/lzc-manifest.yml   # 【修改】新增注释掉的可选 env：
                                 #   DATABASE_URL=postgresql://edu:<密码>@127.0.0.1:5432/edu_openmaic
docs/POSTGRES-SHARED.md          # 【新增】本文
```

拓扑（推荐）：**独立的共享数据库应用**

```text
┌──────────────────────── 懒猫微服盒子 ────────────────────────┐
│  cloud.lazycat.app.edu-postgres                              │
│    postgres:16-alpine  ──► 127.0.0.1:5432                    │
│    数据: /lzcapp/var/pgdata                                  │
│         ▲                              ▲                     │
│  cloud.lazycat.app.deeptutor    cloud.lazycat.app.openmaic   │
│    (fork 版, 读 DEEPTUTOR_        (fork 版, 读 DATABASE_URL) │
│     DATABASE_URL)                                            │
│    库: edu_deeptutor                库: edu_openmaic         │
│    文件数据仍挂 /lzcapp/var/data                             │
└──────────────────────────────────────────────────────────────┘
```

懒猫应用容器共享宿主机网络，跨应用用 `127.0.0.1:5432` 直连即可，
PG 不需要任何对外路由/端口暴露。

> 备选拓扑：① 若你已有外部 PG（NAS、云 RDS），跳过 apps/postgres/ 应用，
> 直接把两个 env 指向外部地址；② 若想要单一大应用，把 postgres service
> 合并进任一 manifest 组成组合 LPK，失去独立安装灵活性，不推荐。

## 3. 部署共享 PG（基础设施部分，现在就能做）

```bash
# 1. 同步官方镜像到懒猫 Registry（多架构，arm64/x86 均可）
lzc-cli appstore copy-image postgres:16-alpine
#    如需，把 apps/postgres/lzc-manifest.yml 的 image 改为输出的懒猫 Registry 地址

# 2. 打包安装
cd apps/postgres
lzc-cli project build -o edu-postgres.lpk
lzc-cli lpk install ./edu-postgres.lpk

# 3. 取出安装时生成的稳定密码（同一盒子同一应用重装不变）
lzc-cli project exec -- env | grep POSTGRES_PASSWORD

# 4. 为两个应用各建一个库（共用实例、逻辑隔离）
lzc-cli project exec -- psql -U edu -d edu \
  -c "CREATE DATABASE edu_deeptutor;" \
  -c "CREATE DATABASE edu_openmaic;"
```

到此共享 PG 就绪。接下来是两个应用的 fork 改造。

## 4. DeepTutor fork 改造点（Python）

目标：把三处 SQLite 存储切到 PG，文件数据原样保留。

| 改造点 | 位置 | 做法 |
|---|---|---|
| 依赖 | `pyproject.toml` | 加 `asyncpg>=0.29`（或 `psycopg[binary]>=3.1` + SQLAlchemy 可选） |
| 连接读取 | 新增 `deeptutor/services/storage/database.py` | 读 `DEEPTUTOR_DATABASE_URL`；未设置时回落 SQLite（保持官方行为，fork 可持续合上游） |
| 会话存储 | `deeptutor/services/session/sqlite_store.py` | 抽象 `SessionStore` 协议，新增 `pg_store.py` 实现同名方法；表结构直接沿用 SQLite 的 DDL 改成 PG 方言（`INTEGER PRIMARY KEY AUTOINCREMENT` → `BIGSERIAL` 等） |
| 记忆快照 | `deeptutor/services/memory/snapshot/adapters.py` | 同上，加 PG adapter |
| 账户/认证 | `deeptutor/api/routers/auth.py` + `deeptutor/multi_user/`（identity/grants/audit） | 账户、grants、audit 三张表迁 PG；bcrypt/JWT 逻辑不变 |
| 迁移 | 新增 `deeptutor db migrate` CLI 子命令 | 启动时 `CREATE TABLE IF NOT EXISTS`；另提供 SQLite→PG 一次性导入脚本（`sqlite3 .db .dump` 清洗方言后 `psql` 导入） |

要点：**不要试图把 FAISS 索引搬进 PG**。向量索引文件仍走 `/app/data`，
PG 里只存元数据（KB 清单、版本、manifest 已有 JSON 可后续再迁）。
这样 fork 改动最小，且 DeepTutor 的文件数据面优势（备份=拷目录）依然成立。

## 5. OpenMAIC fork 改造点（TypeScript / Next.js）

目标：课程数据从「只在浏览器 IndexedDB」变为「服务端 PG 为源 + 浏览器为缓存」。
这是比 DeepTutor 更大的改造——服务端数据库层是从零新增。

| 改造点 | 位置 | 做法 |
|---|---|---|
| 依赖 | `package.json` | 加 `pg` + `drizzle-orm`（或 `prisma`）；dev 加 `drizzle-kit` |
| 连接读取 | 新增 `lib/server/db.ts` | 读 `DATABASE_URL`，未设置时应用退回纯 IndexedDB 模式（保持官方行为） |
| schema | 新增 `lib/server/schema.ts` | 对照 `lib/utils/database.ts` 的 Dexie 表（courses/lessons/chat/playback/images…）建 PG 表，主键沿用前端 id |
| API | `app/api/courses/**` 等 route handlers | REST：`GET/POST/PUT/DELETE /api/courses[/:id]`，服务端渲染产物（`/app/data` 文件）只存路径引用 |
| 前端同步 | `lib/utils/database.ts` 及各 `*-storage.ts` | 写路径改为「先写 IndexedDB（离线可用）→ 后台 POST 到服务端」；读路径优先服务端、miss 时回落本地 |
| 迁移 | 应用内「导出/导入」 | 读取现有 Dexie 全量数据 → 一次性 POST 到 `/api/migrate`；浏览器端零命令行操作 |

要点：Dexie 保留做离线缓存，用户体验不变，但换浏览器/换设备后课程还在
——这正是共用 PG 对 OpenMAIC 的核心价值。

## 6. 启用接线（fork 镜像构建后）

```bash
# 1. 用 fork 源码构建镜像（标签建议加 -pg 区分）
docker build -t <你>/deeptutor:1.5.10-pg .          # 在 DeepTutor fork 根目录
docker build -f apps/openmaic/Dockerfile -t <你>/openmaic:0.1.0-pg upstream/OpenMAIC4course
lzc-cli appstore copy-image <你>/deeptutor:1.5.10-pg
lzc-cli appstore copy-image <你>/openmaic:0.1.0-pg

# 2. 改 manifest：image 换成 fork 镜像，取消 PG env 注释并填入第 3 节的密码
#    apps/deeptutor/lzc-manifest.yml → DEEPTUTOR_DATABASE_URL=postgresql://edu:<密码>@127.0.0.1:5432/edu_deeptutor
#    apps/openmaic/lzc-manifest.yml  → DATABASE_URL=postgresql://edu:<密码>@127.0.0.1:5432/edu_openmaic

# 3. 重新打包安装（数据目录原地保留）
cd apps/deeptutor && lzc-cli project build -o deeptutor.lpk && lzc-cli lpk install ./deeptutor.lpk
cd ../openmaic && lzc-cli project build -o openmaic.lpk && lzc-cli lpk install ./openmaic.lpk
```

## 7. 备份与运维

| 内容 | 位置 | 备份方式 |
|---|---|---|
| PG 数据（两库） | `/lzcapp/var/pgdata` | 停应用拷目录，或 `lzc-cli project exec -- pg_dump -U edu edu_deeptutor > backup.sql` |
| DeepTutor 文件数据 | deeptutor 应用 `/lzcapp/var/data` | 原样拷目录（不变） |
| OpenMAIC 服务端产物 | openmaic 应用 `/lzcapp/var/data` | 原样拷目录（不变） |

## 8. 注意事项

1. **值不值得做**：DeepTutor 切 PG 的收益主要是「会话/账户集中管理」，它的大头数据
   （索引/文档/记忆）天然是文件，强上 PG 反而丢失「备份=拷目录」的简单性。
   如果动机只是「两个应用数据集中备份」，更便宜的做法是保持现状 + 统一备份
   `/lzcapp/var/*/data`；如果动机是「多设备同步 OpenMAIC 课程 / DeepTutor 集中账户」，
   PG 路线才成立。
2. **fork 纪律**：DB 访问层都做「`DATABASE_URL` 未设置 → 回落原行为」，才能保证
   持续合并上游 release 不冲突。
3. **PG 不挂的后果**：fork 镜像在 PG 不可达时应启动失败并给出明确日志，不要静默
   回落 SQLite 造成「两边各写一半」的数据分裂。
4. **密码**：`stable_secret` 生成的密码重装不变、跨盒子不同；不要把它写进任何
   会提交到 git 的文件（本仓库 manifest 中全部以 `<密码>` 占位）。
5. **资源**：postgres:16-alpine 空载约 30–50 MB 内存，对盒子压力可忽略。
