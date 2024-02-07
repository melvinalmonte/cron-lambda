resource "null_resource" "pip_install" {
  triggers = {
    shell_hash = "${sha256(file("${path.module}/../requirements.txt"))}"
  }

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/layer/python/lib/python3.12/site-packages && python3 -m pip install -r ${path.module}/../requirements.txt -t ${path.module}/layer/python/lib/python3.12/site-packages"
  }
}

data "archive_file" "layer" {
  type        = "zip"
  source_dir  = "${path.module}/layer"
  output_path = "${path.module}/layer.zip"
  depends_on  = [null_resource.pip_install]
}

resource "aws_lambda_layer_version" "layer" {
  layer_name          = "test-layer"
  filename            = data.archive_file.layer.output_path
  source_code_hash    = data.archive_file.layer.output_base64sha256
  compatible_runtimes = ["python3.12"]
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/code.zip"
}

resource "aws_iam_role" "iam_role" {
  name = "lambda-iam-role"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "lambda.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}


resource "aws_iam_policy" "lambda_logs_policy" {
  name        = "lambda-logs-policy"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.iam_role.name
  policy_arn = aws_iam_policy.lambda_logs_policy.arn
}

resource "aws_lambda_function" "lambda" {
  function_name    = "test-lambda"
  handler          = "main.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  role             = aws_iam_role.iam_role.arn
  layers           = [aws_lambda_layer_version.layer.arn]
  environment {
    variables = {
      "MY_VAR" = "HELLO FROM TF"
    }
  }
}

# EVENTBRIDGE

resource "aws_cloudwatch_event_rule" "every_hour" {
  name                = "every-hour"
  description         = "Trigger every hour"
  schedule_expression = "cron(0 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "invoke_lambda_every_hour" {
  rule      = aws_cloudwatch_event_rule.every_hour.name
  arn       = aws_lambda_function.lambda.arn
  target_id = "TargetFunction"
}

resource "aws_lambda_permission" "allow_eventbridge_to_call_lambda" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_hour.arn
}