# 懒猫微服部署完整步骤说明

> 适用应用：**DeepTutor**（`deeptutor/`）与 **OpenMAIC**（`openmaic/`）。
> 目标：从零开始，把两个应用打包为 LPK 并安装到懒猫微服盒子上。
> 全程只需本目录 + 对应的上游源码仓库。

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

> 架构说明：DeepTutor 官方镜像同时提供 `linux/amd64` 与 `linux/arm64`；
> OpenMAIC 基于 `node:22-alpine` 构建，两种架构均可。无论盒子是
> x86_64 还是 arm64 都可以部署，构建镜像时用 `docker buildx` 出对应架构即可。

---

## 1. DeepTutor：打包与安装

DeepTutor 使用**官方已发布的一体化镜像**（前后端同容器），不需要自己构建镜像。

### 1.1 同步镜像到懒猫 Registry（推荐）

ghcr.io 在部分网络下拉取缓慢，先经懒猫云中转：

```bash
lzc-cli appstore copy-image ghcr.io/hkuds/deeptutor:latest
```

复制成功后，把 `deeptutor/lzc-manifest.yml` 中的 `services.deeptutor.image`
改为命令输出的懒猫 Registry 地址（形如
`registry.lazycat.cloud/<你的命名空间>/deeptutor:latest`）。

> 若盒子网络可以直连 ghcr.io，可跳过本步，保持 manifest 原样。

### 1.2 构建 LPK

```bash
cd deeptutor
lzc-cli project build -o deeptutor.lpk
```

产物：`deeptutor/cloud.lazycat.app.deeptutor-v1.5.10.lpk`（或你指定的 `-o` 文件名）。

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
- **升级**：重复 1.1–1.3（改 manifest 镜像 tag 与 `package.yml` 的 version），
  数据目录原地保留。
- **资源**：建议盒子空闲内存 ≥ 4 GB（FastAPI + Next.js + FAISS）。

---

## 2. OpenMAIC：打包与安装

OpenMAIC 没有官方发布镜像，需要**从上游源码自行构建**。

### 2.1 准备上游源码

```bash
git clone https://github.com/JoeyMyMan/OpenMAIC4course.git
cd OpenMAIC4course
```

> 注意：Docker 构建使用 `pnpm install --frozen-lockfile`，要求
> `package.json` 与 `pnpm-lock.yaml` 严格同步。如果你升级过依赖
> （例如 ai-sdk 大版本），先执行 `pnpm install --lockfile-only` 再构建。

### 2.2 构建镜像

在上游仓库根目录执行（Dockerfile 用本仓库提供的副本，与上游一致并
预建 `/app/data` 目录）：

```bash
# 单架构（与本机一致）：
docker build -f /path/to/lazycat-edu-apps/openmaic/Dockerfile \
  -t <你的dockerhub用户名>/openmaic:0.1.0 .

# 或跨架构（如在 Apple Silicon 上给 x86 盒子构建）：
docker buildx build --platform linux/amd64 \
  -f /path/to/lazycat-edu-apps/openmaic/Dockerfile \
  -t <你的dockerhub用户名>/openmaic:0.1.0 --push .
```

### 2.3 推送并同步到懒猫 Registry

```bash
docker push <你的dockerhub用户名>/openmaic:0.1.0        # buildx --push 已推则跳过
lzc-cli appstore copy-image <你的dockerhub用户名>/openmaic:0.1.0
```

把 `openmaic/lzc-manifest.yml` 的 `services.openmaic.image` 改为 copy-image
输出的懒猫 Registry 地址。

### 2.4 构建并安装 LPK

```bash
cd openmaic
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
6. **升级后想回滚** → 数据目录未动，重新安装旧版本 LPK 即可。

## 5. 文件清单

```text
deeptutor/
├── package.yml           # LPK V2 元数据（name/package/version）
├── lzc-manifest.yml      # 运行结构：1 个 service + HTTP 路由 :3782 + 数据挂载
├── lzc-build.yml         # 构建脚本（pkgout + icon）
└── icon.png              # 512×512 应用图标

openmaic/
├── package.yml
├── lzc-manifest.yml      # 1 个 service + HTTP 路由 :3000 + 数据挂载 + 安装期参数渲染
├── lzc-build.yml
├── lzc-deploy-params.yml # 安装期可选 LLM 参数（OpenAI/DeepSeek/Qwen）
├── Dockerfile            # 上游 Dockerfile 副本（预建 /app/data）
└── icon.png
```
