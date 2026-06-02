#### Slurm (Simple Linux Utility for Resource Management), Slurm Workload Manager
#### KEY WORDS: Backfill, Partition

→ 여러 컴퓨터(노드)를 묶어서 작업을 공정하게 분배해주는 스케줄러.

##### 핵심역할
| 역할 | 설명 |
|---|---|
| `Resource Manager` | 어떤 노드에 CPU/Mem/GPU가 얼마나 남았는지 추적 | 
| `Job Scheduler` | 제출된 작업을 우선순위에 따라 스케줄링 | 
| `Job Executor` | 실제 작업을 노드에서 실행시킴 | 

##### 구성요소
```
[사용자] → sbatch 제출
              ↓
         [slurmctld]  ← 마스터 데몬 (Control Node)
              ↓
         [slurmd]     ← 데몬 (Worker Node)
              ↓
         [실제 작업 실행]
```

##### Kubernetes와 차이점
🗒️ Kube와 차이점은 작업 단위 `Kubernetes (Pod), Slurm(Job)`외에도 다음과 같다.

|  | Kubernetes | SLURM |
|---|---|---|
| 대상 | 컨테이너 기반 서비스/앱 | 배치 작업 (HPC, ML 학습 등) | 
| 실행 방식 | 서비스가 계속 떠 있음 | 작업 실행 후 종료 (batch job) |
| 스케줄링 기준 | 리소스 요청량 + 가용노드 | 큐, 우선순위, 파티션 | 
| 용도 | 웹 서비스, 마이크로서비스 | 슈퍼컴퓨터, AI 학습, 시뮬레이션 | 

```
SLURM  →  GPU 학습 job 스케줄링
Kubernetes  →  학습 완료된 모델 서빙
```

##### 파티션
클러스터의 노드들을 목적에 따라 그룹으로 나눔.
```
전체 클러스터 노드 100개
├── gpu 파티션      → GPU 달린 노드 20개, AI 학습용
├── cpu 파티션      → CPU만 있는 노드 60개, 일반 계산용
├── debug 파티션    → 노드 5개, 짧은 테스트용
└── long 파티션     → 노드 15개, 장기 실행 job용
```

##### References
▸ https://supercomputing.tue.nl/documentation/steps/jobs/