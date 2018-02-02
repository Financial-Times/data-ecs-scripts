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
test -z ${ARGS[--suffix]} && ARGS[--suffix]=$3
test -z ${ARGS[--image_name]} && ARGS[--image_name]=${4:-${SERVICE_NAME}}
test -z ${ARGS[--image_version]} && ARGS[--image_version]=${5:-1.1.0-${CIRCLE_BUILD_NUM}}
test -z ${ARGS[--aws_account_id]} && ARGS[--aws_account_id]=${6:-${AWS_ACCOUNT_NUMBER}}
test -z ${ARGS[--aws_region]} && ARGS[--aws_region]=${7:-"eu-west-1"}
test -z ${ARGS[--memory]} && ARGS[--memory]=${8:-"256"}
test -z ${ARGS[--cpu]} && ARGS[--cpu]=${9:-"10"}
test -z ${ARGS[--port1]} && ARGS[--port1]=${10:-"1000"}
test -z ${ARGS[--port2]} && ARGS[--port2]=${11:-"1001"}
test -z ${ARGS[--zone_constraint]} && ARGS[--zone_constraint]=${12:-"a"}
test -z ${ARGS[--environment]} && ARGS[--environment]=${13:-"dev"}
test -z ${ARGS[--splunk]} && ARGS[--splunk]=${14:-""}
test -z ${ARGS[--colour]} && ARGS[--colour]=${15:-"green"}

# more bash-friendly output for jq
JQ="jq --raw-output --exit-status"

install_aws_cli() {
  pip install --upgrade pip
  pip install --upgrade awscli
  sudo apt-get install jq
}

# Check whether to install aws clis
which aws &>/dev/null || install_aws_cli

echo "Set AWS region"
aws configure set default.region ${ARGS[--aws_region]}

make_task_definition(){
	task_template='[
		{
			"name": "%s-%s-%s",
			"image": "%s.dkr.ecr.eu-west-1.amazonaws.com/%s:%s",
			"essential": true,
			"memory": %s,
			"cpu": %s,
			"environment": [
			    {
			        "name": "environment",
			        "value": "%s"
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
            ],
			"portMappings": [
				{
					"containerPort": 8080,
					"hostPort": %s
				},
				{
					"containerPort": 8081,
					"hostPort": %s
				}
			]
		}
	]'

    task_def=$(printf "$task_template" ${ARGS[--ecs_service]} ${ARGS[--suffix]}  ${ARGS[--colour]} ${ARGS[--aws_account_id]} ${ARGS[--image_name]} ${ARGS[--image_version]} ${ARGS[--memory]} ${ARGS[--cpu]} ${ARGS[--splunk]} ${ARGS[--environment]} ${ARGS[--ecs_service]} ${ARGS[--environment]} ${ARGS[--suffix]} ${ARGS[--port1]} ${ARGS[--port2]} )
}

volume_mount_def(){
    volume_mount='[
        {
            "name": "ecs-logs",
            "host": {
                "sourcePath": "/mnt/ebs/logs/"
            }
        },
        {
            "name": "ecs-data",
            "host": {
                "sourcePath": "/mnt/ebs/data/"
            }
        }
    ]'

    volumes=$(printf "$volume_mount")
}

register_task_definition() {
    echo "Registering task definition ${task_def}"
    if revision=$(aws ecs register-task-definition --volumes "$volumes" --placement-constraints "$placement_constraint" --task-role-arn $task_role_arn --container-definitions "$task_def" --family $family --output text --query 'taskDefinition.taskDefinitionArn'); then
        echo "Revision: $revision"
    else
        echo "Failed to register task definition"
        return 1
    fi

}

# make sure you start this containter on Cluster 01 only (required by apps that need access to persistend data)
placement_constraint_def(){
    placement_constraint_template='[
        {
            "expression": "attribute:ecs.availability-zone =~ eu-west-1%s",
            "type": "memberOf"
        }
    ]'

    placement_constraint=$(printf "$placement_constraint_template" ${ARGS[--zone_constraint]})
}

deploy_cluster() {

    family="${ARGS[--ecs_service]}-${ARGS[--suffix]}-task-family"
    echo "Family name is ${family}"
    task_role_arn="arn:aws:iam::${ARGS[--aws_account_id]}:role/FTApplicationRoleFor_ingesters"
    echo "Task role is: ${task_role_arn}"

    make_task_definition
    volume_mount_def
    placement_constraint_def
    register_task_definition

    register_task_definition

    if [[ $(aws ecs update-service --cluster ${ARGS[--cluster_name]}-${ARGS[--colour]} --service ${ARGS[--ecs_service]}-${ARGS[--suffix]}-${ARGS[--colour]} --task-definition $revision | \
                   $JQ '.service.taskDefinition') != $revision ]]; then
        echo "Error updating service."
        return 1
    fi
}

deploy_cluster
