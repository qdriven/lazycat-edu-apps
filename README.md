# lazycat-edu-apps · 教育应用自托管基础设施

把 **DeepTutor + OpenMAIC + 共享 PostgreSQL** 作为一套完整的教育基础设施，
自托管到懒猫微服（Lazycat MicroServer）私有云。本仓库是唯一事实来源：
**版本锁定、源码可复现、一键构建部署备份**。

## 架构

```text
┌────────────────────── 懒猫微服私有云（你的盒子）──────────────────────┐
│                                                                      │
│   https://deeptutor.<box>.heiyu.space    https://openmaic.<box>...   │
│   ┌─────────────────────────┐          ┌─────────────────────────┐   │
│   │ DeepTutor 1.5.10        │          │ OpenMAIC 0.1.0          │   │
│   │ FastAPI+Next.js 一体    │          │ Next.js standalone      │   │
│   │ /lzcapp/var/data        │          │ /lzcapp/var/data        │   │
│   └───────────┬─────────────┘          └───────────┬─────────────┘   │
│               │ 127.0.0.1:5432（内部，不对外）       │                │
│        ┌──────┴──────────────────────────────────────┴──────┐         │
│        │ Edu PostgreSQL 16（共享实例）                       │         │
│        │   库: edu / edu_deeptutor / edu_openmaic           │         │
│        │   /lzcapp/var/pgdata                               │         │
│        └────────────────────────────────────────────────────┘         │
│   出站：LLM / Embedding 远程 API（OpenAI 兼容 / DeepSeek / Qwen…）     │
└──────────────────────────────────────────────────────────────────────┘
```

> PG 接线已就位；官方应用镜像本身不写 PG（DeepTutor=文件+SQLite，
> OpenMAIC=浏览器 IndexedDB），启用需 fork 版，见
> [docs/POSTGRES-SHARED.md](docs/POSTGRES-SHARED.md)。

## 仓库布局

```text
├── versions.env          # ★ 版本事实来源（镜像 tag / 应用版本 / registry）
├── Makefile              # ★ sync-images / build / pack / deploy / backup
├── apps/                 # 懒猫 LPK 包定义（三件套 + 图标）
│   ├── deeptutor/        #   官方镜像 ghcr.io/hkuds/deeptutor:1.5.10（锁定）
│   ├── openmaic/         #   自建镜像（Dockerfile + 安装期 LLM 参数）
│   └── postgres/         #   共享 PG（stable_secret 密码，内部 :5432）
├── upstream/             # 上游源码 git submodule，锁定到验证过的提交
│   ├── DeepTutor         #   → qdriven/DeepTutor      @ v1.5.10 (8865da7c)
│   └── OpenMAIC4course   #   → JoeyMyMan/OpenMAIC4course @ 5bd8235
├── scripts/backup.sh     # 全量备份（pg_dump + 数据目录快照）
└── docs/
    ├── INFRA.md          # 基础设施架构与运维手册（升级/备份/安全）
    ├── DEPLOY-GUIDE.md   # 从零部署完整步骤 + 排障
    └── POSTGRES-SHARED.md# 共享 PG 分析与两个应用的 fork 改造点
```

## 快速开始

```bash
# 0. 一次性：lzc-cli + 登录开发者账号 + 盒子上装「开发者工具」
npm install -g @lazycatcloud/lzc-cli

# 1. 克隆（含上游子模块，版本已锁定）
git clone --recursive https://github.com/qdriven/lazycat-edu-apps.git
cd lazycat-edu-apps
#    忘了 --recursive 就：git submodule update --init

# 2. 按你的环境改 versions.env（主要是 REGISTRY_USER）

# 3. 镜像 → 懒猫 Registry → LPK → 安装，四条命令
make sync-images       # DeepTutor + PostgreSQL 官方镜像中转
make build-openmaic    # 从锁定的 upstream 源码构建 OpenMAIC 并同步
make pack              # 三个 LPK 打到 dist/
make deploy            # 按 PG → 应用顺序安装到盒子

# 4. 日常
make backup            # 全量备份到 backups/<日期>/
make update-upstream   # 查看上游新提交（升级流程见 docs/INFRA.md）
```

## 设计原则

- **版本锁定**：镜像用精确 tag（不用 `:latest`），上游源码用 submodule 锁提交；
  任何一台机器 clone 出来构建的结果一致。
- **单一事实来源**：版本号只在 `versions.env`；部署步骤只在 `Makefile`；
  知识只在 `docs/`。
- **数据自持**：全部状态在盒子的 `/lzcapp/var/*` 三棵目录树 + PG 实例，
  不依赖任何外部存储；外部依赖只剩 LLM API（可换任意 OpenAI 兼容端点）。
- **诚实分层**：官方镜像做不到的（PG 持久化），文档明确给出 fork 改造点，
  不用 env 假装支持。

## 许可证

本仓库（打包配置、脚本、文档）以 MIT 发布；应用遵循各自上游许可证
（DeepTutor: Apache-2.0，OpenMAIC: AGPL-3.0，PostgreSQL: PostgreSQL License）。
