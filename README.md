> **Fork 안내** — 이 레포는 4인 팀 프로젝트([원본](https://github.com/hjin-2e/Train_repo))의 fork입니다.
> `main` 브랜치의 [`4d627e6`](https://github.com/hanqql/Train_repo/commit/4d627e6) 커밋부터는
> 팀 내 네트워크/보안 담당 개인 작업입니다 — Route53 Failover IaC화, CloudFront 커스텀 헤더 +
> ALB 리스너 규칙 기반 오리진 검증, EKS 최소 권한 Access Entry, CloudTrail 보안 이벤트 실시간
> 감시, Azure Site-to-Site VPN DR 연동. 설계 배경은 [`docs/adr/0001-alb-origin-access-control.md`](docs/adr/0001-alb-origin-access-control.md),
> 검증 절차는 [`docs/runbooks/failover-test.md`](docs/runbooks/failover-test.md) 참고.
> 전체를 한 번에 보려면 [케이스 스터디](https://claude.ai/code/artifact/f5603810-42e9-4489-bd20-cde1aedcf3eb) 참고.
>
> 그 외(K8s 애드온, DB, 로깅/알람 등)는 팀원들의 작업입니다.

## 🏗️ 1단계: AWS 뼈대 인프라 배포 (Terraform)
가장 먼저 네트워크(VPC)와 쿠버네티스 클러스터(EKS), 그리고 데이터베이스(Aurora, Redis)를 AWS에 올립니다.

* **위치**: `environments/prod` 폴더 안에서 실행
* **사전 조건**: AWS Route53에 `team-train.cloud` 도메인이 정상적으로 등록(Hosted Zone 생성)되어 있어야 합니다. (ACM 인증서 발급을 위함)
* **명령어**:
  ```bash
  cd environments/prod
  terraform init
  terraform apply
  ```
  *(또는 고객님이 설정하신 단축어 `tfp` 등을 사용)*
* **결과**: VPC, EKS 클러스터(`team-train-prod-eks`), S3 버킷, CloudFront, Aurora DB, Redis 등이 전부 생성됩니다.

---

## ☸️ 2단계: 쿠버네티스 핵심 애드온 배포 (Terraform)
EKS 클러스터가 만들어졌으니, 클러스터 내부를 관리할 도구들(ArgoCD, ALB 컨트롤러 등)을 설치합니다.

* **위치**: `environments/prod-k8s` 폴더 안에서 실행
* **사전 조건**: 1단계가 완전히 끝난 직후 진행해야 합니다.
* **명령어**:
  ```bash
  cd ../prod-k8s
  terraform init
  terraform apply
  ```
* **결과**: 쿠버네티스 내부에 `ArgoCD`, `AWS Load Balancer Controller` 등이 자동으로 설치됩니다.
  *(이때 테라폼 코드 내부에 ArgoCD와 깃허브를 연동하는 설정이 이미 포함되어 있기 때문에, 설치가 끝나자마자 ArgoCD가 깃허브의 매니페스트를 읽어와 자동으로 파드 배포를 시작합니다!)*

`Back_Train` 레포 → Settings → Secrets and variables → Actions:

| Secret 이름 | 값 |
|-----------|---|
| `AWS_BACKEND_ROLE_ARN` | terraform output `github_actions_backend_role_arn` |
| `GITOPS_PAT` | GitHub Personal Access Token (Train_repo에 write 권한) |

`Front_Train` 레포 → Settings → Secrets and variables → Actions:

| Secret 이름 | 값 |
|-----------|---|
| `AWS_GITHUB_ACTIONS_ROLE_ARN` | terraform output `github_actions_role_arn` |
| `ARTIFACT_BUCKET` | terraform output `pipeline_artifact_bucket_name` |
| `VITE_API_URL` | 임시로 `http://localhost:8080` (Phase 4 후 ALB 주소로 업데이트) |


---

## 💻 4단계: (선택) 프론트엔드/백엔드 소스코드 CI/CD
인프라 세팅은 끝났습니다. 이제 백엔드나 프론트엔드 레포지토리에서 코드를 짜고 `main` 브랜치에 푸시(`git push`)하기만 하면 됩니다.

* **백엔드**: GitHub Actions가 코드를 빌드하여 `team-train-prod-backend` ECR에 올리고, ArgoCD가 변경을 감지하여 새 파드(Pod)로 교체합니다.
* **프론트엔드**: GitHub Actions가 React 코드를 빌드하여, 생성된 프론트엔드 S3 버킷에 정적 파일을 업로드하고 CloudFront 캐시를 무효화(Invalidation)합니다.

> [!TIP]
> **요약**: 처음에만 터미널에서 **[ 1단계(`prod`) apply 👉 2단계(`prod-k8s`) apply 👉 3단계(`argocd-app` 적용) ]** 순서대로 한 번씩 쳐 주시면, 그 이후부터는 깃허브 푸시만으로 모든 배포가 알아서 돌아갑니다!


## 🛠️ **배포 방법**
팀 프로젝트 진행 시 코드를 동기화하고 배포하는 프로세스입니다. 아래 순서를 준수해 주세요.

```bash
# 작업 시작 전, 원격 저장소의 최신 변경 사항을 먼저 반영합니다.
git pull origin main

# 작업 내용 커밋하기
# 커밋 메시지는 이름(영문): 본인이 작업한 내용 작성 형식으로 통일합니다.
git commit -m "hjin: 인프라 기초 작업 완료"

# 원격 저장소에 푸시 후 공유
git push origin main

# 푸시가 완료되면 반드시 팀 톡방에 알림을 남겨주세요!

# ✨ 브랜치 변경 후 배포해야합니다.
# 1. dev 브랜치를 만들면서 동시에 그 브랜치로 이동합니다.
git checkout -b dev

# 2. 변경된 파일들을 올릴 준비를 합니다. (점 '.'은 모든 변경된 파일을 의미합니다)
git add .

# 3. 버전 기록 메시지(커밋)를 남깁니다.
git commit -m "feat: dev 브랜치 생성 및 파일 추가"

# 4. 원격 저장소(GitHub 등)에 dev 브랜치를 새로 만들며 코드를 올립니다.
git push -u origin dev

# main으로 다시 변경하고 싶은 경우
git checkout main

```
