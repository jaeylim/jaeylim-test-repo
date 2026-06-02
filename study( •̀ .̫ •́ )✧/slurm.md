#### Slurm (Simple Linux Utility for Resource Management), Slurm Workload Manager
###### KEY WORDS: Backfill, Partition

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

##### sbatch (스크립트)
실제로 job을 어떻게 제출하는지.
EX> sbatch job.sh
```
#!/bin/bash
#SBATCH --job-name=myjob      # job 이름 (squeue에서 보임)
#SBATCH --partition=gpu        # 어떤 파티션에서 실행할지
#SBATCH --nodes=1              # 노드 몇 대 쓸지
#SBATCH --ntasks=1             # 태스크 몇 개 (프로세스 수)
#SBATCH --cpus-per-task=4      # 태스크당 CPU 코어 수
#SBATCH --gres=gpu:1           # GPU 몇 개
#SBATCH --mem=16G              # 메모리
#SBATCH --time=02:00:00        # 최대 실행시간 (초과하면 강제종료)
#SBATCH --output=log_%j.out    # 표준출력 저장 파일 (%j = job ID)
#SBATCH --error=err_%j.err     # 에러출력 저장 파일

python train.py                # 실제 실행할 명령어
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

##### slurm test
[순서]: 공통 설정 → Control 설정 → Worker 설정 → 연결 확인

[공통 설정]
1. hosts 파일 설정
```
sudo tee -a /etc/hosts << 'EOF'
175.45.204.12 jaeyeon-control
101.79.17.249 jaeyeon-worker
EOF
```
2. 패키지 업데이트 + slurm 설치
```
sudo apt update && sudo apt install -y slurmd slurm-client munge
```
3. MUNGE 키 생성 (control)
###### 키가 같아야만 통신 허용
```
sudo create-munge-key
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key

# worker에 같은 키 복사
sudo scp -i ./jaeyeon-key.pem /etc/munge/munge.key root@101.79.17.249:/etc/munge/munge.key
# (worker)
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key
```
4. 두 서버 모두 munge 시작
```
sudo systemctl enable munge
sudo systemctl start munge
sudo systemctl status munge
```

[Control]
1. slurm.conf 설정
```
sudo tee /etc/slurm/slurm.conf << 'EOF'
ClusterName=jaeyeon-cluster
SlurmctldHost=jaeyeon-control
MpiDefault=none
ProctrackType=proctrack/linuxproc
ReturnToService=2
SlurmctldPidFile=/var/run/slurmctld.pid
SlurmdPidFile=/var/run/slurmd.pid
SlurmdSpoolDir=/var/spool/slurmd
SlurmctldLogFile=/var/log/slurmctld.log
SlurmdLogFile=/var/log/slurmd.log
StateSaveLocation=/var/spool/slurmctld

SchedulerType=sched/backfill
SelectType=select/cons_tres

AccountingStorageType=accounting_storage/none
JobAcctGatherType=jobacct_gather/none

NodeName=jaeyeon-worker CPUs=2 RealMemory=3800 State=UNKNOWN
PartitionName=debug Nodes=jaeyeon-worker Default=YES MaxTime=INFINITE State=UP
EOF
```
2. worker에도 복사
```
sudo scp -i ./jaeyeon-key.pem /etc/slurm/slurm.conf root@101.79.17.249:/etc/slurm/slurm.conf
```

[Slurm]
1. (control)
```
sudo systemctl enable slurmctld
sudo systemctl start slurmctld
sudo systemctl status slurmctld
```
2. (worker)
```
sudo systemctl enable slurmd
sudo systemctl start slurmd
sudo systemctl status slurmd
```


##### References
▸ https://supercomputing.tue.nl/documentation/steps/jobs/