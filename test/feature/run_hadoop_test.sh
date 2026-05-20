#!/bin/bash
set -e

cluster_url="${1:-http://localhost:8080}"
test_bucket="hadoop-s3a-test"
image_name="ghcr.io/stjank/hadoop-s3a-tests:v1"

export UH_ROOT_USER="main"
export UH_ROOT_ACCESS_KEY="0555b35654ad1656d804"
export UH_ROOT_SECRET_KEY="h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q=="

export AWS_ACCESS_KEY_ID="$UH_ROOT_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$UH_ROOT_SECRET_KEY"
export AWS_DEFAULT_REGION="us-east-1"
aws --endpoint-url "$cluster_url" --no-verify-ssl s3 mb "s3://$test_bucket"

docker run --rm --network host \
    -e S3_ENDPOINT="$cluster_url" \
    -e S3_ACCESS_KEY="$UH_ROOT_ACCESS_KEY" \
    -e S3_SECRET_KEY="$UH_ROOT_SECRET_KEY" \
    -e S3_BUCKET="$test_bucket" \
    ${IT_TEST:+-e IT_TEST="$IT_TEST"} \
    "$image_name"
