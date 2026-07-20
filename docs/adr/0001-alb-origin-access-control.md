# ADR 0001: ALB 오리진 접근 제어 및 Failover 헬스체크 설계

- 상태: 승인됨
- 관련 리소스: `modules/networking/security_group.tf` (`aws_security_group.alb`), `modules/infra/cdn/main.tf`, `modules/infra/eks-cluster/alb.tf`, `environments/prod/main.tf` (Route53 Failover)

## 배경

`api.team-train.cloud`는 Route53 Failover 레코드로 관리된다 (Primary: ALB, Secondary: Azure App Service). ALB의 보안그룹은 CloudFront의 관리형 prefix list(`com.amazonaws.global.cloudfront.origin-facing`)로만 인바운드를 허용해서, CloudFront를 거치지 않은 트래픽은 SG 단계에서 차단된다.

이 설계에서 두 가지 문제가 동시에 발생했다.

1. **Route53 헬스체크가 ALB에 도달하지 못함.** Route53가 Primary(ALB)의 상태를 판단하려면 실제로 ALB에 요청을 보내야 하는데, Route53 헬스체커의 IP 대역은 CloudFront prefix list에 포함되지 않는다. 그 결과 헬스체크가 항상 실패해서 Failover가 오작동한다.
2. **prefix list만으로는 "내 CloudFront 배포"인지 구분이 안 됨.** CloudFront의 IP 대역(prefix list)은 AWS의 모든 CloudFront 고객이 공유한다. 즉 "CloudFront에서 왔다"는 검증은 되지만, "내 CloudFront 배포에서 왔다"는 검증이 안 된다 — 제3자가 자신의 CloudFront 배포에 우리 ALB를 커스텀 오리진으로 등록하면 그 요청도 SG를 통과한다 (confused deputy / domain fronting 유형의 허점).

## 검토한 대안

### 문제 1 (헬스체크)에 대해

| 대안 | 기각 사유 |
|---|---|
| ALB SG에 Route53 헬스체커 IP 대역을 추가 허용 | AWS가 managed prefix list로 제공하지 않음. `ip-ranges.json`에서 직접 뽑아 customer-managed prefix list로 관리해야 하는데, 대역이 주기적으로 바뀌어서 자동 갱신 파이프라인(Lambda+EventBridge 등)이 별도로 필요함 — 유지보수 비용이 큼 |
| Route53 Primary를 CloudFront 도메인으로 변경 | 이 프로젝트에서 CloudFront의 ALB 오리진 도메인이 `api.team-train.cloud` 자기 자신이라, Primary를 CloudFront로 돌리면 순환 참조가 생김 (CloudFront → api.team-train.cloud → CloudFront → …) |
| **CloudWatch 알람 기반 헬스체크 (채택)** | ALB Target Group의 `HealthyHostCount`를 CloudWatch 알람으로 만들고, Route53 헬스체크를 `type = CLOUDWATCH_METRIC`으로 설정해서 그 알람 상태만 조회하게 함. 네트워크 트래픽이 전혀 발생하지 않고 AWS 제어 영역 API로만 상태를 가져오므로 SG 규칙과 완전히 무관하게 동작함 |

### 문제 2 (confused deputy)에 대해

CloudFront origin에 시크릿 값이 담긴 커스텀 헤더(`X-Origin-Verify`)를 추가하고, ALB HTTPS 리스너의 기본 동작을 403으로 바꾼 뒤, 해당 헤더가 일치하는 요청만 리스너 규칙에서 타겟그룹으로 forward하도록 했다. prefix list는 그대로 유지한다 — 대체가 아니라 추가다.

## 결정

- **prefix list(네트워크 계층 필터링)와 커스텀 헤더(L7 검증)를 함께 사용한다.** prefix list는 무차별 스캐닝/트래픽을 SG 단계에서 값싸게 차단하고, 헤더는 "정확히 내 배포에서 왔는지"를 확인한다. 하나가 다른 하나를 대체하지 않는다.
- **Route53 Primary 헬스체크는 CloudWatch 알람 기반(`CLOUDWATCH_METRIC`)으로 한다.** SG를 열거나 순환 참조를 만들지 않고도 Failover 판단이 가능하다.
- **ALB 앞단에 Regional WAF를 추가로 둔다.** 커스텀 헤더 검증까지 뚫리는 경우를 대비한 3번째 방어선(CloudFront WAF는 CloudFront 경유 트래픽만 보므로 별개로 필요).

## 트레이드오프

- 커스텀 헤더 시크릿은 Terraform `random_password`로 자동 생성되어 CDN/ALB 양쪽에 동일하게 주입된다. 로테이션이 필요하면 해당 리소스를 `taint`해야 하며, 자동 로테이션 파이프라인은 없다 (포트폴리오 스코프에서는 수동 로테이션으로 충분하다고 판단).
- Regional WAF는 리전 하나 추가될 때마다 비용이 붙는다. `enable_alb_waf` 변수로 언제든 끌 수 있게 만들어뒀다.
- CloudWatch 알람 기반 헬스체크는 "ALB가 살아있는지"만 보고 "CloudFront에서 실제로 도달 가능한지"는 별도로 검증하지 않는다. 이 프로젝트 규모에서는 두 실패 모드가 사실상 함께 발생하므로 허용 가능한 단순화로 판단했다.
