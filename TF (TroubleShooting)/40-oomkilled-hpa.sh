#!/usr/bin/env bash
# =============================================================================
# TSC Scenario 1: OOMKilled 반복 + HPA 미작동 복합 장애 탐지
# =============================================================================
# 설명:
#   - 단순 OOMKilled 1회 발생은 기본 시나리오에서 커버됨
#   - 이 스크립트는 단시간 내 반복 OOMKilled + HPA가 스케일 아웃 못 하는
#     "복합 무음 장애(silent failure)" 상태를 탐지함
#
# 탐지 조건 (AND):
#   1) restartCount >= RESTART_THRESHOLD (기본 3회) 인 파드가 존재
#   2) 해당 파드의 종료 이유가 OOMKilled
#   3) 동일 네임스페이스에 HPA가 존재하고 ScalingActive=false 또는
#      metrics-server 파드가 Running 상태가 아님
#
# 사용법:
#   ./40-oomkilled-hpa.sh [--namespace <ns>] [--threshold <n>]
#   옵션 없을 시 전체 네임스페이스 대상, threshold=3
# =============================================================================

set -euo pipefail

# 색상 출력 
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# 기본값 
NAMESPACE=""
RESTART_THRESHOLD=3
FOUND_ISSUE=false

# 인자 파싱
while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace|-n) NAMESPACE="$2"; shift 2 ;;
    --threshold|-t) RESTART_THRESHOLD="$2"; shift 2 ;;
    --help|-h)
      echo "사용법: $0 [--namespace <ns>] [--threshold <n>]"
      exit 0
      ;;
    *) echo "알 수 없는 옵션: $1"; exit 1 ;;
  esac
done

NS_OPTS=""
[[ -n "$NAMESPACE" ]] && NS_OPTS="-n $NAMESPACE" || NS_OPTS="--all-namespaces"

# 헤더 출력
echo ""
echo -e "${BOLD}${CYAN}================================================================${RESET}"
echo -e "${BOLD}${CYAN}  TSC Scenario 1: OOMKilled 반복 + HPA 미작동 탐지${RESET}"
echo -e "${BOLD}${CYAN}================================================================${RESET}"
echo -e "  검사 범위  : ${NS_OPTS}"
echo -e "  재시작 임계: ${RESTART_THRESHOLD}회 이상"
echo -e "  실행 시각  : $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 함수: kubectl 존재 확인
check_kubectl() {
  if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}[ERROR] kubectl 이 설치되어 있지 않습니다.${RESET}"
    exit 1
  fi
}

# 함수: metrics-server 상태 확인
check_metrics_server() {
  local ms_status
  ms_status=$(kubectl get pods -n kube-system \
    -l "k8s-app=metrics-server" \
    --no-headers 2>/dev/null | awk '{print $3}' | head -1)

  if [[ -z "$ms_status" ]]; then
    ms_status=$(kubectl get pods -n kube-system \
      --no-headers 2>/dev/null | grep "metrics-server" | awk '{print $4}' | head -1)
  fi

  echo "${ms_status:-NOT_FOUND}"
}

# 함수: HPA ScalingActive 조건 확인 
check_hpa_in_ns() {
  local ns="$1"
  local hpa_issues=()

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local hpa_name
    hpa_name=$(echo "$line" | awk '{print $1}')
    local conditions
    conditions=$(kubectl get hpa "$hpa_name" -n "$ns" \
      -o jsonpath='{.status.conditions}' 2>/dev/null)

    # ScalingActive=false 확인
    if echo "$conditions" | grep -q '"reason":"FailedGetScale\|FailedComputeMetricsReplicas\|InvalidSelector"'; then
      hpa_issues+=("HPA[$hpa_name] ScalingActive=false — 메트릭 수집 실패 의심")
    fi

    local current_replicas min_replicas max_replicas
    current_replicas=$(kubectl get hpa "$hpa_name" -n "$ns" \
      -o jsonpath='{.status.currentReplicas}' 2>/dev/null)
    max_replicas=$(kubectl get hpa "$hpa_name" -n "$ns" \
      -o jsonpath='{.spec.maxReplicas}' 2>/dev/null)

    # 이미 maxReplicas에 닿은 경우
    if [[ -n "$current_replicas" && -n "$max_replicas" && "$current_replicas" -ge "$max_replicas" ]]; then
      hpa_issues+=("HPA[$hpa_name] maxReplicas($max_replicas)에 도달 — 스케일 아웃 불가")
    fi

  done < <(kubectl get hpa -n "$ns" --no-headers 2>/dev/null | awk '{print $1}')

  printf '%s\n' "${hpa_issues[@]+"${hpa_issues[@]}"}"
}

# 메인 탐지 로직 
check_kubectl

echo -e "${BOLD}[STEP 1] metrics-server 상태 확인${RESET}"
MS_STATUS=$(check_metrics_server)
if [[ "$MS_STATUS" != "Running" ]]; then
  echo -e "  ${RED}[WARNING] metrics-server 상태: ${MS_STATUS}${RESET}"
  echo -e "  ${YELLOW}  → HPA 메트릭 수집 불가 가능성 있음${RESET}"
  FOUND_ISSUE=true
else
  echo -e "  ${GREEN}[OK] metrics-server Running${RESET}"
fi
echo ""

echo -e "${BOLD}[STEP 2] OOMKilled 반복 파드 탐지 (threshold: ${RESTART_THRESHOLD}회)${RESET}"

# 파드 목록 수집: namespace pod container restartCount lastState reason
if [[ "$NS_OPTS" == "--all-namespaces" ]]; then
  POD_JSON=$(kubectl get pods --all-namespaces -o json 2>/dev/null)
else
  POD_JSON=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null)
fi

OOM_PODS=()

while IFS='|' read -r pod_ns pod_name container restart_count last_reason; do
  [[ -z "$pod_name" ]] && continue
  if [[ "$restart_count" -ge "$RESTART_THRESHOLD" && "$last_reason" == "OOMKilled" ]]; then
    OOM_PODS+=("${pod_ns}|${pod_name}|${container}|${restart_count}")
    echo -e "  ${RED}[DETECTED] ${pod_ns}/${pod_name} — 컨테이너: ${container}${RESET}"
    echo -e "            재시작: ${restart_count}회 / 마지막 종료 이유: ${last_reason}"

    # 리소스 limit 정보 출력
    local_mem_limit=$(echo "$POD_JSON" | python3 -c "
import json,sys
data=json.load(sys.stdin)
for item in data.get('items',[]):
    if item['metadata']['name']=='${pod_name}' and item['metadata']['namespace']=='${pod_ns}':
        for c in item['spec']['containers']:
            if c['name']=='${container}':
                lim=c.get('resources',{}).get('limits',{})
                print(lim.get('memory','미설정'))
" 2>/dev/null || echo "조회불가")
    echo -e "            메모리 limit: ${local_mem_limit}"
    FOUND_ISSUE=true
  fi
done < <(echo "$POD_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    ns   = item['metadata']['namespace']
    name = item['metadata']['name']
    for cs in item.get('status', {}).get('containerStatuses', []):
        cname   = cs.get('name', '')
        restart = cs.get('restartCount', 0)
        reason  = cs.get('lastState', {}).get('terminated', {}).get('reason', '')
        print(f'{ns}|{name}|{cname}|{restart}|{reason}')
" 2>/dev/null)

if [[ ${#OOM_PODS[@]} -eq 0 ]]; then
  echo -e "  ${GREEN}[OK] OOMKilled 반복 파드 없음${RESET}"
fi
echo ""

echo -e "${BOLD}[STEP 3] HPA 스케일 아웃 불가 조건 교차 확인${RESET}"

if [[ ${#OOM_PODS[@]} -gt 0 ]]; then
  # OOM 파드가 있는 네임스페이스만 HPA 확인
  declare -A CHECKED_NS
  for entry in "${OOM_PODS[@]}"; do
    oom_ns=$(echo "$entry" | cut -d'|' -f1)
    [[ -n "${CHECKED_NS[$oom_ns]+_}" ]] && continue
    CHECKED_NS[$oom_ns]=1

    hpa_count=$(kubectl get hpa -n "$oom_ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$hpa_count" -eq 0 ]]; then
      echo -e "  ${YELLOW}[INFO] ${oom_ns}: HPA 없음 — 수동 스케일링만 가능한 상태${RESET}"
      continue
    fi

    while IFS= read -r issue; do
      [[ -z "$issue" ]] && continue
      echo -e "  ${RED}[ISSUE] ${oom_ns}: ${issue}${RESET}"
      FOUND_ISSUE=true
    done < <(check_hpa_in_ns "$oom_ns")

    if [[ -z "$(check_hpa_in_ns "$oom_ns")" ]]; then
      echo -e "  ${GREEN}[OK] ${oom_ns}: HPA 정상 동작 중${RESET}"
    fi
  done
else
  echo -e "  ${GREEN}[SKIP] OOMKilled 파드 없으므로 HPA 검사 생략${RESET}"
fi
echo ""

# 최종 요약 
echo -e "${BOLD}${CYAN}================================================================${RESET}"
if $FOUND_ISSUE; then
  echo -e "${BOLD}${RED}  [RESULT] 복합 장애 감지됨 — 즉시 확인 필요${RESET}"
  echo ""
  echo -e "  권장 조치:"
  echo -e "    1) kubectl describe hpa <name> -n <ns> — conditions 상세 확인"
  echo -e "    2) kubectl top pod -n <ns>             — 실시간 메모리 확인"
  echo -e "    3) kubectl logs -n kube-system <metrics-server-pod>"
  echo -e "    4) 해당 Deployment resources.limits.memory 조정 검토"
else
  echo -e "${BOLD}${GREEN}  [RESULT] 이상 없음 — OOMKilled 반복 및 HPA 문제 미감지${RESET}"
fi
echo -e "${BOLD}${CYAN}================================================================${RESET}"
echo ""
