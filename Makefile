# lazycat-edu-apps · 自托管基础设施 Makefile
# 版本事实来源：versions.env（改版本只动这一个文件 + manifest tag）

include versions.env
export

SHELL := /bin/bash
LPK_DIR := dist

.PHONY: help sync-images build-openmaic pack deploy backup update-upstream clean

help: ## 显示全部目标
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-16s %s\n", $$1, $$2}'

sync-images: ## 同步全部外部镜像到懒猫 Registry（盒子免直连 ghcr/docker.io）
	lzc-cli appstore copy-image $(DEEPTUTOR_IMAGE)
	lzc-cli appstore copy-image $(POSTGRES_IMAGE)
	@echo "==> OpenMAIC 镜像需先 make build-openmaic（自建镜像）"

build-openmaic: ## 从 upstream 子模块构建 OpenMAIC 镜像（版本锁定）
	docker build \
	  -f apps/openmaic/Dockerfile \
	  -t $(REGISTRY_USER)/openmaic:$(OPENMAIC_VERSION) \
	  upstream/OpenMAIC4course
	docker push $(REGISTRY_USER)/openmaic:$(OPENMAIC_VERSION)
	lzc-cli appstore copy-image $(REGISTRY_USER)/openmaic:$(OPENMAIC_VERSION)

pack: ## 打包全部三个 LPK 到 dist/
	@mkdir -p $(LPK_DIR)
	cd apps/deeptutor && lzc-cli project build -o ../../$(LPK_DIR)/deeptutor.lpk
	cd apps/openmaic  && lzc-cli project build -o ../../$(LPK_DIR)/openmaic.lpk
	cd apps/postgres  && lzc-cli project build -o ../../$(LPK_DIR)/edu-postgres.lpk
	@ls -la $(LPK_DIR)/

deploy: ## 按依赖顺序安装到盒子（PG → 应用）
	lzc-cli lpk install $(LPK_DIR)/edu-postgres.lpk
	lzc-cli lpk install $(LPK_DIR)/deeptutor.lpk
	lzc-cli lpk install $(LPK_DIR)/openmaic.lpk

backup: ## 备份盒子上的全部数据到本地 backups/<日期>/
	./scripts/backup.sh

update-upstream: ## 拉取上游最新提交（不自动升级，仅查看差异）
	git -C upstream/DeepTutor fetch origin main
	git -C upstream/OpenMAIC4course fetch origin main
	@echo "== DeepTutor 落后提交 =="
	git -C upstream/DeepTutor log --oneline HEAD..origin/main | head -20
	@echo "== OpenMAIC 落后提交 =="
	git -C upstream/OpenMAIC4course log --oneline HEAD..origin/main | head -20
	@echo "确认升级后：checkout 目标提交 + 改 versions.env + manifest tag + make pack"

clean: ## 清理 LPK 产物
	rm -rf $(LPK_DIR) apps/*/*.lpk
