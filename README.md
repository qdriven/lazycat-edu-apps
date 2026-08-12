# lazycat-edu-apps

教育类应用的**懒猫微服（Lazycat MicroServer）**打包仓库：把 [DeepTutor](https://github.com/HKUDS/DeepTutor) 与 [OpenMAIC](https://github.com/JoeyMyMan/OpenMAIC4course) 打包成可在懒猫私服盒子上安装运行的 LPK 应用。

## 应用一览

| 应用 | 目录 | 上游 | 镜像来源 | 端口/路由 | 数据目录 |
|---|---|---|---|---|---|
| **DeepTutor** v1.5.10 | [`deeptutor/`](./deeptutor) | HKUDS/DeepTutor（Apache-2.0） | 官方 `ghcr.io/hkuds/deeptutor`（amd64+arm64） | `:3782`（前后端一体，后端请求时代理） | `/lzcapp/var/data` → `/app/data` |
| **OpenMAIC** v0.1.0 | [`openmaic/`](./openmaic) | JoeyMyMan/OpenMAIC4course（AGPL-3.0） | 本仓库 `openmaic/Dockerfile` 自行构建 | `:3000`（Next.js standalone） | `/lzcapp/var/data` → `/app/data` |

## 快速开始

```bash
# 0. 安装 lzc-cli 并登录懒猫开发者账号（一次性）
npm install -g @lazycatcloud/lzc-cli

# 1. DeepTutor：同步官方镜像 → 打包 → 安装
lzc-cli appstore copy-image ghcr.io/hkuds/deeptutor:latest
cd deeptutor && lzc-cli project build -o deeptutor.lpk
lzc-cli lpk install ./deeptutor.lpk

# 2. OpenMAIC：构建镜像 → 同步 → 打包 → 安装（详见部署指南）
```

完整步骤（前置条件、镜像构建、安装配置、验证清单、常见问题）见：

**[docs/DEPLOY-GUIDE.md](./docs/DEPLOY-GUIDE.md)**

## 设计要点

- **单 service 一体化**：两个应用都是单容器形态，懒猫 manifest 只需一个 service + 一条 HTTP route。
- **数据单树挂载**：全部状态落在 `/lzcapp/var/data`，备份迁移一条路径。
- **无构建期地址**：DeepTutor 前端请求时代理后端，OpenMAIC 为 standalone，天然兼容懒猫按域名分配路由的模型。
- **LLM 全部出站调用**：盒子无需 GPU，远程 API（OpenAI 兼容 / DeepSeek / Qwen 等）即可。

## 许可证

本仓库的打包配置文件以 MIT 发布；应用本身遵循各自上游许可证
（DeepTutor: Apache-2.0，OpenMAIC: AGPL-3.0）。
