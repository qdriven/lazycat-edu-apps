# 懒猫微服部署完整步骤说明

> 适用应用：**DeepTutor**（`apps/deeptutor/`）、**OpenMAIC**（`apps/openmaic/`）、
> **共享 PostgreSQL**（`apps/postgres/`）。
> 目标：从零开始，把整套基础设施打包为 LPK 并安装到懒猫微服盒子上。
> 快捷路径：`make sync-images && make build-openmaic && make pack && make deploy`
> （见根 [README](../README.md)）；本文是等价的完整手动步骤与排障手册。

---

## 0. 前置条件（一次性）

| 项 | 要求 | 验证命令 |
|---|---|---|
| 懒猫微服盒子 | 已激活，可 SSH / 局域网访问 | 客户端能打开盒子桌面 |
| lzc-cli | `npm install -g @lazycatcloud/lzc-cli` | `lzc-cli --version` |
| 开发者工具 | 盒子应用商店安装「开发者工具」 | 盒子上可见该应用 |
| 懒猫社区开发者账号 | 在 lzc-cli 登录 | `lzc-cli whoami`（或按提示 `lzc-cli login`） |
| Docker | 本机 Docker / Podman，可构建镜像 | `docker version` |
| rsync / ssh | lzc-cli project 系列命令依赖（macOS/Linux 自带） | `which rsync ssh` |
| 本仓库 | `git clone --recursive`（含 upstream 子模块） | `git submodule status` |

> 架构说明：DeepTutor 官方镜像同时提供 `linux/amd64` 与 `linux/arm64`；
> OpenMAIC 基于 `node:22-alpine` 构建，两种架构均可。无论盒子是
> x86_64 还是 arm64 都可以部署，构建镜像时用 `docker buildx` 出对应架构即可。

---

## 1. DeepTutor：打包与安装

DeepTutor 使用**官方已发布的一体化镜像**（前后端同容器），不需要自己构建镜像。
镜像版本在 `apps/deeptutor/lzc-manifest.yml` 中锁定为 `ghcr.io/hkuds/deeptutor:1.5.10`
（GHCR tag 无 `v` 前缀；与 `versions.env` 同步修改）。

### 1.1 同步镜像到懒猫 Registry（推荐）

ghcr.io 在部分网络下拉取缓慢，先经懒猫云中转：

```bash
lzc-cli appstore copy-image ghcr.io/hkuds/deeptutor:1.5.10
```

复制成功后，把 `apps/deeptutor/lzc-manifest.yml` 中的 `services.deeptutor.image`
改为命令输出的懒猫 Registry 地址（形如
`registry.lazycat.cloud/<你的命名空间>/deeptutor:1.5.10`）。

> 若盒子网络可以直连 ghcr.io，可跳过本步，保持 manifest 原样。

### 1.2 构建 LPK

```bash
cd apps/deeptutor
lzc-cli project build -o deeptutor.lpk
```

产物：`apps/deeptutor/cloud.lazycat.app.deeptutor-v1.5.10.lpk`（或你指定的 `-o` 文件名）。

### 1.3 安装到盒子

```bash
lzc-cli lpk install ./deeptutor.lpk
```

### 1.4 首次配置

1. 浏览器打开 `https://deeptutor.<你的设备名>.heiyu.space`。
2. 默认**单用户无认证**。需要多人使用：在应用内 `data/user/settings/auth.json`
   开启 auth（或 Settings 界面操作），重启应用；**第一个注册的用户自动成为 admin**。
3. 进入 **Settings → Models**：配置 LLM provider（任意 OpenAI 兼容网关均可）、
   可选 Embedding provider（知识库/RAG 需要）。
4. 建知识库：Knowledge Center → 新建 KB 上传文档（默认 LlamaIndex 引擎，
   文档解析建议在 **Settings → Knowledge Base** 选 Text-only 或 PyMuPDF4LLM，
   避免 MinerU 在盒子上下载本地模型）。

### 1.5 数据与升级

- **数据**：全部状态在盒子的 `/lzcapp/var/data`（容器内 `/app/data`）。
  备份 = 复制该目录；迁移 = 拷贝到新盒子同路径。
- **升级**：按 [INFRA.md](./INFRA.md) 第 2 节的版本纪律执行
  （改 `versions.env` + manifest tag + 子模块提交 → 重新打包安装），
  数据目录原地保留。
- **资源**：建议盒子空闲内存 ≥ 4 GB（FastAPI + Next.js + FAISS）。

---

## 2. OpenMAIC：打包与安装

OpenMAIC 没有官方发布镜像，需要**从锁定的上游源码自行构建**。

### 2.1 准备上游源码

本仓库已把上游锁定为 git submodule（`upstream/OpenMAIC4course` @ 5bd8235）：

```bash
git submodule update --init   # clone 时用了 --recursive 则已就绪
```

> 注意：Docker 构建使用 `pnpm install --frozen-lockfile`，要求
> `package.json` 与 `pnpm-lock.yaml` 严格同步。如果你在 fork 里升级过依赖
> （例如 ai-sdk 大版本），先执行 `pnpm install --lockfile-only` 再构建。

### 2.2 构建镜像

在仓库根目录直接用 Makefile（等价于手动 docker build）：

```bash
make build-openmaic      # 使用 versions.env 中的 REGISTRY_USER / OPENMAIC_VERSION
```

手动等价命令（在上游子模块目录作为 build context）：

```bash
# 单架构（与本机一致）：
docker build -f apps/openmaic/Dockerfile \
  -t <你的dockerhub用户名>/openmaic:0.1.0 upstream/OpenMAIC4course

# 或跨架构（如在 Apple Silicon 上给 x86 盒子构建）：
docker buildx build --platform linux/amd64 \
  -f apps/openmaic/Dockerfile \
  -t <你的dockerhub用户名>/openmaic:0.1.0 --push upstream/OpenMAIC4course
```

### 2.3 推送并同步到懒猫 Registry

```bash
docker push <你的dockerhub用户名>/openmaic:0.1.0        # buildx --push 已推则跳过
lzc-cli appstore copy-image <你的dockerhub用户名>/openmaic:0.1.0
```

把 `apps/openmaic/lzc-manifest.yml` 的 `services.openmaic.image` 改为 copy-image
输出的懒猫 Registry 地址。

### 2.4 构建并安装 LPK

```bash
cd apps/openmaic
lzc-cli project build -o openmaic.lpk
lzc-cli lpk install ./openmaic.lpk
```

### 2.5 首次配置

1. 打开 `https://openmaic.<你的设备名>.heiyu.space`。
2. LLM 配置两种方式任选：
   - **安装时**：安装弹窗中填写 `lzc-deploy-params.yml` 定义的可选参数
     （OpenAI / DeepSeek / Qwen 的 API Key）；
   - **安装后**：在应用内配置，或在数据目录放 `server-providers.yml`。
3. 数据在 `/lzcapp/var/data`（容器内 `/app/data`）。

---

## 3. 验证清单

| 检查 | 方法 | 预期 |
|---|---|---|
| LPK 打包成功 | `lzc-cli project build` 输出 | 生成 `.lpk` 文件无报错 |
| 安装成功 | `lzc-cli lpk install` 输出 | `Installation successful!` |
| 容器运行 | 盒子开发者工具 / `lzc-cli project info` | 应用状态 running |
| 页面可访问 | 浏览器打开应用域名 | DeepTutor 首页 / OpenMAIC 首页正常渲染 |
| API 联通（DeepTutor） | 首页 Settings 状态条 | Backend 绿色（前端请求时代理 /api/*） |
| 数据持久化 | 重启应用后 | 知识库 / 课程设置仍在 |

## 4. 常见问题

1. **镜像拉取失败 / 超时** → 先 `lzc-cli appstore copy-image` 走懒猫中转，不要把 ghcr / docker.io 地址直接留给盒子拉。
2. **OpenMAIC 构建报 frozen-lockfile 错误** → `package.json` 与 `pnpm-lock.yaml` 不同步，`pnpm install --lockfile-only` 后重新构建。
3. **DeepTutor 页面开了但 API 500 / 转圈** → 多为内存不足或首次初始化慢；等 1–2 分钟，确认盒子空闲内存 ≥ 4 GB。
4. **数据目录权限问题** → 两个镜像内进程均为非 root（DeepTutor UID 1000 / OpenMAIC UID 1001），懒猫 bind 挂载一般自动对齐；若报 PermissionError，在盒子上 `chmod -R a+rwX /lzcapp/var/data` 后重启应用。
5. **本地模型类功能**（MinerU 本地下载、本地 LLM）→ 盒子定位是「远程 API + 轻量索引」，请在应用内选择远程 provider。
6. **升级后想回滚** → 数据目录未动，重新安装旧版本 LPK 即可（版本纪律见 [INFRA.md](./INFRA.md)）。

## 5. 文件清单

```text
apps/deeptutor/
├── package.yml           # LPK V2 元数据（name/package/version）
├── lzc-manifest.yml      # 运行结构：1 个 service + HTTP 路由 :3782 + 数据挂载
│                         #   镜像锁定 ghcr.io/hkuds/deeptutor:1.5.10
│                         #   （含注释掉的共享 PG env：DEEPTUTOR_DATABASE_URL）
├── lzc-build.yml         # 构建脚本（pkgout + icon）
└── icon.png              # 512×512 应用图标

apps/openmaic/
├── package.yml
├── lzc-manifest.yml      # 1 个 service + HTTP 路由 :3000 + 数据挂载 + 安装期参数渲染
│                         #   （含注释掉的共享 PG env：DATABASE_URL）
├── lzc-build.yml
├── lzc-deploy-params.yml # 安装期可选 LLM 参数（OpenAI/DeepSeek/Qwen）
├── Dockerfile            # 上游 Dockerfile 副本（预建 /app/data）
└── icon.png

apps/postgres/            # 共享 PostgreSQL 应用
├── package.yml           # cloud.lazycat.app.edu-postgres
├── lzc-manifest.yml      # postgres:16-alpine，stable_secret 密码，内部 :5432
├── lzc-build.yml
└── icon.png

upstream/                 # 上游源码 submodule（版本锁定，构建 OpenMAIC 用）
├── DeepTutor             # @ v1.5.10 (8865da7c)
└── OpenMAIC4course       # @ 5bd8235
```

## 6. 共享 PostgreSQL

让 DeepTutor 与 OpenMAIC 共用本仓库 `apps/postgres/` 提供的数据库实例：

```bash
# 1. 安装共享 PG
lzc-cli appstore copy-image postgres:16-alpine
cd apps/postgres && lzc-cli project build -o edu-postgres.lpk
lzc-cli lpk install ./edu-postgres.lpk

# 2. 取密码、建库
lzc-cli project exec -- env | grep POSTGRES_PASSWORD
lzc-cli project exec -- psql -U edu -d edu \
  -c "CREATE DATABASE edu_deeptutor;" -c "CREATE DATABASE edu_openmaic;"

# 3. 两个应用换成 PG fork 版镜像后，取消各自 manifest 中 PG env 的注释，
#    重新打包安装
```

⚠️ **重要前提**：官方镜像**不读** `DATABASE_URL`——DeepTutor 是文件+SQLite
数据面，OpenMAIC 数据在浏览器 IndexedDB。共用 PG 需要两个应用的 fork 版本
真正接入数据库，精确的代码改造点（DeepTutor 的 `sqlite_store.py` / 认证存储、
OpenMAIC 的 Dexie → 服务端 API）、数据迁移与备份策略，全部见
**[POSTGRES-SHARED.md](./POSTGRES-SHARED.md)**。
