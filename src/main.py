import requests
import os


def handler(event, context):
    encoded_email = requests.utils.quote("foo+bar@email.com")
    return {"statusCode": 200, "body": f"Hello, {encoded_email}, from {os.environ['MY_VAR']}"}
