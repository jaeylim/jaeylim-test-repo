## TSC (Trouble Shooting Checker) 스크립트
Kubernetes 운영 환경에서 발생하는 장애를 사전에 탐지하는 쉘 스크립트 기반 진단 도구입니다.

- 실험 환경: NKS(Naver Kubernetes Service)
- 버전: v1.32.6
---
### 목적
운영 환경에는 기본적인 알람이 설정되어 있지만, 다음과 같은 유형의 장애는 단일 메트릭 기반 알람으로 탐지하기 어렵다고 판단하여 본 스크립트를 작성하였습니다.

- 두 가지 이상의 조건이 동시에 충족될 때 발생하는 복합 장애 
ex> OOMKilled 반복 + HPA 미작동 복합 장애
- 파드가 `Running` 상태임에도 내부에서 실패하는 런타임 장애
- `kubectl get` 조회로는 원인이 보이지 않는 딥한 설정 오류

이런 시나리오들을 쉘 스크립트로 진단 가능하게 제공합니다.
---
### 전제 조건
- kubectl 설치 및 클러스터 접근 가능 (kubeconfig 설정)
- `get`, `list` on pods, pvc, sa, rolebinding, hpa 등 권한있어야 함.
- python3는 JSON 파싱 용도로 필요
---
### 프로젝트 구조
```
tsc/
├── README.md
├── 40-oomkilled-hpa.sh      # OOMKilled 반복 + HPA 미작동 복합 장애
├── 41-pvc-storageclass.sh   # PVC Pending + StorageClass 불일치
└── 42-rbac-sa.sh            # RBAC 권한 누락 / ServiceAccount 오설정
```
---
### 기본 시나리오와의 분리 기준
- 40: OOMKilled 반복 + HPA 미작동 복합
- 41: PVC Pending 원인 분류 + SC 불일치
- 42: RBAC 런타임 403 + SA 오설정
---
### 시나리오 상세

#### Scenario 1 — OOMKilled 반복 + HPA 미작동 복합 장애
OOMKilled 1회 발생은 기본 알람으로 잡힐 수 있지만, 아래 조건이 동시에 성립하면 알람 없이 서비스가 지속적으로 재시작될 수 있습니다.

- 특정 파드가 단시간 내 OOMKilled로 `N`회 이상 재시작
- HPA가 존재하지만 스케일 아웃을 못 하고 있음 (metrics-server 장애, maxReplicas 도달 등)

[탐지 항목]
1. `restartCount` 임계 초과 + `lastState.reason=OOMKilled` → 반복 OOM 파드 탐지
2. `metrics-server` pod Running 여부 → HPA 메트릭 수집 가능 여부
3. HPA `ScalingActive` condition 확인 → `FailedGetScale` 등 조건 탐지
4. HPA `currentReplicas >= maxReplicas` → 스케일 아웃 여지 없음 탐지

[실행 예시]
```bash
# 전체 네임스페이스, 재시작 3회 이상
./40-oomkilled-hpa.sh

# 특정 네임스페이스, 임계 5회
./40-oomkilled-hpa.sh --namespace production --threshold 5
```

[권장 후속 조치]
```bash
kubectl describe hpa <hpa-name> -n <namespace>
kubectl top pod -n <namespace>
kubectl logs -n kube-system <metrics-server-pod>
```
---

#### Scenario 2 — PVC Pending + StorageClass 불일치 / Node Topology 충돌
PVC `Pending` 상태는 기본 탐지 가능하지만, Pending의 원인은 Events 로그를 파싱해야만 알 수 있습니다. 
원인에 따라 조치 방법이 다르기 때문에 필요한 시나리오라고 생각이 되었습니다.

[탐지 원인 분류]
1. `NO_PROVISIONER`: StorageClass에 명시된 provisioner pod/CSIDriver 미존재 → SC 생성은 됐지만 실제 드라이버 미설치
2. `WAIT_FIRST_CONSUMER`: 바인딩 모드가 `WaitForFirstConsumer`인데 파드가 스케줄 안 됨 → PVC만 있고 파드가 Pending
3. `TOPOLOGY_MISMATCH`: SC `allowedTopologies` zone과 실제 노드 zone 불일치 → 멀티존 클러스터에서 자주 발생
4. `RESOURCE_QUOTA`: ResourceQuota 초과로 PVC 생성 차단 → 네임스페이스 스토리지 quota 부족

(+) 추가로 `Released` / `Failed` 상태의 잔존 PV도 함께 탐지합니다.

[실행 예시]
```bash
# 전체 네임스페이스, 5분 이상 Pending PVC 탐지 (기본)
./41-pvc-storageclass.sh

# 특정 네임스페이스, 2분 이상 Pending
./41-pvc-storageclass.sh --namespace staging --age-minutes 2
```

[권장 후속 조치]
```bash
kubectl describe pvc <pvc-name> -n <namespace>     # Events 섹션 확인
kubectl get csidriver                               # CSI 드라이버 등록 확인
kubectl get nodes --show-labels | grep zone        # 노드 zone 레이블 확인
kubectl describe storageclass <sc-name>            # volumeBindingMode 확인
```
---

#### Scenario 3 — RBAC 권한 누락 / ServiceAccount(SA) 오설정 런타임 장애
이미지 Pull도 성공하고, 파드도 `Running`인데 k8s API를 호출하는 순간 4XX이 발생할 수 있습니다. 
이 장애는 파드 이벤트에는 나타나지 않으며, 앱 로그를 직접 확인하거나 RBAC 설정을 분석해야 발견될 수 있습니다.

** Operator 패턴, Argo Workflows, Flux, 커스텀 컨트롤러를 사용하는 환경에서 특히 자주 발생한다고 합니다.

[탐지 항목]
1. `automountServiceAccountToken: false`: SA 토큰 미마운트 + Running 파드 교차 확인
2. SA에 RoleBinding/ClusterRoleBinding 없음: 바인딩 누락으로 권한 0인 SA 탐지
3. `ClusterRole` → namespace-scoped `RoleBinding`: cluster-scoped 리소스 접근 제한 가능성 경고
4. `kubectl auth can-i` 주요 verb 검증: get/list/watch on pods/services/configmaps
5. 파드 로그 RBAC 에러 패턴 탐지: `403`, `Forbidden`, `RBAC` 키워드 (옵션)
6. `default` SA 사용 파드 경고: 전용 SA 미설정 상태 권고

[실행 예시]
```bash
# 기본 실행 (로그 검사 제외)
./42-rbac-sa.sh

# 특정 네임스페이스 + 파드 로그까지 검사
./42-rbac-sa.sh --namespace production --check-logs

# default SA 경고 제외
./42-rbac-sa.sh --namespace production --skip-default-sa
```

[권장 후속 조치]
```bash
# SA 권한 직접 검증
kubectl auth can-i get pods \
  --as=system:serviceaccount:<namespace>:<sa-name> -n <namespace>

kubectl describe rolebinding -n <namespace>
kubectl describe clusterrolebinding | grep -A5 <sa-name>
kubectl get sa <sa-name> -n <namespace> -o yaml
kubectl logs <pod-name> -n <namespace> | grep -i '403\|forbidden\|RBAC'
```
---
#### 실행 권한 설정
```bash
chmod +x 40-oomkilled-hpa.sh
chmod +x 41-pvc-storageclass.sh
chmod +x 42-rbac-sa.sh
```
---
#### CronJob으로 주기적 실행 (선택)
클러스터 내에서 CronJob으로 돌리려면, 스크립트를 ConfigMap으로 마운트하거나 컨테이너 이미지에 포함해 다음과 같이 구성할 수 있습니다.
```
[yaml]
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: tsc-checker
  namespace: monitoring
spec:
  schedule: "*/10 * * * *"    # 10분마다
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: tsc-sa    # 충분한 read 권한 필요
          containers:
          - name: tsc
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - /scripts/40-oomkilled-hpa.sh
            volumeMounts:
            - name: scripts
              mountPath: /scripts
          restartPolicy: OnFailure
          volumes:
          - name: scripts
            configMap:
              name: tsc-scripts
```              
---
#### 출력 예시

```
================================================================
  TSC Scenario 1: OOMKilled 반복 + HPA 미작동 탐지
================================================================
  검사 범위  : --all-namespaces
  재시작 임계: 3회 이상
  실행 시각  : 2025-10-01 14:23:01

[STEP 1] metrics-server 상태 확인
  [WARNING] metrics-server 상태: CrashLoopBackOff
    → HPA 메트릭 수집 불가 가능성 있음

[STEP 2] OOMKilled 반복 파드 탐지 (threshold: 3회)
  [DETECTED] production/api-server-7d9f8 — 컨테이너: app
            재시작: 5회 / 마지막 종료 이유: OOMKilled
            메모리 limit: 256Mi

[STEP 3] HPA 스케일 아웃 불가 조건 교차 확인
  [ISSUE] production: HPA[api-server-hpa] ScalingActive=false — 메트릭 수집 실패 의심

================================================================
  [RESULT] 복합 장애 감지됨 — 즉시 확인 필요
================================================================
```
---
#### 라이선스
내부 프로젝트 / 팀 내 사용 목적으로 작성되었습니다.
