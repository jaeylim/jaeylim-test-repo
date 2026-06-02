#### SLURM (Simple Linux Utility for Resource Management)

→ 여러 컴퓨터(노드)를 묶어서 작업을 공정하게 분배해주는 스케줄러.

###### 핵심역할
| 역할 | 설명 |
|---|---|
| `Resource Manager` | 어떤 노드에 CPU/Mem/GPU가 얼마나 남았는지 추적 | 
| `Job Scheduler` | 제출된 작업을 우선순위에 따라 스케줄링 | 
| `Job Executor` | 실제 작업을 노드에서 실행시킴 | 

###### 구성요소
```
[사용자] → sbatch 제출
              ↓
         [slurmctld]  ← 마스터 데몬 (컨트롤 노드에서 실행)
              ↓
         [slurmd]     ← 각 워커 노드에서 실행되는 데몬
              ↓
         [실제 작업 실행]
```