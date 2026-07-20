# Runbook: api.team-train.cloud Failover 동작 검증

관련 설계: [ADR 0001](../adr/0001-alb-origin-access-control.md)

이 문서는 Route53 Failover(Primary: ALB, Secondary: Azure App Service)가 실제로
동작하는지 검증하는 절차다. 인프라가 배포되어 있는 상태에서만 실행 가능하다.
(작성 시점 기준 인프라가 내려가 있어 아래 절차는 아직 직접 실행/캡처하지 못했다 —
다음 배포 때 이 문서를 따라가며 실제로 검증하고, 각 단계 결과를 스크린샷/로그로
이 문서 하단 "실행 기록"에 남길 것.)

## 사전 확인

```bash
# 1. Primary 헬스체크가 지금 Healthy인지 확인
aws route53 get-health-check-status --health-check-id <api_primary health_check_id>

# 2. CloudWatch 알람이 OK 상태인지 확인
aws cloudwatch describe-alarms --alarm-names team-train-prod-alb-healthy-hosts

# 3. 현재 api.team-train.cloud가 ALB로 응답하는지 확인
curl -sv https://api.team-train.cloud/health
```

`get-health-check-status`가 `Success`, alarm이 `OK`, curl이 ALB 백엔드 응답을
반환하면 정상 상태다.

## 1단계 — 인위적으로 Primary를 Unhealthy로 만들기

```bash
# 백엔드 파드를 전부 0으로 스케일 (Target Group에 healthy target이 없어짐)
kubectl scale deployment train-backend --replicas=0
```

## 2단계 — 장애 전파 확인 (시간 순서대로)

```bash
# a. Target Group에 healthy target이 0인지 확인
aws elbv2 describe-target-health --target-group-arn <app_tg_arn>

# b. CloudWatch 알람이 ALARM 상태로 전환되는지 확인 (evaluation_periods=2, period=60초라
#    최대 2분 정도 걸릴 수 있음)
aws cloudwatch describe-alarms --alarm-names team-train-prod-alb-healthy-hosts

# c. Route53 헬스체크가 Failure로 바뀌는지 확인
aws route53 get-health-check-status --health-check-id <api_primary health_check_id>

# d. DNS 응답이 Azure App Service 쪽으로 바뀌는지 확인 (TTL=60초 고려해서 재시도)
dig api.team-train.cloud
```

**캡처할 증거**: (a)~(d) 각 명령의 출력, 그리고 `curl https://api.team-train.cloud/health`가
Azure App Service의 응답으로 바뀌는 순간의 로그.

## 3단계 — 정상 복구 (Failback) 확인

```bash
kubectl scale deployment train-backend --replicas=2
```

- Target Group healthy target 다시 채워짐 확인
- CloudWatch 알람 OK로 복귀 확인
- Route53 헬스체크 Success로 복귀 확인
- DNS/`curl` 응답이 다시 ALB로 돌아오는지 확인 (TTL 고려)

## 4단계 — 커스텀 헤더 검증도 같이 확인 (ADR 0001의 confused deputy 방어)

```bash
# 헤더 없이 ALB 직접 호출 -> 403 나와야 정상 (prefix list를 우회해 직접 IP로 못 붙으니
# 이 테스트는 반드시 CloudFront 뒤가 아니라 ALB에 도달 가능한 사설망/Bastion에서 실행)
curl -sv https://<alb_dns_name>/health

# CloudFront 경유 호출 -> 정상 응답 나와야 함 (CloudFront가 자동으로 시크릿 헤더를 붙여줌)
curl -sv https://team-train.cloud/api/health
```

## 실행 기록

| 일자 | 실행자 | 결과 | 비고 |
|---|---|---|---|
| (아직 실행 전) | - | - | 인프라 재배포 후 진행 예정 |
