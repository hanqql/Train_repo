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
네트워크(VPC), 쿠버네티스 클러스터(EKS), 데이터베이스(Aurora, Redis)를 AWS에 올립니다.

* **위치**: `environments/prod`
* **사전 조건**: Route53에 `team-train.cloud` 호스팅 존이 등록되어 있어야 합니다 (ACM 인증서 발급용).
* **명령어**:
  ```bash
  cd environments/prod
  terraform init
  terraform apply
  ```
  *(alias를 등록해두셨다면 `tfp` 같은 단축 명령을 대신 써도 됩니다)*
* **결과**: VPC, EKS 클러스터(`team-train-prod-eks`), S3 버킷, CloudFront, Aurora DB, Redis 등이 생성됩니다.

---

## ☸️ 2단계: 쿠버네티스 핵심 애드온 배포 (Terraform)
EKS 클러스터 내부를 관리할 도구(ArgoCD, ALB 컨트롤러 등)를 설치합니다.

* **위치**: `environments/prod-k8s`
* **사전 조건**: 1단계가 완전히 끝난 직후 진행합니다.
* **명령어**:
  ```bash
  cd ../prod-k8s
  terraform init
  terraform apply
  ```
* **결과**: `ArgoCD`, `AWS Load Balancer Controller` 등이 클러스터 내부에 설치됩니다.

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
| `VITE_API_URL` | 임시로 `http://localhost:8080` (4단계 완료 후 ALB 주소로 업데이트) |

---

## 🚀 3단계: ArgoCD Application 등록
2단계에서 설치된 ArgoCD가 어떤 매니페스트를 감시할지 알려줍니다.

* **위치**: 레포 루트의 `argocd-app.yaml`
* **명령어**:
  ```bash
  kubectl apply -f argocd-app.yaml
  ```
* **결과**: ArgoCD가 `modules/infra/k8s-manifests/overlays/dev`를 감시하기 시작하고, 이후 해당 경로에
  변경이 생기면 자동으로 동기화합니다.
* **주의**: 현재 `argocd-app.yaml`은 `overlays/dev`만 가리킵니다. prod에 배포하려면
  `path: modules/infra/k8s-manifests/overlays/prod`로 바꾼 별도 Application 매니페스트가 필요합니다 —
  아직 레포에 없으니 prod 배포 전에 추가해주세요.

---

## 💻 4단계: (선택) 프론트엔드/백엔드 소스코드 CI/CD
인프라 세팅은 끝났습니다. 이제 백엔드나 프론트엔드 레포지토리에서 코드를 짜고 `main` 브랜치에 푸시하면 됩니다.

* **백엔드**: GitHub Actions가 코드를 빌드해 `team-train-prod-backend` ECR에 올리고, ArgoCD가 변경을 감지해 새 파드로 교체합니다.
* **프론트엔드**: GitHub Actions가 React 코드를 빌드해 프론트엔드 S3 버킷에 업로드하고 CloudFront 캐시를 무효화합니다.

> [!TIP]
> **요약**: 처음 한 번만 **[ 1단계(`prod`) apply 👉 2단계(`prod-k8s`) apply 👉 3단계(`argocd-app.yaml` 적용) ]**
> 순서로 실행하면, 이후부터는 GitHub 푸시만으로 배포가 자동으로 돌아갑니다.

---

## 🛠️ 협업 워크플로우

- `main`: 배포 기준 브랜치
- `dev`: 개발·테스트용 브랜치

### 평소 작업

```bash
# 1. 작업 시작 전 최신 변경사항 반영
git pull origin main

# 2. 작업 후 커밋 — 형식: 이름(영문): 작업 내용
git add .
git commit -m "hjin: 인프라 기초 작업 완료"

# 3. 푸시 후 팀 톡방에 알림
git push origin main
```

### 새 브랜치가 필요할 때

```bash
# dev 브랜치 생성과 동시에 이동
git checkout -b dev

# 작업 후 커밋
git add .
git commit -m "feat: dev 브랜치 생성 및 파일 추가"

# 원격에 dev 브랜치 새로 push
git push -u origin dev

# main으로 복귀
git checkout main
```
