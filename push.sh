#!/usr/bin/env bash
#
# Push Docker image to ECR
#
# Script is intended to be run by CircleCI. It references variables CIRCLE_PROJECT_REPONAME and  IMAGE_VERSION
# unless passed in as command line parameter
#
#
# USAGE: ./push.sh [image_name] [image_version] [aws_account_id] [aws_region]
#   OR
# USAGE: ./push.sh --image_name=image_name --image_version=image_version --aws_account_id=aws_account_id --aws_region=aws_region --ecr_endpoint=ecr-endpoint

source $(dirname $0)/common.sh || echo "$0: Failed to source common.sh"

processCliArgs $@

test -z ${ARGS[--service_name]} && ARGS[--service_name]=${1:-${SERVICE_NAME}}
test -z ${ARGS[--image_version]} && ARGS[--image_version]=${2:-1.0.${CIRCLE_BUILD_NUM}}
test -z ${ARGS[--aws_account_id]} && ARGS[--aws_account_id]=${3:-@@account@@}
test -z ${ARGS[--aws_region]} && ARGS[--aws_region]=${4:-"eu-west-1"}
test -z ${ARGS[--ecr_endpoint]} && ARGS[--ecr_endpoint]=${5:-"@@account@@.dkr.ecr.eu-west-1.amazonaws.com"}

install_aws_cli() {
  pip install --upgrade pip
  pip install --upgrade awscli
}

# Check whether to install aws clis
which aws &>/dev/null || install_aws_cli

echo "Set AWS region"
aws configure set default.region ${ARGS[--aws_region]}

echo "Login to ECR"
$(aws ecr get-login --no-include-email)

echo "Verify repository exists"
aws ecr describe-repositories --repository-names ${ARGS[--image_name]}} &>/dev/null || \
#aws ecr create-repository --repository-name ${ARGS[--image_name]}

echo "Tag image"
docker tag ${ARGS[--service_name]}:${ARGS[--image_version]} \
  ${ARGS[--ecr_endpoint]}/${ARGS[--service_name]}:${ARGS[--image_version]}


echo "Pushing container to ECR"
docker push ${ARGS[--ecr_endpoint]}/${ARGS[--service_name]}:${ARGS[--image_version]}