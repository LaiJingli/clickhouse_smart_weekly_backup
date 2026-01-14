#!/bin/bash
# author by https://github.com/LaiJingli/clickhouse_smart_weekly_backup.git
# ================= 配置区 =================
LOG_FILE="/var/log/clickhouse-backup/backup_job.log"
CB_TOOL="/usr/bin/clickhouse-backup"

exec 1>>"$LOG_FILE"
exec 2>&1

echo "========================================================"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🚀 Backup Job Started"

# ================= 1. 计算时间维度 =================

ISO_YEAR=$(date +%G)
ISO_WEEK=$(date +%V)
TIMESTAMP=$(date +%F-%H%M)

FULL_PREFIX="${ISO_YEAR}-${ISO_WEEK}-weekly-full"
INC_PREFIX="${ISO_YEAR}-${ISO_WEEK}-daily-inc"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📅 Cycle Info: ${ISO_YEAR}-Week${ISO_WEEK}"

# ================= 2. 寻找本周基准 =================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔍 Checking remote for existing Full Backup: ${FULL_PREFIX}..."

BASE_FULL_BACKUP=$($CB_TOOL list remote | awk '{print $1}' | grep "^${FULL_PREFIX}" | sort | tail -n 1)

# ================= 3. 决策：全量 OR 增量 =================

if [ -z "$BASE_FULL_BACKUP" ]; then
    # === 场景 A: 全量备份 ===
    BACKUP_NAME="${FULL_PREFIX}-${TIMESTAMP}"
    BACKUP_ARGS="" 
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ No Full Backup found for this week."
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 💡 Action: Create NEW WEEKLY FULL backup."
else
    # === 场景 B: 增量备份 ===
    BACKUP_NAME="${INC_PREFIX}-${TIMESTAMP}"
    
    # 修复点：同时指定 --diff-from 和 --diff-from-remote
    #BACKUP_ARGS="--diff-from=${BASE_FULL_BACKUP} --diff-from-remote"
    BACKUP_ARGS="--diff-from-remote=${BASE_FULL_BACKUP}"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Found Base: ${BASE_FULL_BACKUP}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 💡 Action: Create INCREMENTAL based on Remote Weekly Full."
fi

# ================= 4. 执行备份 =================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️ Target Name: $BACKUP_NAME"

# 4.1 防重名清理
if $CB_TOOL list local | grep -q "$BACKUP_NAME"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🧹 Cleaning local duplicate..."
    $CB_TOOL delete local "$BACKUP_NAME" > /dev/null
fi

# 4.2 执行 create_remote
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ▶️ Executing: create_remote $BACKUP_NAME $BACKUP_ARGS"

OUTPUT=$($CB_TOOL create_remote "$BACKUP_NAME" $BACKUP_ARGS)
EXIT_CODE=$?

echo "$OUTPUT"

# ================= 5. 结果处理 =================

if [ $EXIT_CODE -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Backup SUCCESS."
    
    # 工具会根据 config.yml 自动清理，这里只需记录日志即可
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️ Old backups will be cleaned automatically by config policy."

else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Backup FAILED. Exit Code: $EXIT_CODE"
    
    # === 失败补救机制 ===
    if [[ "$OUTPUT" == *"no such file or directory"* ]] || [[ "$OUTPUT" == *"not found"* ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔄 Failure Reason: Base backup metadata missing."
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔄 Fallback: Retrying as FULL backup..."
        
        $CB_TOOL delete local "$BACKUP_NAME" > /dev/null
        $CB_TOOL create_remote "$BACKUP_NAME"
    fi
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🏁 Job Finished"
echo "========================================================"

