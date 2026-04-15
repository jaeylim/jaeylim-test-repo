### Date: 2026-04-15 (wed.)
### Contents: Create HPA on Kubernetes environment.

### (optional) install metrics-server
```
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 인증서 검증이 까다로운 환경은 아래 패치 추가
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```
### step1. 테스트용 Deployment 생성
```
# tsc-test-deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tsc-test-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tsc-test
  template:
    metadata:
      labels:
        app: tsc-test
    spec:
      containers:
      - name: app
        image: polinux/stress          # CPU/Memory 부하 생성 전용 이미지
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"           # 타이트하게 설정 → OOMKill 유도용
        command: ["stress"]
        args: ["--vm", "1", "--vm-bytes", "50M", "--cpu", "1"]
        # 처음엔 부하 없이 시작, 나중에 args 변경으로 OOM 유도


kubectl apply -f tsc-test-deploy.yaml
kubectl get pods -w  # Running 확인
---
NAME                            READY   STATUS    RESTARTS   AGE
tsc-test-app-849bb9666b-8rzdl   1/1     Running   0          34s
---
```

### step2. HPA 생성
```
# tsc-test-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: tsc-test-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tsc-test-app
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 30        # 낮게 설정 → 부하 시 빠르게 스케일
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 60

kubectl apply -f tsc-test-hpa.yaml
kubectl get hpa tsc-test-hpa -w     # TARGETS 컬럼 확인

NAME           REFERENCE                 TARGETS                                     MINPODS   MAXPODS   REPLICAS   AGE
tsc-test-hpa   Deployment/tsc-test-app   cpu: <unknown>/30%, memory: <unknown>/60%   1         3         0          15s
tsc-test-hpa   Deployment/tsc-test-app   cpu: 200%/30%, memory: 66%/60%              1         3         1          16s
```

### step3. OOMKilled 반복
```
kubectl set env deployment/tsc-test-app -n default\
  STRESS_OPTS="--vm 1 --vm-bytes 200M"   # 128Mi limit 초과 → OOMKilled 유도

# 또는 직접 patch
kubectl patch deployment tsc-test-app -n default --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/args",
   "value":["--vm","1","--vm-bytes","200M","--cpu","1"]}
]'

# 파드 재생성 확인
kubectl get pods -n default -l app=tsc-test -w

# OOMKilled 발생 확인 (2~3분 소요)
kubectl describe pods -n default -l app=tsc-test | grep -E "OOMKilled|Restart Count"

# 다시 메모리 부하 원복
kubectl patch deployment tsc-test-app -n default --type=json -p='[
  {"op":"replace",
   "path":"/spec/template/spec/containers/0/args",
   "value":["--vm","1","--vm-bytes","50M","--cpu","1"]}
]'
```
