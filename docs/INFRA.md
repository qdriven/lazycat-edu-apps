# 基础设施架构与运维手册

> 本仓库作为自托管基础设施仓库的完整说明：组件、版本策略、网络与存储拓扑、
> 升级流程、备份恢复、安全边界。部署操作步骤见 [DEPLOY-GUIDE.md](./DEPLOY-GUIDE.md)。

---

## 1. 组件矩阵

| 组件 | 角色 | 镜像 / 源码 | 版本锁定方式 | 数据 |
|---|---|---|---|---|
| DeepTutor | 学习工作台（RAG 知识库 / 教程生成 / 掌握度学习） | `ghcr.io/hkuds/deeptutor:1.5.10` 官方多架构 | manifest 固定 tag + `upstream/DeepTutor` submodule @ 8865da7c | `/lzcapp/var/data`（文件数据面：索引/设置/会话/记忆） |
| OpenMAIC | AI 课程生成与课堂 | 自建 `apps/openmaic/Dockerfile`（上游同源） | `upstream/OpenMAIC4course` submodule @ 5bd8235 + `versions.env` | `/lzcapp/var/data` + 浏览器 IndexedDB |
| Edu PostgreSQL | 共享数据库 | `postgres:16-alpine` 官方 | manifest 固定 tag | `/lzcapp/var/pgdata` |

## 2. 版本策略（基础设施仓库的核心纪律）

1. **唯一事实来源是 `versions.env`**。任何地方出现版本号，都必须能追溯到它。
2. **禁止 `:latest`**。所有镜像引用必须是精确 tag。
3. **上游源码用 submodule 锁提交**，不用" clone 下来当前是什么就是什么"。
4. 升级流程（以 DeepTutor 为例）：

```bash
make update-upstream                          # 看上游新提交
git -C upstream/DeepTutor checkout <新tag提交> # 子模块推进
# 改 versions.env 的 DEEPTUTOR_VERSION / DEEPTUTOR_IMAGE
# 改 apps/deeptutor/lzc-manifest.yml 的 image tag
# 改 apps/deeptutor/package.yml 的 version
make sync-images && make pack && make deploy   # 重新发布
git add -A && git commit -m "chore: bump deeptutor to x.y.z"
```

5. **回滚**：`git checkout <旧提交>` 后重新 `make pack && make deploy`；
   应用数据目录与 PG 数据不受影响（除非上游有破坏性 schema 变更——
   升级前先 `make backup`）。

## 3. 网络拓扑

```text
外部世界                    懒猫盒子
─────────                ─────────────────────────────────
LLM API  ◄──出站 HTTPS──   deeptutor 容器 (3782 前端 / 8001 后端内部)
                           openmaic  容器 (3000)
用户     ◄──HTTPS 路由──   懒猫网关（按应用域名分发，自动证书）
                           postgres  容器 (5432，仅 127.0.0.1 内部互通)
```

- 对外只有两条 HTTPS 路由（两个应用域名），PG 无任何路由/端口暴露。
- 跨应用通信走宿主机 loopback（懒猫容器共享主机网络）。
- 外部依赖收敛为两类：**镜像 Registry**（经 `make sync-images` 中转后盒子不再直连）
  与 **LLM API**（应用本质所需；要完全断外网可自托管 Ollama/vLLM 后改 base URL，
  但 RAG 质量取决于模型，需自行评估）。

## 4. 存储与备份

| 数据 | 位置 | 备份 |
|---|---|---|
| PG 三库 | postgres 应用 `/lzcapp/var/pgdata` | `pg_dump` 逻辑备份（首选）+ 目录快照 |
| DeepTutor 全部状态 | deeptutor 应用 `/lzcapp/var/data` | 目录快照（备份=拷目录是它的设计优势） |
| OpenMAIC 服务端产物 | openmaic 应用 `/lzcapp/var/data` | 目录快照 |
| OpenMAIC 课程（当前版本） | **浏览器 IndexedDB** | 应用内导出；PG fork 后由 PG 接管 |

`make backup` → `backups/<日期>/`（pg-*.sql + *.tar.gz）。
建议把 `backups/` 定期同步到盒子之外（另一台机器 / 对象存储）。
恢复 = tar 解回对应 `/lzcapp/var` + `psql` 导入 + 重装/重启应用。

## 5. 安全边界

1. **密钥不出盒子**：PG 密码由懒猫 `stable_secret` 生成，只存在于渲染后的
   运行时 manifest（`/lzcapp/run/`），不进 git。LLM API Key 由安装参数或应用内
   设置注入，本仓库一律 `<密码>` 占位。
2. **DeepTutor 多用户**：开启 auth 后首注册用户即 admin；exec 沙箱对非 admin
   默认拒绝——保持默认。
3. **最小暴露**：不要给 postgres 应用开 `ingress`（除非明确要远程调试，
   用完即关）；两个应用之外不需要任何端口。
4. **私有仓库化**：本仓库目前是 public（只含配置与文档，无密钥）。若后续放入
   盒子域名、内部地址等敏感信息，在 GitHub Settings 转为 private 即可，
   内容与流程不变。

## 6. 路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| ✅ 打包层 | 三应用 LPK + 部署文档 | 完成 |
| ✅ 基础设施层 | 版本锁定 + submodule + Makefile + 备份 | 完成（本次） |
| ⬜ PG fork 层 | DeepTutor SessionStore PG 实现；OpenMAIC 服务端课程 API（[改造点](./POSTGRES-SHARED.md)） | 待做 |
| ⬜ GitOps 层 | GitHub Actions：上游 release 监控 → 自动开升级 PR（改 versions.env + submodule） | 待做 |
| ⬜ 离线增强 | 可选 Ollama/vLLM 本地模型 sidecar 应用 | 评估中 |
