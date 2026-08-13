#!/usr/bin/env bash
# ============================================================
# backup.sh — 备份懒猫盒子上的全部应用数据到本地 backups/<日期>/
#
# 覆盖：
#   postgres  应用: /lzcapp/var/pgdata   （共享数据库）
#   deeptutor 应用: /lzcapp/var/data     （知识库/会话/设置/记忆）
#   openmaic  应用: /lzcapp/var/data     （服务端课程产物）
#
# 依赖：lzc-cli 已登录且盒子可达。也可直接用 SSH + rsync 替代。
# 注意：备份 PG 建议先 pg_dump 做逻辑备份（本脚本同时执行），
#       纯目录拷贝要求 PG 无写入或接受 crash-consistent 快照。
# ============================================================
set -euo pipefail

DATE=$(date +%Y%m%d-%H%M%S)
DEST="backups/${DATE}"
mkdir -p "${DEST}"

echo "==> [1/3] PostgreSQL 逻辑备份（pg_dump）"
for db in edu edu_deeptutor edu_openmaic; do
  # 库不存在时跳过（首次部署可能尚未建库）
  lzc-cli project exec --app cloud.lazycat.app.edu-postgres -- \
    sh -c "pg_dump -U edu ${db}" > "${DEST}/pg-${db}.sql" 2>/dev/null \
    && echo "    ✓ ${db}" || { echo "    - ${db} 不存在，跳过"; rm -f "${DEST}/pg-${db}.sql"; }
done

echo "==> [2/3] PostgreSQL 数据目录快照"
lzc-cli project exec --app cloud.lazycat.app.edu-postgres -- \
  tar czf - -C /lzcapp/var pgdata > "${DEST}/pgdata.tar.gz"

echo "==> [3/3] 应用数据目录快照"
lzc-cli project exec --app cloud.lazycat.app.deeptutor -- \
  tar czf - -C /lzcapp/var data > "${DEST}/deeptutor-data.tar.gz"
lzc-cli project exec --app cloud.lazycat.app.openmaic -- \
  tar czf - -C /lzcapp/var data > "${DEST}/openmaic-data.tar.gz"

echo ""
echo "备份完成 → ${DEST}/"
ls -lh "${DEST}"
echo ""
echo "恢复：反向执行 tar xzf 到对应 /lzcapp/var，psql 导入 *.sql，重启应用。"
