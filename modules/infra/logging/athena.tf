# ==============================================================================
# AWS Athena & Glue Crawler 연동 (CloudTrail 로그 분석)
# ==============================================================================

# 1. Athena 쿼리 결과 저장용 S3 버킷
resource "aws_s3_bucket" "athena_results" {
  count         = var.create_s3_buckets ? 1 : 0
  bucket        = "${var.project_name}-${var.environment}-athena-results"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-athena-results"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  count  = var.create_s3_buckets ? 1 : 0
  bucket = aws_s3_bucket.athena_results[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. Athena 데이터베이스 생성 (카탈로그)
resource "aws_athena_database" "logs_db" {
  count         = var.create_s3_buckets ? 1 : 0
  name          = "${replace(var.project_name, "-", "_")}_${replace(var.environment, "-", "_")}_logs_db"
  bucket        = aws_s3_bucket.athena_results[0].bucket
  force_destroy = true
}

# 3. Athena 워크그룹 생성
resource "aws_athena_workgroup" "logs_workgroup" {
  count = var.create_s3_buckets ? 1 : 0
  name  = "${var.project_name}-${var.environment}-logs-workgroup"

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results[0].bucket}/"
    }
  }
  force_destroy = true
}

# =========================================================================
# 4. CloudTrail 로그 Athena 테이블 (Glue Crawler 없이 파티션 프로젝션으로 관리)
#
# CloudTrail 로그는 스키마가 고정돼있어서 크롤러로 "추론"할 필요가 없음.
# 크롤러 대신 CloudTrail 콘솔의 "Create Athena table" 기능과 동일한 방식으로
# 컬럼을 직접 정의하고, 파티션은 projection으로 자동 계산되게 해서
# MSCK REPAIR TABLE / 크롤러 스케줄 실행 없이도 항상 최신 파티션이 조회됨
# =========================================================================
data "aws_caller_identity" "current" {
  count = var.create_s3_buckets && var.cloudtrail_bucket_name != "" ? 1 : 0
}

resource "aws_glue_catalog_table" "cloudtrail_logs" {
  count         = var.create_s3_buckets && var.cloudtrail_bucket_name != "" ? 1 : 0
  name          = "cloudtrail_logs"
  database_name = aws_athena_database.logs_db[0].name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"                = "cloudtrail"
    "projection.enabled"            = "true"
    "projection.region.type"        = "enum"
    "projection.region.values"      = "ap-northeast-2,us-east-1"
    "projection.date.type"          = "date"
    "projection.date.range"         = "2024/01/01,NOW"
    "projection.date.format"        = "yyyy/MM/dd"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${var.cloudtrail_bucket_name}/AWSLogs/${data.aws_caller_identity.current[0].account_id}/CloudTrail/$${region}/$${date}"
  }

  partition_keys {
    name = "region"
    type = "string"
  }
  partition_keys {
    name = "date"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${var.cloudtrail_bucket_name}/AWSLogs/${data.aws_caller_identity.current[0].account_id}/CloudTrail/"
    input_format  = "com.amazon.emr.cloudtrail.CloudTrailInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "cloudtrail-serde"
      serialization_library = "com.amazon.emr.hive.serde.CloudTrailSerde"
    }

    columns {
      name = "eventversion"
      type = "string"
    }
    columns {
      name = "useridentity"
      type = "struct<type:string,principalid:string,arn:string,accountid:string,invokedby:string,accesskeyid:string,username:string,sessioncontext:struct<attributes:struct<mfaauthenticated:string,creationdate:string>,sessionissuer:struct<type:string,principalid:string,arn:string,accountid:string,username:string>>>"
    }
    columns {
      name = "eventtime"
      type = "string"
    }
    columns {
      name = "eventsource"
      type = "string"
    }
    columns {
      name = "eventname"
      type = "string"
    }
    columns {
      name = "awsregion"
      type = "string"
    }
    columns {
      name = "sourceipaddress"
      type = "string"
    }
    columns {
      name = "useragent"
      type = "string"
    }
    columns {
      name = "errorcode"
      type = "string"
    }
    columns {
      name = "errormessage"
      type = "string"
    }
    columns {
      name = "requestparameters"
      type = "string"
    }
    columns {
      name = "responseelements"
      type = "string"
    }
    columns {
      name = "additionaleventdata"
      type = "string"
    }
    columns {
      name = "requestid"
      type = "string"
    }
    columns {
      name = "eventid"
      type = "string"
    }
    columns {
      name = "resources"
      type = "array<struct<arn:string,accountid:string,type:string>>"
    }
    columns {
      name = "eventtype"
      type = "string"
    }
    columns {
      name = "apiversion"
      type = "string"
    }
    columns {
      name = "readonly"
      type = "string"
    }
    columns {
      name = "recipientaccountid"
      type = "string"
    }
    columns {
      name = "vpcendpointid"
      type = "string"
    }
  }
}
