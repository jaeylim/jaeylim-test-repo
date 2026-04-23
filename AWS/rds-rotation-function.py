import boto3
import logging
import os
import pymysql
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    arn = event['SecretId'] # 어떤 시크릿인지
    token = event['ClientRequestToken'] # 이번 Rotation 고유 ID
    step = event['Step'] #지금 몇 단계인지

    client = boto3.client('secretsmanager', region_name=os.environ.get('AWS_REGION', 'ap-northeast-2'))

    metadata = client.describe_secret(SecretId=arn)
    if not metadata['RotationEnabled']:
        raise ValueError("Secret {} is not enabled for rotation".format(arn))

    versions = metadata['VersionIdsToStages']
    if token not in versions:
        raise ValueError("Secret version {} has no stage for rotation of secret {}".format(token, arn))
    if 'AWSCURRENT' in versions[token]:
        logger.info("Secret version {} already set as AWSCURRENT for secret {}".format(token, arn))
        return
    elif 'AWSPENDING' not in versions[token]:
        raise ValueError("Secret version {} not set as AWSPENDING for rotation of secret {}".format(token, arn))

    if step == 'createSecret':
        create_secret(client, arn, token)
    elif step == 'setSecret':
        set_secret(client, arn, token)
    elif step == 'testSecret':
        test_secret(client, arn, token)
    elif step == 'finishSecret':
        finish_secret(client, arn, token)
    else:
        raise ValueError("Invalid step parameter {}".format(step))

def create_secret(client, arn, token):
    try:
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage='AWSPENDING')
        logger.info("createSecret: Successfully retrieved secret for {}".format(arn))
    except client.exceptions.ResourceNotFoundException:
        current = get_secret_dict(client, arn, 'AWSCURRENT')
        passwd = client.get_random_password(ExcludeCharacters='/@"\'\\')['RandomPassword']
        current['password'] = passwd
        client.put_secret_value(
            SecretId=arn, ClientRequestToken=token,
            SecretString=str(current).replace("'", '"'),
            VersionStages=['AWSPENDING']
        )

def set_secret(client, arn, token):
    current = get_secret_dict(client, arn, 'AWSCURRENT')
    pending = get_secret_dict(client, arn, 'AWSPENDING', token)
    conn = get_connection(current)
    if not conn:
        raise ValueError("Unable to connect to DB with current credentials for {}".format(arn))
    try:
        with conn.cursor() as cur:
            cur.execute("ALTER USER '{}'@'%' IDENTIFIED BY '{}'".format(pending['username'], pending['password']))
        conn.commit()
    finally:
        conn.close()

def test_secret(client, arn, token):
    pending = get_secret_dict(client, arn, 'AWSPENDING', token)
    conn = get_connection(pending)
    if not conn:
        raise ValueError("Unable to connect to DB with pending credentials for {}".format(arn))
    conn.close()

def finish_secret(client, arn, token):
    metadata = client.describe_secret(SecretId=arn)
    current_version = next(v for v, stages in metadata['VersionIdsToStages'].items() if 'AWSCURRENT' in stages)
    client.update_secret_version_stage(
        SecretId=arn, VersionStage='AWSCURRENT',
        MoveToVersionId=token, RemoveFromVersionId=current_version
    )

def get_secret_dict(client, arn, stage, token=None):
    kwargs = {'SecretId': arn, 'VersionStage': stage}
    if token:
        kwargs['VersionId'] = token
    secret = client.get_secret_value(**kwargs)['SecretString']
    import json
    return json.loads(secret)

def get_connection(secret_dict):
    try:
        return pymysql.connect(
            host=secret_dict['host'],
            user=secret_dict['username'],
            password=secret_dict['password'],
            port=int(secret_dict.get('port', 3306)),
            connect_timeout=5
        )
    except Exception as e:
        logger.error("Connection failed: {}".format(e))
        return None