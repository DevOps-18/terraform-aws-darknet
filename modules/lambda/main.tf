data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  source_dir  = "${path.module}/src/"
  output_path = "${path.module}/build/lambda.zip"

  log_group            = "/aws/lambda/${var.name}"
  log_retention_period = 90

  timeout = 900
}

resource "aws_cloudwatch_log_group" "main" {
  name              = "${local.log_group}"
  retention_in_days = "${local.log_retention_period}"
}

resource "aws_iam_role" "main" {
  name = "${var.role_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "main_policy" {
  name = "policy"
  role = "${aws_iam_role.main.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group}:*:*",
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group}"
      ]
    }
  ]
}
EOF
}

data "archive_file" "main" {
  type        = "zip"
  source_dir  = "${local.source_dir}"
  output_path = "${local.output_path}"
}

resource "aws_lambda_function" "main" {
  function_name    = "${var.name}"
  handler          = "index.handler"
  runtime          = "nodejs8.10"
  filename         = "${local.output_path}"
  source_code_hash = "${data.archive_file.main.output_base64sha256}"
  role             = "${aws_iam_role.main.arn}"
  timeout          = "${local.timeout}"

  environment {
    variables = {
      NOTIFICATION_MESSAGE   = "${var.notification_message}"
      SLACK_NOTIFICATION_URL = "${var.slack_notification_url}"
    }
  }
}

resource "aws_lambda_permission" "main" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.main.arn}"
  principal     = "logs.${data.aws_region.current.name}.amazonaws.com"
  source_arn    = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.log_group_name}:*"

  depends_on = ["aws_lambda_function.main"]
}

resource "aws_cloudwatch_log_subscription_filter" "main" {
  name            = "${var.name}_filter2"
  log_group_name  = "${var.log_group_name}"
  filter_pattern  = ""
  destination_arn = "${aws_lambda_function.main.arn}"

  depends_on = ["aws_lambda_permission.main"]
}
