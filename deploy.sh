#!/usr/bin/env bash
#
# Create ECS task defintion and update service
#
# Script is intended to be run by CircleCI. It references variables CIRCLE_PROJECT_REPONAME and  CIRCLE_BUILD_NUM
# unless passed in as command line parameter
#
# Script is based on https://github.com/circleci/go-ecs-ecr/blob/master/deploy.sh
#
# USAGE: deploy.sh <ecs_cluster> <ecs_service> [image_name] [image_version] [aws_account_id] [region]
#   OR
# USAGE: deploy.sh --ecs_cluster=cluster_name --ecs_service=service_name [--image_name=image_name] [--image_version=image_version] [--aws_account_id=aws_account_id] [--aws_region=aws_region]
#

source $(dirname $0)/common.sh || echo "$0: Failed to source common.sh"
processCliArgs $@

test -z ${ARGS[--cluster_name]} && ARGS[--cluster_name]=$1
test -z ${ARGS[--ecs_service]} && ARGS[--ecs_service]=$2
test -z ${ARGS[--image_name]} && ARGS[--image_name]=${3:-${SERVICE_NAME}}
test -z ${ARGS[--image_version]} && ARGS[--image_version]=${4:-1.0.${CIRCLE_BUILD_NUM}}
test -z ${ARGS[--aws_account_id]} && ARGS[--aws_account_id]=${5:-${AWS_ACCOUNT_NUMBER}}
test -z ${ARGS[--aws_region]} && ARGS[--aws_region]=${6:-"eu-west-1"}
test -z ${ARGS[--memory]} && ARGS[--memory]=${7:-"256"}
test -z ${ARGS[--cpu]} && ARGS[--cpu]=${8:-"10"}
test -z ${ARGS[--port1]} && ARGS[--port1]=${9:-"1000"}
test -z ${ARGS[--port2]} && ARGS[--port2]=${10:-"1001"}

deploy() {
    if [[ $(aws ecs update-service --cluster ${ARGS[--cluster_name]} --service ${ARGS[--ecs_service]} --task-definition $revision \
            --output text --query 'service.taskDefinition') != $revision ]]; then
        echo "Error updating service."
        return 1
    fi
}

make_task_definition(){
	task_template='[
		{
			"name": "%s",
			"image": "%s.dkr.ecr.eu-west-1.amazonaws.com/%s:%s",
			"essential": true,
			"memory": %s,
			"cpu": %s,
			"portMappings": [
				{
					"containerPort": 8080,
					"hostPort": %s
				},
				{
					"containerPort": 8081,
					"hostPort": %s
				}
			],
			"mountPoints": [
                {
                  "sourceVolume": "ecs-logs",
                  "containerPath": "/var/log/apps",
                  "readOnly": false
                },
                {
                  "sourceVolume": "ecs-data",
                  "containerPath": "/usr/local/dropwizard/data",
                  "readOnly": false
                }
            ]
		}
	]'

	task_def=$(printf "$task_template" ${ARGS[--ecs_service]} ${ARGS[--aws_account_id]} ${ARGS[--image_name]} ${ARGS[--image_version]} ${ARGS[--memory]} ${ARGS[--cpu]} ${ARGS[--port1]} ${ARGS[--port2]} )
}

register_task_definition() {
    echo "Registering task definition ${task_def}"
    if revision=$(aws ecs register-task-definition --container-definitions "$task_def" --family "${ARGS[--ecs_service]}" --output text --query 'taskDefinition.taskDefinitionArn'); then
        echo "Revision: $revision"
    else
        echo "Failed to register task definition"
        return 1
    fi

}

make_task_definition
register_task_definition
deploy