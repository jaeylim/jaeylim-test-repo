1. zammad-railsserver — 진짜 핵심, 애플리케이션 두뇌

Ruby on Rails로 만들어진 웹 애플리케이션 서버 자체
티켓 생성/조회, 사용자 인증, API 요청 처리, 비즈니스 로직(트리거 조건 평가, Core Workflow 판단 등) 전부 여기서 처리
nginx가 8080으로 받은 요청을 내부적으로 이 컨테이너에 전달(proxy_pass)
지금까지 대화하신 Entra ID SSO, Core Workflow, Duplicate Detection 같은 로직들이 다 이 프로세스 안에서 실행돼요

2. zammad-nginx — 관문(gateway)

유일하게 8080 포트로 외부에 노출된 컨테이너
정적 파일(JS, CSS, 이미지) 서빙 + 요청을 railsserver나 websocket 컨테이너로 라우팅
SSL 종료(termination)도 보통 여기서 처리 (또는 앞단에 별도 리버스 프록시/로드밸런서가 있으면 거기서)

3. zammad-scheduler — 시간 기반 자동화 담당

railsserver와 같은 이미지지만 주기적으로 실행돼야 하는 작업들을 처리
예: 트리거 조건 재평가, 예약 발송 메일, 통계 집계, 세션 만료 정리, SLA 타이머 체크
cron이랑 비슷한 역할인데, Rails 코드 안에서 스케줄러 프로세스로 돌아가는 거예요

4. zammad-websocket — 실시간 통신 담당

에이전트 화면에서 "누가 지금 이 티켓 보고 있음", "새 티켓 도착", "다른 사람이 답변 작성 중" 같은 실시간 업데이트를 처리
HTTP 요청-응답 방식이 아니라 지속 연결(WebSocket)을 유지해야 하니까 railsserver랑 분리된 별도 프로세스로 돌아감

5. zammad-backup — 백업 스케줄러

설정된 주기(cron 유사)로 DB + 첨부파일 등을 백업 아카이브로 생성
보통 /var/lib/zammad/backup 같은 볼륨에 저장 → 이 볼륨을 외부 스토리지(S3, NCP Object Storage 등)로 별도 백업하는 게 실무 권장 (컨테이너 자체가 죽으면 백업도 같이 날아가니까)

6. zammad-postgresql — 메인 DB

티켓, 사용자, 조직, 그룹, 워크플로우 설정 등 거의 모든 구조화된 데이터 저장
지금 버전 postgres:17.10

7. zammad-elasticsearch — 검색엔진

티켓 풀텍스트 검색, 첨부파일 내용 검색(OCR/파싱된 텍스트 포함)
railsserver가 티켓 생성/수정 시 ES에 색인(index)을 갱신 → 검색 요청은 PostgreSQL이 아니라 ES가 처리
이게 없으면 Zammad 검색창 자체가 아예 동작 안 함 (필수 컴포넌트)

8. zammad-redis — 세션/실시간 데이터 캐시

WebSocket 연결 상태, 세션 정보, 백그라운드 작업 큐(Job queue) 관리
scheduler/websocket 프로세스들이 서로 상태를 공유해야 할 때 여기 거쳐감

9. zammad-memcached — 애플리케이션 레벨 캐시

Rails 애플리케이션 자체의 쿼리 결과, 세션 일부, 자주 조회되는 데이터를 메모리에 캐싱
Redis랑 역할이 겹쳐 보일 수 있는데, Redis는 "실시간/큐" 쪽, Memcached는 "단순 key-value 캐시" 쪽으로 성격이 달라요


사용자 요청 → nginx → railsserver (핵심 로직) 
                          ├─ postgresql (데이터 저장)
                          ├─ elasticsearch (검색)
                          ├─ redis (세션/큐)
                          └─ memcached (캐시)

백그라운드: scheduler (주기 작업), websocket (실시간), backup (백업)
---
#### Docker Compose
###### KEY WORDS: Service, Volume, Network, Healthcheck

→ 하나의 yml 파일로 여러 컨테이너를 정의하고, 하나의 "프로젝트" 단위로 묶어서 관리하는 도구.

##### 핵심역할
| 역할 | 설명 |
|---|---|
| `Multi-container 정의` | 여러 컨테이너를 하나의 docker-compose.yml로 선언적 관리 |
| `프로젝트 단위 관리` | 컨테이너 여러 개를 "하나의 앱"으로 묶어서 이름 부여 (예: zammad-docker-compose) |
| `네트워크/볼륨 자동 구성` | 서비스 간 통신, 데이터 영속성 자동 설정 |
| `의존성 순서 관리` | depends_on으로 시작 순서만 제어 (K8s처럼 상태 기반 대기는 아님) |

##### Kubernetes와 차이점
🗒️ Kube와 차이점은 대상 범위 `Kubernetes (멀티 노드 클러스터), Compose(단일 호스트)`외에도 다음과 같다.

| | Docker Compose | Kubernetes |
|---|---|---|
| 대상 | 단일 호스트 | 멀티 노드 클러스터 |
| 오토스케일링 | ✗ (수동 --scale) | HPA 자동 |
| 자가 치유 | restart policy 수준 | liveness/readiness probe + kubelet |
| 서비스 디스커버리 | 내장 DNS (서비스명으로 resolve) | CoreDNS + Service |
| 헬스체크 | healthcheck 정의 시 (healthy) 표시 | livenessProbe/readinessProbe |
| 포트 노출 | ports로 직접 호스트 바인딩 | Service/Ingress로 추상화 |

Docker Compose  →  단일 서버에서 여러 컨테이너 빠르게 묶어 실행
Kubernetes      →  여러 노드에 걸쳐 자동 복구·확장까지 관리

##### 실습: zammad-docker-compose 구조 (zammad-test 서버)
프로젝트명: `zammad-docker-compose`
설정 파일: `/root/zammad-docker-compose/docker-compose.yml`
상태: running (9개 컨테이너)

사용자 요청 → nginx → railsserver (핵심 로직)
├─ postgresql (데이터 저장)
├─ elasticsearch (검색)
├─ redis (세션/큐)
└─ memcached (캐시)
백그라운드: scheduler (주기 작업), websocket (실시간), backup (백업)

| 컨테이너 | 이미지 | 역할 | 포트 노출 |
|---|---|---|---|
| zammad-nginx | ghcr.io/zammad/zammad:7.0.1 | 관문(gateway), 정적파일 서빙, railsserver로 라우팅 | 0.0.0.0:8080→8080 (유일한 외부 노출) |
| zammad-railsserver | ghcr.io/zammad/zammad:7.0.1 | 핵심 애플리케이션 서버 (인증, 티켓 로직, Core Workflow 평가 등) | 미노출 (내부 전용) |
| zammad-scheduler | ghcr.io/zammad/zammad:7.0.1 | 주기적 작업 (트리거 재평가, 예약메일, SLA 타이머) | 미노출 |
| zammad-websocket | ghcr.io/zammad/zammad:7.0.1 | 실시간 업데이트 (신규 티켓 알림, 동시 편집 표시) | 미노출 |
| zammad-backup | ghcr.io/zammad/zammad:7.0.1 | 주기적 DB+첨부파일 백업 아카이브 생성 | 미노출 |
| zammad-postgresql | postgres:17.10-alpine | 메인 DB (티켓/유저/그룹/워크플로우 설정 등) | 5432 (내부 전용) |
| zammad-elasticsearch | elasticsearch:9.4.2 | 티켓 풀텍스트 검색/색인 (없으면 검색 기능 자체가 동작 안함) | 9200, 9300 (내부 전용) |
| zammad-redis | redis:8.8.0-alpine | 세션 상태, 백그라운드 작업 큐 관리 | 6379 (내부 전용) |
| zammad-memcached | memcached:1.6.42-alpine | 애플리케이션 레벨 쿼리/세션 캐시 | 11211 (내부 전용) |

**포인트**: nginx, railsserver, scheduler, websocket, backup은 전부 **같은 이미지**(ghcr.io/zammad/zammad)를 쓰지만, docker-compose.yml에서 각기 다른 `command`로 역할을 나눠 실행함 → 완전히 분리된 MSA가 아니라 "모놀리식 코드베이스를 프로세스 역할별로 분리 실행"하는 구조.

##### 실습 로그
- `docker ps` 확인 결과 (healthy) 상태 표시된 컨테이너: railsserver, memcached, postgresql, redis → compose 파일에 healthcheck 정의됨
- elasticsearch, nginx, scheduler, websocket, backup은 healthcheck 미정의 → Up 상태만 표시, 정상 동작 여부는 로그로 별도 확인 필요
- 외부에 열린 포트는 nginx의 8080 하나뿐 → DB/캐시/검색엔진은 내부 네트워크에서만 통신, 외부 직접 노출 없음 (보안 관점에서 정상 구조)
- `docker compose ls`로 프로젝트 단위 확인, `docker ps`로 개별 컨테이너 상태 확인 → 두 명령어의 관찰 단위가 다름 (프로젝트 vs 컨테이너)

##### References
▸ https://docs.docker.com/reference/compose-file/
▸ https://github.com/zammad/zammad-docker-compose