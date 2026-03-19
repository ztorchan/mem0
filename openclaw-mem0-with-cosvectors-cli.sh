#!/bin/bash
set -e

# ============================================================
#  openclaw-mem0 管理脚本
#  用法：
#    openclaw-mem0-with-cosvectors-cli.sh install    — 安装插件并交互式配置
#    openclaw-mem0-with-cosvectors-cli.sh install --skip-config — 仅安装插件，跳过配置
#    openclaw-mem0-with-cosvectors-cli.sh uninstall  — 卸载插件（交互确认）
#    openclaw-mem0-with-cosvectors-cli.sh uninstall --force — 强制卸载，无需确认
#    openclaw-mem0-with-cosvectors-cli.sh config     — 重新交互式配置
#    openclaw-mem0-with-cosvectors-cli.sh enable     — 启用插件
#    openclaw-mem0-with-cosvectors-cli.sh disable    — 禁用插件
# ============================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PLUGIN_NAME="@ztorchan/openclaw-mem0"
PLUGIN_ENTRY_KEY="openclaw-mem0"
OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"

# ===========================================================
# 通用工具函数
# ===========================================================

# 打印带颜色的信息
info()  { echo -e "${GREEN}$1${NC}"; }
warn()  { echo -e "${YELLOW}$1${NC}"; }
error() { echo -e "${RED}$1${NC}"; }
title() { echo -e "${CYAN}$1${NC}"; }

# 检查 openclaw.json 是否存在
check_config_exists() {
  if [ ! -f "$OPENCLAW_JSON" ]; then
    error "❌ 未找到 $OPENCLAW_JSON，请确认 openclaw 已正确安装"
    exit 1
  fi
}

# 显示使用说明
show_usage() {
  echo ""
  title "============================================================"
  title "       openclaw-mem0 管理脚本"
  title "============================================================"
  echo ""
  echo "用法: $0 <命令>"
  echo ""
  title "可用命令:"
  echo "  install               安装插件并交互式配置"
  echo "  install --skip-config  仅安装插件，跳过交互式配置"
  echo "  uninstall              卸载插件并清理配置"
  echo "  uninstall --force      强制卸载，无需确认"
  echo "  config                 重新交互式配置（不重新安装）"
  echo "  enable                 启用插件"
  echo "  disable                禁用插件"
  echo ""
  title "示例:"
  echo "  $0 install"
  echo "  $0 config"
  echo "  $0 disable"
  echo ""
}

# ===========================================================
# 用 Python 修改 openclaw.json 中的某个字段
# 参数: $1 = python 表达式（对 config 字典操作）
# ===========================================================
python_edit_config() {
  local py_expr="$1"
  python3 -c "
import json, sys, os

config_path = os.path.expanduser('~/.openclaw/openclaw.json')

try:
    with open(config_path, 'r', encoding='utf-8') as f:
        config = json.load(f)
except Exception as e:
    print(f'❌ 读取 {config_path} 失败: {e}', file=sys.stderr)
    sys.exit(1)

plugins = config.setdefault('plugins', {})
entries = plugins.setdefault('entries', {})
mem0_entry = entries.setdefault('$PLUGIN_ENTRY_KEY', {})

$py_expr

try:
    with open(config_path, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
except Exception as e:
    print(f'❌ 写入 {config_path} 失败: {e}', file=sys.stderr)
    sys.exit(1)
"
}

# ===========================================================
# config 命令：交互式配置
# ===========================================================
do_config() {
  check_config_exists

  echo ""
  title "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  title "         交互式配置 openclaw-mem0"
  title "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # ---------------------------------------------------------
  # 基础配置
  # ---------------------------------------------------------
  title "━━━ 基础配置 ━━━"
  echo ""
  echo -e "  ${YELLOW}mode 已固定为: ${NC}${GREEN}open-source${NC}"
  MEM0_MODE="open-source"
  echo ""
  read -rp "$(echo -e "  ${CYAN}用户标识 (userId) [默认: main]: ${NC}")" MEM0_USER_ID
  MEM0_USER_ID=${MEM0_USER_ID:-main}
  echo ""

  # ---------------------------------------------------------
  # embedder — 可选
  # ---------------------------------------------------------
  CONFIGURE_EMBEDDER="n"
  echo ""
  read -rp "$(echo -e "${CYAN}是否配置 embedder（Embedding 模型）？(y/n) [默认: n]: ${NC}")" CONFIGURE_EMBEDDER
  CONFIGURE_EMBEDDER=${CONFIGURE_EMBEDDER:-n}

  EMB_PROVIDER=""
  EMB_API_KEY=""
  EMB_MODEL=""
  EMB_BASE_URL=""
  EMB_URL=""
  EMB_EMBEDDING_DIMS=""

  if [[ "$CONFIGURE_EMBEDDER" == "y" || "$CONFIGURE_EMBEDDER" == "Y" ]]; then
    echo ""
    title "━━━ embedder 配置 ━━━"
    warn "直接回车跳过的项将保留 openclaw.json 中的原有值"
    echo ""
    read -rp "$(echo -e "  ${CYAN}Embedder 提供商 (provider, 如 openai): ${NC}")" EMB_PROVIDER
    read -srp "$(echo -e "  ${CYAN}API Key (apiKey, 输入不会显示): ${NC}")" EMB_API_KEY
    echo ""
    read -rp "$(echo -e "  ${CYAN}模型名称 (model, 如 text-embedding-3-small): ${NC}")" EMB_MODEL
    read -rp "$(echo -e "  ${CYAN}API 基础地址 (baseURL): ${NC}")" EMB_BASE_URL
    read -rp "$(echo -e "  ${CYAN}嵌入服务地址 (url, 仅 Ollama 等本地服务需要): ${NC}")" EMB_URL
    read -rp "$(echo -e "  ${CYAN}Embedding 向量维度 (embeddingDims): ${NC}")" EMB_EMBEDDING_DIMS
    echo ""
  fi

  # ---------------------------------------------------------
  # vectorStore (cos_vectors) — 必选
  # ---------------------------------------------------------
  title "━━━ vectorStore 配置 (cos_vectors) ━━━"
  warn "请依次输入以下配置参数（带默认值的可直接回车跳过）："
  echo ""

  # bucketName（必填）
  while true; do
    read -rp "$(echo -e "  ${CYAN}向量存储桶名 (bucketName): ${NC}")" VS_BUCKET_NAME
    if [ -n "$VS_BUCKET_NAME" ]; then break; fi
    error "  ⚠ bucketName 为必填项，请输入"
  done

  # indexName（默认 mem0）
  read -rp "$(echo -e "  ${CYAN}向量索引名 (indexName) [默认: mem0]: ${NC}")" VS_INDEX_NAME
  VS_INDEX_NAME=${VS_INDEX_NAME:-mem0}

  # region（必填）
  while true; do
    read -rp "$(echo -e "  ${CYAN}向量存储桶所在地域 (region, 例如 ap-guangzhou): ${NC}")" VS_REGION
    if [ -n "$VS_REGION" ]; then break; fi
    error "  ⚠ region 为必填项，请输入"
  done

  # distanceMetric（默认 cosine）
  read -rp "$(echo -e "  ${CYAN}距离度量 (distanceMetric) [cosine/euclidean, 默认: cosine]: ${NC}")" VS_DISTANCE_METRIC
  VS_DISTANCE_METRIC=${VS_DISTANCE_METRIC:-cosine}

  # secretId（必填）
  while true; do
    read -rp "$(echo -e "  ${CYAN}腾讯云 SecretId: ${NC}")" VS_SECRET_ID
    if [ -n "$VS_SECRET_ID" ]; then break; fi
    error "  ⚠ secretId 为必填项，请输入"
  done

  # secretKey（必填，隐藏输入）
  while true; do
    read -srp "$(echo -e "  ${CYAN}腾讯云 SecretKey (输入不会显示): ${NC}")" VS_SECRET_KEY
    echo ""
    if [ -n "$VS_SECRET_KEY" ]; then break; fi
    error "  ⚠ secretKey 为必填项，请输入"
  done

  # internalAccess（默认 false）
  read -rp "$(echo -e "  ${CYAN}是否通过内网域名访问 (internalAccess) [true/false, 默认: false]: ${NC}")" VS_INTERNAL_ACCESS
  VS_INTERNAL_ACCESS=${VS_INTERNAL_ACCESS:-false}

  # embeddingModelDims（默认 1536）
  read -rp "$(echo -e "  ${CYAN}Embedding 向量维度 (embeddingModelDims) [默认: 1536]: ${NC}")" VS_EMBEDDING_DIMS
  VS_EMBEDDING_DIMS=${VS_EMBEDDING_DIMS:-1536}

  echo ""

  # ---------------------------------------------------------
  # llm — 可选
  # ---------------------------------------------------------
  CONFIGURE_LLM="n"
  echo ""
  read -rp "$(echo -e "${CYAN}是否配置 llm（大语言模型）？(y/n) [默认: n]: ${NC}")" CONFIGURE_LLM
  CONFIGURE_LLM=${CONFIGURE_LLM:-n}

  LLM_PROVIDER=""
  LLM_API_KEY=""
  LLM_MODEL=""
  LLM_BASE_URL=""

  if [[ "$CONFIGURE_LLM" == "y" || "$CONFIGURE_LLM" == "Y" ]]; then
    echo ""
    title "━━━ llm 配置 ━━━"
    warn "直接回车跳过的项将保留 openclaw.json 中的原有值"
    echo ""
    read -rp "$(echo -e "  ${CYAN}LLM 提供商 (provider, 如 openai): ${NC}")" LLM_PROVIDER
    read -srp "$(echo -e "  ${CYAN}API Key (apiKey, 输入不会显示): ${NC}")" LLM_API_KEY
    echo ""
    read -rp "$(echo -e "  ${CYAN}模型名称 (model, 如 gpt-4-turbo-preview): ${NC}")" LLM_MODEL
    read -rp "$(echo -e "  ${CYAN}API 基础地址 (baseURL): ${NC}")" LLM_BASE_URL
    echo ""
  fi

  # ---------------------------------------------------------
  # 配置确认
  # ---------------------------------------------------------
  echo ""
  warn "━━━ 配置确认 ━━━"
  echo ""
  title "[基础配置]"
  echo "  mode:                $MEM0_MODE"
  echo "  userId:              $MEM0_USER_ID"
  echo ""
  if [[ "$CONFIGURE_EMBEDDER" == "y" || "$CONFIGURE_EMBEDDER" == "Y" ]]; then
    title "[embedder]"
    [ -n "$EMB_PROVIDER" ]       && echo "  provider:       $EMB_PROVIDER"       || echo "  provider:       (保留原值)"
    [ -n "$EMB_API_KEY" ]        && echo "  apiKey:          ******"             || echo "  apiKey:          (保留原值)"
    [ -n "$EMB_MODEL" ]          && echo "  model:           $EMB_MODEL"          || echo "  model:           (保留原值)"
    [ -n "$EMB_BASE_URL" ]       && echo "  baseURL:         $EMB_BASE_URL"       || echo "  baseURL:         (保留原值)"
    [ -n "$EMB_URL" ]            && echo "  url:             $EMB_URL"            || echo "  url:             (保留原值)"
    [ -n "$EMB_EMBEDDING_DIMS" ] && echo "  embeddingDims:   $EMB_EMBEDDING_DIMS" || echo "  embeddingDims:   (保留原值)"
    echo ""
  fi

  title "[vectorStore]"
  echo "  bucketName:          $VS_BUCKET_NAME"
  echo "  indexName:            $VS_INDEX_NAME"
  echo "  region:               $VS_REGION"
  echo "  distanceMetric:       $VS_DISTANCE_METRIC"
  echo "  secretId:             $VS_SECRET_ID"
  echo "  secretKey:            ******"
  echo "  internalAccess:       $VS_INTERNAL_ACCESS"
  echo "  embeddingModelDims:   $VS_EMBEDDING_DIMS"

  if [[ "$CONFIGURE_LLM" == "y" || "$CONFIGURE_LLM" == "Y" ]]; then
    echo ""
    title "[llm]"
    [ -n "$LLM_PROVIDER" ] && echo "  provider:  $LLM_PROVIDER" || echo "  provider:  (保留原值)"
    [ -n "$LLM_API_KEY" ]  && echo "  apiKey:     ******"       || echo "  apiKey:     (保留原值)"
    [ -n "$LLM_MODEL" ]    && echo "  model:      $LLM_MODEL"    || echo "  model:      (保留原值)"
    [ -n "$LLM_BASE_URL" ] && echo "  baseURL:    $LLM_BASE_URL" || echo "  baseURL:    (保留原值)"
  fi

  echo ""
  read -rp "$(echo -e "${CYAN}确认以上配置？(y/n) [默认: y]: ${NC}")" CONFIRM
  CONFIRM=${CONFIRM:-y}
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    error "已取消配置，请重新运行 $0 config"
    exit 1
  fi

  # ---------------------------------------------------------
  # 写入 openclaw.json
  # ---------------------------------------------------------
  echo ""
  title "正在写入配置到 $OPENCLAW_JSON ..."

  # 导出所有变量供 Python 子进程读取
  export MEM0_MODE MEM0_USER_ID
  export VS_BUCKET_NAME VS_INDEX_NAME VS_REGION VS_DISTANCE_METRIC
  export VS_SECRET_ID VS_SECRET_KEY VS_INTERNAL_ACCESS VS_EMBEDDING_DIMS
  export CONFIGURE_EMBEDDER EMB_PROVIDER EMB_API_KEY EMB_MODEL EMB_BASE_URL EMB_URL EMB_EMBEDDING_DIMS
  export CONFIGURE_LLM LLM_PROVIDER LLM_API_KEY LLM_MODEL LLM_BASE_URL

  python3 << 'PYEOF'
import json, sys, os

config_path = os.path.expanduser("~/.openclaw/openclaw.json")

try:
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)
except Exception as e:
    print(f"❌ 读取 {config_path} 失败: {e}", file=sys.stderr)
    sys.exit(1)

def set_if(d, key, val):
    if val:
        d[key] = val

def set_if_int(d, key, val):
    if val:
        try:
            d[key] = int(val)
        except ValueError:
            pass

# 取得环境变量
vs_bucket_name     = os.environ.get("VS_BUCKET_NAME", "")
vs_index_name      = os.environ.get("VS_INDEX_NAME", "")
vs_region          = os.environ.get("VS_REGION", "")
vs_distance_metric = os.environ.get("VS_DISTANCE_METRIC", "")
vs_secret_id       = os.environ.get("VS_SECRET_ID", "")
vs_secret_key      = os.environ.get("VS_SECRET_KEY", "")
vs_internal_access = os.environ.get("VS_INTERNAL_ACCESS", "false")
vs_embedding_dims  = os.environ.get("VS_EMBEDDING_DIMS", "1536")

configure_embedder = os.environ.get("CONFIGURE_EMBEDDER", "n")
emb_provider       = os.environ.get("EMB_PROVIDER", "")
emb_api_key        = os.environ.get("EMB_API_KEY", "")
emb_model          = os.environ.get("EMB_MODEL", "")
emb_base_url       = os.environ.get("EMB_BASE_URL", "")
emb_url            = os.environ.get("EMB_URL", "")
emb_embedding_dims = os.environ.get("EMB_EMBEDDING_DIMS", "")

configure_llm = os.environ.get("CONFIGURE_LLM", "n")
llm_provider  = os.environ.get("LLM_PROVIDER", "")
llm_api_key   = os.environ.get("LLM_API_KEY", "")
llm_model     = os.environ.get("LLM_MODEL", "")
llm_base_url  = os.environ.get("LLM_BASE_URL", "")

# 构建配置
plugins    = config.setdefault("plugins", {})
entries    = plugins.setdefault("entries", {})
mem0_entry = entries.setdefault("openclaw-mem0", {})
mem0_entry["enabled"] = True
mem0_cfg   = mem0_entry.setdefault("config", {})
mem0_cfg["mode"] = os.environ.get("MEM0_MODE", "open-source")
mem0_cfg["userId"] = os.environ.get("MEM0_USER_ID", "main")
oss_cfg    = mem0_cfg.setdefault("oss", {})

# vectorStore
vector_store = {
    "provider": "cos_vectors",
    "config": {
        "bucketName": vs_bucket_name,
        "indexName": vs_index_name,
        "region": vs_region,
        "distanceMetric": vs_distance_metric,
        "secretId": vs_secret_id,
        "secretKey": vs_secret_key,
        "internalAccess": vs_internal_access.lower() == "true",
        "embeddingModelDims": int(vs_embedding_dims)
    }
}
oss_cfg["vectorStore"] = vector_store

# embedder
if configure_embedder.lower() == "y":
    embedder = oss_cfg.get("embedder", {})
    set_if(embedder, "provider", emb_provider)
    embedder_config = embedder.get("config", {})
    set_if(embedder_config, "apiKey", emb_api_key)
    set_if(embedder_config, "model", emb_model)
    set_if(embedder_config, "baseURL", emb_base_url)
    set_if(embedder_config, "url", emb_url)
    set_if_int(embedder_config, "embeddingDims", emb_embedding_dims)
    if embedder_config:
        embedder["config"] = embedder_config
    if embedder:
        oss_cfg["embedder"] = embedder

# llm
if configure_llm.lower() == "y":
    llm = oss_cfg.get("llm", {})
    set_if(llm, "provider", llm_provider)
    llm_config = llm.get("config", {})
    set_if(llm_config, "apiKey", llm_api_key)
    set_if(llm_config, "model", llm_model)
    set_if(llm_config, "baseURL", llm_base_url)
    if llm_config:
        llm["config"] = llm_config
    if llm:
        oss_cfg["llm"] = llm

# 写入
try:
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    print("✅ 配置写入成功")
except Exception as e:
    print(f"❌ 写入 {config_path} 失败: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

  echo ""
}

# ===========================================================
# 检查插件是否已安装或存在残留
# 返回值: 0 = 可以继续安装, 1 = 用户选择退出
# ===========================================================
check_existing_installation() {
  local plugin_installed=false
  local config_exists=false
  local extension_dir_exists=false
  local EXTENSION_DIR="$HOME/.openclaw/extensions/openclaw-mem0"

  # 检查插件是否已通过 openclaw plugins 安装
  if openclaw plugins list 2>/dev/null | grep -q "$PLUGIN_ENTRY_KEY"; then
    plugin_installed=true
  fi

  # 检查 openclaw.json 中是否存在配置
  local allow_exists=false
  local slot_exists=false
  if [ -f "$OPENCLAW_JSON" ]; then
    local config_check_result
    config_check_result=$(python3 -c "
import json, os
config_path = os.path.expanduser('~/.openclaw/openclaw.json')
try:
    with open(config_path, 'r', encoding='utf-8') as f:
        config = json.load(f)
    plugins = config.get('plugins', {})
    entries = plugins.get('entries', {})
    allow_list = plugins.get('allow', [])
    slots = plugins.get('slots', {})
    has_entry = 'yes' if 'openclaw-mem0' in entries else 'no'
    has_allow = 'yes' if 'openclaw-mem0' in allow_list else 'no'
    has_slot = 'yes' if slots.get('memory') == 'openclaw-mem0' else 'no'
    print(f'{has_entry},{has_allow},{has_slot}')
except:
    print('no,no,no')
" 2>/dev/null)
    local entry_flag allow_flag slot_flag
    IFS=',' read -r entry_flag allow_flag slot_flag <<< "$config_check_result"
    if [ "$entry_flag" = "yes" ]; then
      config_exists=true
    fi
    if [ "$allow_flag" = "yes" ]; then
      allow_exists=true
    fi
    if [ "$slot_flag" = "yes" ]; then
      slot_exists=true
    fi
  fi

  # 检查 extensions 目录是否存在残留
  if [ -d "$EXTENSION_DIR" ]; then
    extension_dir_exists=true
  fi

  # 全部不存在，可以直接安装
  if [ "$plugin_installed" = false ] && [ "$config_exists" = false ] && [ "$extension_dir_exists" = false ] && [ "$allow_exists" = false ] && [ "$slot_exists" = false ]; then
    return 0
  fi

  # 存在已安装的插件或残留
  echo ""
  warn "⚠ 检测到已有 openclaw-mem0 的安装痕迹："
  echo ""
  if [ "$plugin_installed" = true ]; then
    echo -e "  ${YELLOW}●${NC} 插件 ${CYAN}$PLUGIN_NAME${NC} 已安装"
  fi
  if [ "$config_exists" = true ]; then
    echo -e "  ${YELLOW}●${NC} ${CYAN}$OPENCLAW_JSON${NC} 中存在 openclaw-mem0 配置"
  fi
  if [ "$allow_exists" = true ]; then
    echo -e "  ${YELLOW}●${NC} ${CYAN}plugins.allow${NC} 列表中存在 openclaw-mem0"
  fi
  if [ "$slot_exists" = true ]; then
    echo -e "  ${YELLOW}●${NC} ${CYAN}plugins.slots.memory${NC} 仍指向 openclaw-mem0"
  fi
  if [ "$extension_dir_exists" = true ]; then
    echo -e "  ${YELLOW}●${NC} 存在扩展目录残留 ${CYAN}$EXTENSION_DIR${NC}"
  fi
  echo ""

  # 根据情况提示用户
  if [ "$plugin_installed" = true ] && [ "$config_exists" = true ]; then
    warn "插件已完整安装，如需重新配置请使用: $0 config"
  fi

  echo ""
  read -rp "$(echo -e "${CYAN}是否先卸载/清理后重新安装？(y/n) [默认: n]: ${NC}")" DO_CLEAN
  DO_CLEAN=${DO_CLEAN:-n}

  if [[ "$DO_CLEAN" != "y" && "$DO_CLEAN" != "Y" ]]; then
    warn "已取消安装"
    return 1
  fi

  # 执行清理
  echo ""
  title "正在清理..."

  # 清理 openclaw.json 中的配置
  if [ "$config_exists" = true ] || [ "$allow_exists" = true ] || [ "$slot_exists" = true ]; then
    info "  清理 openclaw.json 中的插件配置..."
    python3 -c "
import json, os
config_path = os.path.expanduser('~/.openclaw/openclaw.json')
with open(config_path, 'r', encoding='utf-8') as f:
    config = json.load(f)
plugins = config.get('plugins', {})
entries = plugins.get('entries', {})
if 'openclaw-mem0' in entries:
    del entries['openclaw-mem0']
    print('  ✅ 已移除 plugins.entries.openclaw-mem0')
allow_list = plugins.get('allow', [])
if 'openclaw-mem0' in allow_list:
    allow_list.remove('openclaw-mem0')
    plugins['allow'] = allow_list
    print('  ✅ 已从 plugins.allow 中移除 openclaw-mem0')
slots = plugins.get('slots', {})
if slots.get('memory') == 'openclaw-mem0':
    slots['memory'] = 'memory-core'
    print('  ✅ 已将 plugins.slots.memory 复原为 memory-core')
with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
"
  fi

  # 卸载已安装的插件
  if [ "$plugin_installed" = true ]; then
    info "  卸载已安装的插件..."
    openclaw plugins uninstall "$PLUGIN_NAME" 2>/dev/null || true
    info "  ✅ 插件已卸载"
  fi

  # 清理 extensions 目录残留
  if [ -d "$EXTENSION_DIR" ]; then
    info "  清理扩展目录残留 $EXTENSION_DIR ..."
    rm -rf "$EXTENSION_DIR"
    info "  ✅ 扩展目录已清理"
  fi

  echo ""
  info "清理完成，继续安装流程..."
  echo ""
  return 0
}

# ===========================================================
# install 命令
# ===========================================================
do_install() {
  local skip_config=false
  # 解析参数
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-config)
        skip_config=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  echo ""
  title "============================================================"
  title "       openclaw-mem0 安装与配置"
  title "============================================================"
  echo ""

  # 前置检查：是否已安装或存在残留
  if ! check_existing_installation; then
    exit 0
  fi

  # 第 1 步：安装插件
  info "[1/2] 安装 openclaw-mem0 插件..."
  echo ""
  openclaw plugins install "$PLUGIN_NAME"
  echo ""
  info "✅ 插件安装完成"
  echo ""

  # 判断是否跳过配置
  local DO_CONFIG_NOW="y"
  if [ "$skip_config" = true ]; then
    DO_CONFIG_NOW="n"
  else
    read -rp "$(echo -e "${CYAN}是否立刻进行交互式配置？(y/n) [默认: y]: ${NC}")" DO_CONFIG_NOW
    DO_CONFIG_NOW=${DO_CONFIG_NOW:-y}
  fi

  if [[ "$DO_CONFIG_NOW" == "y" || "$DO_CONFIG_NOW" == "Y" ]]; then
    # 第 2 步：交互式配置
    info "[2/2] 配置插件参数..."
    do_config

    # 重启 gateway
    restart_prompt

    info "============================================================"
    info "  🎉 安装配置完成！openclaw-mem0 已就绪"
    info "============================================================"
  else
    echo ""
    info "============================================================"
    info "  ✅ 插件安装完成（未配置）"
    info "============================================================"
  fi

  echo ""
  warn "💡 你可以随时通过以下命令修改插件配置："
  echo -e "   ${CYAN}$0 config${NC}"
  echo ""
  show_tips
}

# ===========================================================
# uninstall 命令
# ===========================================================
do_uninstall() {
  local force_mode=false
  # 解析参数
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)
        force_mode=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  echo ""
  title "============================================================"
  title "       卸载 openclaw-mem0"
  title "============================================================"
  echo ""

  # 前置检查：是否存在已安装的插件或残留
  local has_plugin=false
  local has_config=false
  local has_allow=false
  local has_slot=false
  local has_ext_dir=false
  local EXTENSION_DIR="$HOME/.openclaw/extensions/openclaw-mem0"

  if openclaw plugins list 2>/dev/null | grep -q "$PLUGIN_ENTRY_KEY"; then
    has_plugin=true
  fi

  if [ -f "$OPENCLAW_JSON" ]; then
    local config_check_result
    config_check_result=$(python3 -c "
import json, os
config_path = os.path.expanduser('~/.openclaw/openclaw.json')
try:
    with open(config_path, 'r', encoding='utf-8') as f:
        config = json.load(f)
    plugins = config.get('plugins', {})
    entries = plugins.get('entries', {})
    allow_list = plugins.get('allow', [])
    slots = plugins.get('slots', {})
    has_entry = 'yes' if 'openclaw-mem0' in entries else 'no'
    has_allow = 'yes' if 'openclaw-mem0' in allow_list else 'no'
    has_slot = 'yes' if slots.get('memory') == 'openclaw-mem0' else 'no'
    print(f'{has_entry},{has_allow},{has_slot}')
except:
    print('no,no,no')
" 2>/dev/null)
    local entry_flag allow_flag slot_flag
    IFS=',' read -r entry_flag allow_flag slot_flag <<< "$config_check_result"
    if [ "$entry_flag" = "yes" ]; then
      has_config=true
    fi
    if [ "$allow_flag" = "yes" ]; then
      has_allow=true
    fi
    if [ "$slot_flag" = "yes" ]; then
      has_slot=true
    fi
  fi

  if [ -d "$EXTENSION_DIR" ]; then
    has_ext_dir=true
  fi

  # 全部不存在，无需卸载
  if [ "$has_plugin" = false ] && [ "$has_config" = false ] && [ "$has_ext_dir" = false ] && [ "$has_allow" = false ] && [ "$has_slot" = false ]; then
    info "ℹ️  未检测到 openclaw-mem0 的安装或残留，无需卸载"
    echo ""
    exit 0
  fi

  # 显示检测到的内容
  info "检测到以下 openclaw-mem0 相关内容："
  echo ""
  if [ "$has_plugin" = true ]; then
    echo -e "  ${YELLOW}●${NC} 插件 ${CYAN}$PLUGIN_NAME${NC} 已安装"
  fi
  if [ "$has_config" = true ]; then
    echo -e "  ${YELLOW}●${NC} ${CYAN}$OPENCLAW_JSON${NC} 中存在 openclaw-mem0 配置"
  fi
  if [ "$has_allow" = true ]; then
    echo -e "  ${YELLOW}●${NC} ${CYAN}plugins.allow${NC} 列表中存在 openclaw-mem0"
  fi
  if [ "$has_slot" = true ]; then
    echo -e "  ${YELLOW}●${NC} ${CYAN}plugins.slots.memory${NC} 仍指向 openclaw-mem0"
  fi
  if [ "$has_ext_dir" = true ]; then
    echo -e "  ${YELLOW}●${NC} 存在扩展目录 ${CYAN}$EXTENSION_DIR${NC}"
  fi
  echo ""

  if [ "$force_mode" = false ]; then
    read -rp "$(echo -e "${YELLOW}确认要卸载 openclaw-mem0 并清理以上内容？(y/n) [默认: n]: ${NC}")" CONFIRM
    CONFIRM=${CONFIRM:-n}
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
      warn "已取消卸载"
      exit 0
    fi
  else
    warn "⚡ 强制模式：跳过确认，直接执行卸载..."
  fi

  echo ""

  # 清理 openclaw.json 中的插件配置
  if [ -f "$OPENCLAW_JSON" ]; then
    title "正在清理 openclaw.json 中的插件配置..."
    python3 -c "
import json, os

config_path = os.path.expanduser('~/.openclaw/openclaw.json')
with open(config_path, 'r', encoding='utf-8') as f:
    config = json.load(f)

plugins = config.get('plugins', {})
entries = plugins.get('entries', {})
changed = False

if 'openclaw-mem0' in entries:
    del entries['openclaw-mem0']
    print('✅ 已移除 plugins.entries.openclaw-mem0')
    changed = True

allow_list = plugins.get('allow', [])
if 'openclaw-mem0' in allow_list:
    allow_list.remove('openclaw-mem0')
    plugins['allow'] = allow_list
    print('✅ 已从 plugins.allow 中移除 openclaw-mem0')
    changed = True

slots = plugins.get('slots', {})
if slots.get('memory') == 'openclaw-mem0':
    slots['memory'] = 'memory-core'
    print('✅ 已将 plugins.slots.memory 复原为 memory-core')
    changed = True

if changed:
    with open(config_path, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
else:
    print('ℹ️  openclaw.json 中未找到 openclaw-mem0 相关配置，跳过')
"
    echo ""
  fi

  # 卸载插件
  info "正在卸载插件..."
  openclaw plugins uninstall "$PLUGIN_NAME" 2>/dev/null || true
  echo ""

  # 兜底：清理 extensions 目录残留
  local EXTENSION_DIR="$HOME/.openclaw/extensions/openclaw-mem0"
  if [ -d "$EXTENSION_DIR" ]; then
    info "正在清理扩展目录残留 $EXTENSION_DIR ..."
    rm -rf "$EXTENSION_DIR"
    info "✅ 扩展目录已清理"
    echo ""
  fi

  # 重启 gateway
  restart_prompt

  info "✅ openclaw-mem0 已卸载完成"
  echo ""
}

# ===========================================================
# enable 命令
# ===========================================================
do_enable() {
  check_config_exists

  echo ""
  title "启用 openclaw-mem0 ..."

  python_edit_config "
mem0_entry['enabled'] = True
slots = plugins.setdefault('slots', {})
slots['memory'] = 'openclaw-mem0'
"

  info "✅ openclaw-mem0 已启用"
  echo ""

  restart_prompt
}

# ===========================================================
# disable 命令
# ===========================================================
do_disable() {
  check_config_exists

  echo ""
  title "禁用 openclaw-mem0 ..."

  python_edit_config "
mem0_entry['enabled'] = False
slots = plugins.setdefault('slots', {})
slots['memory'] = 'memory-core'
"

  info "✅ openclaw-mem0 已禁用"
  echo ""

  restart_prompt
}

# ===========================================================
# 重启提示
# ===========================================================
restart_prompt() {
  read -rp "$(echo -e "${CYAN}是否立即重启 openclaw gateway 使配置生效？(y/n) [默认: y]: ${NC}")" DO_RESTART
  DO_RESTART=${DO_RESTART:-y}
  if [[ "$DO_RESTART" == "y" || "$DO_RESTART" == "Y" ]]; then
    echo ""
    info "正在重启 openclaw gateway..."
    openclaw gateway restart
    echo ""
    info "✅ 重启完成"
  else
    echo ""
    warn "💡 请记得手动执行: openclaw gateway restart"
  fi
  echo ""
}

# ===========================================================
# 提示信息
# ===========================================================
show_tips() {
  warn "💡 提示："
  echo -e "   后续如需修改配置，可直接编辑 ${CYAN}~/.openclaw/openclaw.json${NC} 文件，"
  echo -e "   修改完成后执行 ${CYAN}openclaw gateway restart${NC} 即可生效。"
  echo ""
  echo -e "   也可使用本脚本快速管理："
  echo -e "   ${CYAN}$0 config${NC}     — 重新配置"
  echo -e "   ${CYAN}$0 enable${NC}     — 启用插件"
  echo -e "   ${CYAN}$0 disable${NC}    — 禁用插件"
  echo -e "   ${CYAN}$0 uninstall${NC}  — 卸载插件"
  echo ""
  echo -e "   📖 更多配置说明请参考文档："
  echo -e "   ${CYAN}https://docs.mem0.ai/integrations/openclaw${NC}"
  echo ""
}

# ===========================================================
# 入口：解析命令
# ===========================================================
case "${1:-}" in
  install)
    shift
    do_install "$@"
    ;;
  uninstall)
    shift
    do_uninstall "$@"
    ;;
  config)
    # 检查插件是否已安装
    if ! openclaw plugins list 2>/dev/null | grep -q "$PLUGIN_ENTRY_KEY"; then
      error "❌ 插件 $PLUGIN_ENTRY_KEY 尚未安装，请先执行: $0 install"
      exit 1
    fi
    do_config
    restart_prompt
    show_tips
    ;;
  enable)
    # 检查插件是否已安装
    if ! openclaw plugins list 2>/dev/null | grep -q "$PLUGIN_ENTRY_KEY"; then
      error "❌ 插件 $PLUGIN_ENTRY_KEY 尚未安装，请先执行: $0 install"
      exit 1
    fi
    do_enable
    ;;
  disable)
    # 检查插件是否已安装
    if ! openclaw plugins list 2>/dev/null | grep -q "$PLUGIN_ENTRY_KEY"; then
      error "❌ 插件 $PLUGIN_ENTRY_KEY 尚未安装，请先执行: $0 install"
      exit 1
    fi
    do_disable
    ;;
  *)
    show_usage
    if [ -n "${1:-}" ]; then
      error "❌ 未知命令: $1"
      echo ""
    fi
    exit 1
    ;;
esac
