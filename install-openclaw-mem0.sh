#!/bin/bash
set -e

# ============================================================
#  openclaw-mem0 安装脚本
#  功能：
#    1. 安装 @ztorchan/openclaw-mem0 插件
#    2. 交互式配置 openclaw.json 中的 vectorStore / embedder / llm
#    3. 重启 openclaw gateway
# ============================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}       openclaw-mem0-with-cos-vectors 安装与配置脚本${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# ----------------------------------------------------------
# 第 1 步：安装插件
# ----------------------------------------------------------
echo -e "${GREEN}[1/3] 安装 openclaw-mem0 插件...${NC}"
echo ""

openclaw plugins install @ztorchan/openclaw-mem0

echo ""
echo -e "${GREEN}✅ 插件安装完成${NC}"
echo ""

# ===========================================================
# 第 2 步：交互式收集配置参数
# ===========================================================
echo -e "${GREEN}[2/3] 配置插件参数...${NC}"
echo ""

# -----------------------------------------------------------
# 2.0  mode & userId — 基础配置
# -----------------------------------------------------------
echo -e "${CYAN}━━━ 基础配置 ━━━${NC}"
echo ""
echo -e "  ${YELLOW}mode 已固定为: ${NC}${GREEN}open-source${NC}"
MEM0_MODE="open-source"
echo ""
read -rp "$(echo -e "  ${CYAN}用户标识 (userId) [默认: main]: ${NC}")" MEM0_USER_ID
MEM0_USER_ID=${MEM0_USER_ID:-main}
echo ""

# -----------------------------------------------------------
# 2.1  vectorStore (cos_vectors) — 必选
# -----------------------------------------------------------
echo -e "${CYAN}━━━ vectorStore 配置 (cos_vectors) ━━━${NC}"
echo -e "${YELLOW}请依次输入以下配置参数（带默认值的可直接回车跳过）：${NC}"
echo ""

# bucketName（必填）
while true; do
  read -rp "$(echo -e "  ${CYAN}向量存储桶名 (bucketName): ${NC}")" VS_BUCKET_NAME
  if [ -n "$VS_BUCKET_NAME" ]; then break; fi
  echo -e "  ${RED}⚠ bucketName 为必填项，请输入${NC}"
done

# indexName（默认 mem0）
read -rp "$(echo -e "  ${CYAN}向量索引名 (indexName) [默认: mem0]: ${NC}")" VS_INDEX_NAME
VS_INDEX_NAME=${VS_INDEX_NAME:-mem0}

# region（必填）
while true; do
  read -rp "$(echo -e "  ${CYAN}向量存储桶所在地域 (region, 例如 ap-guangzhou): ${NC}")" VS_REGION
  if [ -n "$VS_REGION" ]; then break; fi
  echo -e "  ${RED}⚠ region 为必填项，请输入${NC}"
done

# distanceMetric（默认 cosine）
read -rp "$(echo -e "  ${CYAN}距离度量 (distanceMetric) [cosine/euclidean, 默认: cosine]: ${NC}")" VS_DISTANCE_METRIC
VS_DISTANCE_METRIC=${VS_DISTANCE_METRIC:-cosine}

# secretId（必填）
while true; do
  read -rp "$(echo -e "  ${CYAN}腾讯云 SecretId: ${NC}")" VS_SECRET_ID
  if [ -n "$VS_SECRET_ID" ]; then break; fi
  echo -e "  ${RED}⚠ secretId 为必填项，请输入${NC}"
done

# secretKey（必填，隐藏输入）
while true; do
  read -srp "$(echo -e "  ${CYAN}腾讯云 SecretKey (输入不会显示): ${NC}")" VS_SECRET_KEY
  echo ""
  if [ -n "$VS_SECRET_KEY" ]; then break; fi
  echo -e "  ${RED}⚠ secretKey 为必填项，请输入${NC}"
done

# internalAccess（默认 false）
read -rp "$(echo -e "  ${CYAN}是否通过内网域名访问 (internalAccess) [true/false, 默认: false]: ${NC}")" VS_INTERNAL_ACCESS
VS_INTERNAL_ACCESS=${VS_INTERNAL_ACCESS:-false}

# embeddingModelDims（默认 1536）
read -rp "$(echo -e "  ${CYAN}Embedding 向量维度 (embeddingModelDims) [默认: 1536]: ${NC}")" VS_EMBEDDING_DIMS
VS_EMBEDDING_DIMS=${VS_EMBEDDING_DIMS:-1536}

echo ""

# -----------------------------------------------------------
# 2.2  embedder — 可选
# -----------------------------------------------------------
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
  echo -e "${CYAN}━━━ embedder 配置 ━━━${NC}"
  echo -e "${YELLOW}直接回车跳过的项将保留 openclaw.json 中的原有值${NC}"
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

# -----------------------------------------------------------
# 2.3  llm — 可选
# -----------------------------------------------------------
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
  echo -e "${CYAN}━━━ llm 配置 ━━━${NC}"
  echo -e "${YELLOW}直接回车跳过的项将保留 openclaw.json 中的原有值${NC}"
  echo ""
  read -rp "$(echo -e "  ${CYAN}LLM 提供商 (provider, 如 openai): ${NC}")" LLM_PROVIDER
  read -srp "$(echo -e "  ${CYAN}API Key (apiKey, 输入不会显示): ${NC}")" LLM_API_KEY
  echo ""
  read -rp "$(echo -e "  ${CYAN}模型名称 (model, 如 gpt-4-turbo-preview): ${NC}")" LLM_MODEL
  read -rp "$(echo -e "  ${CYAN}API 基础地址 (baseURL): ${NC}")" LLM_BASE_URL
  echo ""
fi

# -----------------------------------------------------------
# 配置确认
# -----------------------------------------------------------
echo ""
echo -e "${YELLOW}━━━ 配置确认 ━━━${NC}"
echo ""
echo -e "${CYAN}[基础配置]${NC}"
echo "  mode:                $MEM0_MODE"
echo "  userId:              $MEM0_USER_ID"
echo ""
echo -e "${CYAN}[vectorStore]${NC}"
echo "  bucketName:         $VS_BUCKET_NAME"
echo "  indexName:           $VS_INDEX_NAME"
echo "  region:              $VS_REGION"
echo "  distanceMetric:      $VS_DISTANCE_METRIC"
echo "  secretId:            $VS_SECRET_ID"
echo "  secretKey:           ******"
echo "  internalAccess:      $VS_INTERNAL_ACCESS"
echo "  embeddingModelDims:  $VS_EMBEDDING_DIMS"

if [[ "$CONFIGURE_EMBEDDER" == "y" || "$CONFIGURE_EMBEDDER" == "Y" ]]; then
  echo ""
  echo -e "${CYAN}[embedder]${NC}"
  [ -n "$EMB_PROVIDER" ]       && echo "  provider:       $EMB_PROVIDER"       || echo "  provider:       (保留原值)"
  [ -n "$EMB_API_KEY" ]        && echo "  apiKey:          ******"             || echo "  apiKey:          (保留原值)"
  [ -n "$EMB_MODEL" ]          && echo "  model:           $EMB_MODEL"          || echo "  model:           (保留原值)"
  [ -n "$EMB_BASE_URL" ]       && echo "  baseURL:         $EMB_BASE_URL"       || echo "  baseURL:         (保留原值)"
  [ -n "$EMB_URL" ]            && echo "  url:             $EMB_URL"            || echo "  url:             (保留原值)"
  [ -n "$EMB_EMBEDDING_DIMS" ] && echo "  embeddingDims:   $EMB_EMBEDDING_DIMS" || echo "  embeddingDims:   (保留原值)"
fi

if [[ "$CONFIGURE_LLM" == "y" || "$CONFIGURE_LLM" == "Y" ]]; then
  echo ""
  echo -e "${CYAN}[llm]${NC}"
  [ -n "$LLM_PROVIDER" ] && echo "  provider:  $LLM_PROVIDER" || echo "  provider:  (保留原值)"
  [ -n "$LLM_API_KEY" ]  && echo "  apiKey:     ******"       || echo "  apiKey:     (保留原值)"
  [ -n "$LLM_MODEL" ]    && echo "  model:      $LLM_MODEL"    || echo "  model:      (保留原值)"
  [ -n "$LLM_BASE_URL" ] && echo "  baseURL:    $LLM_BASE_URL" || echo "  baseURL:    (保留原值)"
fi

echo ""
read -rp "$(echo -e "${CYAN}确认以上配置？(y/n) [默认: y]: ${NC}")" CONFIRM
CONFIRM=${CONFIRM:-y}
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo -e "${RED}已取消配置，请重新运行脚本${NC}"
  exit 1
fi

# ----------------------------------------------------------
# 定位 openclaw.json 并写入配置
# ----------------------------------------------------------
OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"

if [ ! -f "$OPENCLAW_JSON" ]; then
  echo -e "${RED}❌ 未找到 $OPENCLAW_JSON，请确认 openclaw 已正确安装${NC}"
  exit 1
fi

echo ""
echo -e "${CYAN}正在写入配置到 $OPENCLAW_JSON ...${NC}"

# 导出所有变量供 Python 子进程读取
export MEM0_MODE MEM0_USER_ID
export VS_BUCKET_NAME VS_INDEX_NAME VS_REGION VS_DISTANCE_METRIC
export VS_SECRET_ID VS_SECRET_KEY VS_INTERNAL_ACCESS VS_EMBEDDING_DIMS
export CONFIGURE_EMBEDDER EMB_PROVIDER EMB_API_KEY EMB_MODEL EMB_BASE_URL EMB_URL EMB_EMBEDDING_DIMS
export CONFIGURE_LLM LLM_PROVIDER LLM_API_KEY LLM_MODEL LLM_BASE_URL

# 使用 python3 + json 模块安全地修改 JSON 配置
python3 << 'PYEOF'
import json, sys, os

config_path = os.path.expanduser("~/.openclaw/openclaw.json")

try:
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)
except Exception as e:
    print(f"❌ 读取 {config_path} 失败: {e}", file=sys.stderr)
    sys.exit(1)

# 辅助函数：仅在用户提供了值时才设置字段
def set_if(d, key, val):
    """当 val 非空字符串时设置 d[key] = val"""
    if val:
        d[key] = val

def set_if_int(d, key, val):
    """当 val 可转为整数时设置 d[key] = int(val)"""
    if val:
        try:
            d[key] = int(val)
        except ValueError:
            pass

# ============ 取得环境变量 ============
# vectorStore
vs_bucket_name     = os.environ.get("VS_BUCKET_NAME", "")
vs_index_name      = os.environ.get("VS_INDEX_NAME", "")
vs_region          = os.environ.get("VS_REGION", "")
vs_distance_metric = os.environ.get("VS_DISTANCE_METRIC", "")
vs_secret_id       = os.environ.get("VS_SECRET_ID", "")
vs_secret_key      = os.environ.get("VS_SECRET_KEY", "")
vs_internal_access = os.environ.get("VS_INTERNAL_ACCESS", "false")
vs_embedding_dims  = os.environ.get("VS_EMBEDDING_DIMS", "1536")

# embedder
configure_embedder = os.environ.get("CONFIGURE_EMBEDDER", "n")
emb_provider       = os.environ.get("EMB_PROVIDER", "")
emb_api_key        = os.environ.get("EMB_API_KEY", "")
emb_model          = os.environ.get("EMB_MODEL", "")
emb_base_url       = os.environ.get("EMB_BASE_URL", "")
emb_url            = os.environ.get("EMB_URL", "")
emb_embedding_dims = os.environ.get("EMB_EMBEDDING_DIMS", "")

# llm
configure_llm = os.environ.get("CONFIGURE_LLM", "n")
llm_provider  = os.environ.get("LLM_PROVIDER", "")
llm_api_key   = os.environ.get("LLM_API_KEY", "")
llm_model     = os.environ.get("LLM_MODEL", "")
llm_base_url  = os.environ.get("LLM_BASE_URL", "")

# ============ 构建配置 ============
plugins    = config.setdefault("plugins", {})
entries    = plugins.setdefault("entries", {})
mem0_entry = entries.setdefault("openclaw-mem0", {})
mem0_cfg   = mem0_entry.setdefault("config", {})
mem0_cfg["mode"] = os.environ.get("MEM0_MODE", "open-source")
mem0_cfg["userId"] = os.environ.get("MEM0_USER_ID", "main")
oss_cfg    = mem0_cfg.setdefault("oss", {})

# --- vectorStore (始终写入) ---
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

# --- embedder (仅用户选择配置时，且只修改用户提供了值的字段) ---
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

# --- llm (仅用户选择配置时，且只修改用户提供了值的字段) ---
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

# ============ 写入 ============
try:
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    print("✅ 配置写入成功")
except Exception as e:
    print(f"❌ 写入 {config_path} 失败: {e}", file=sys.stderr)
    sys.exit(1)

PYEOF

echo ""

# ----------------------------------------------------------
# 第 3 步：重启 gateway
# ----------------------------------------------------------
echo -e "${GREEN}[3/3] 重启 openclaw gateway...${NC}"
echo ""

openclaw gateway restart

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  🎉 安装配置完成！openclaw-mem0 已就绪${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}💡 提示：${NC}"
echo -e "   后续如需修改配置，可直接编辑 ${CYAN}~/.openclaw/openclaw.json${NC} 文件，"
echo -e "   修改完成后执行 ${CYAN}openclaw gateway restart${NC} 即可生效。"
echo ""
echo -e "   📖 更多配置说明请参考文档："
echo -e "   ${CYAN}https://docs.mem0.ai/integrations/openclaw${NC}"
echo ""
