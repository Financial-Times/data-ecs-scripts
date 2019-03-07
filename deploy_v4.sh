#!/usr/bin/env bash
#
# Create ECS task defintion and update service
#
# Script is intended to be run by CircleCI. It references variables CIRCLE_PROJECT_REPONAME and  CIRCLE_BUILD_NUM
# unless passed in as command line parameter
#
# Script is based on https://github.com/circleci/go-ecs-ecr/blob/master/deploy.sh
#
# Optional parameters
# --skip-setting-up-port-mapping-to-host=true
#
# USAGE:
#deploy.sh --cluster_name=data-platform-ecs-cluster \
#  --ecs_service=${SERVICE_NAME} \
#  --suffix="prod1" \
#  --image_name=${SERVICE_NAME} \
#  --image_version=$(cat /tmp/workspace/version) \
#  --aws_account_id=${AWS_PROD_ACCOUNT_NUMBER} \
#  --aws_region="eu-west-1" \
#  --memory="512" \
#  --cpu="128" \
#  --port1="5040" \
#  --port2="7040" \
#  --environment="prod" \
#  --splunk=${SPLUNK_TOKEN} \
#  --colour="green" \
#  --aws_role="FTApplicationRoleFor_passtool"

set -x

source $(dirname $0)/common.sh || echo "$0: Failed to source common.sh"
processCliArgs $@

#Rather than using default values we should just error out if some of the required parameters have not been provided
VARIABLES_THAT_SHOULD_NOT_BE_EMPTY=(\
  --cluster_name\
  --ecs_service\
  --suffix\
  --image_name\
  --image_version\
  --aws_account_id\
  --aws_region\
  --memory\
  --cpu\
  --port1\
  --port2\
  --environment\
  --splunk\
  --colour\
  --aws_role\
)

for VARIABLE_NAME in ${VARIABLES_THAT_SHOULD_NOT_BE_EMPTY[@]}; do
  if [ -z ${ARGS[${VARIABLE_NAME}]} ]; then
    echo "Required parameter \"${VARIABLE_NAME}\" is not set. Exitting"
    exit 1
  fi
done

exit 0


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
			"logConfiguration": {
			    "logDriver": "splunk",
			        "options": {
			           "splunk-url": "https://http-inputs-financialtimes.splunkcloud.com",
			           "splunk-token": "%s",
			           "splunk-index": "data_%s",
			           "splunk-source": "%s",
			           "splunk-insecureskipverify": "true",
			           "splunk-format": "json"
			        }
            },
			"environment": [
			    {
			        "name": "environment",
			        "value": "%s"
			    },
			    {
			        "name": "suffix",
			        "value": "%s"
			    },
			    {
			        "name": "service_name",
			        "value":"%s"
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
                  "containerPath": "/usr/local/dropwizards/data",
                  "readOnly": false
                },
                {
                  "sourceVolume": "ecs-data",
                  "containerPath": "/tmp/data",
                  "readOnly": false
                },
                {
                  "sourceVolume": "ecs-logs",
                  "containerPath": "/tmp/logs",
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

    task_def=$(printf "$task_template" ${ARGS[--ecs_service]} \
                                       ${ARGS[--suffix]}  \
                                       ${ARGS[--colour]} \
                                       ${ARGS[--aws_account_id]} \
                                       ${ARGS[--image_name]} \
                                       ${ARGS[--image_version]} \
                                       ${ARGS[--memory]} \
                                       ${ARGS[--cpu]} \
                                       ${ARGS[--splunk]} \
                                       ${ARGS[--environment]} \
                                       ${ARGS[--ecs_service]} \
                                       ${ARGS[--environment]} \
                                       ${ARGS[--suffix]} \
                                       ${ARGS[--ecs_service]} \
                                       ${ARGS[--port1]} \
                                       ${ARGS[--port2]} )
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
    if revision=$(aws ecs register-task-definition \
            --volumes "$volumes" \
            --task-role-arn $task_role_arn \
            --container-definitions "$task_def" \
            --family $family \
            --output text \
            --query 'taskDefinition.taskDefinitionArn'); then
        echo "Revision: $revision"
    else
        echo "Failed to register task definition"
        return 1
    fi

}

# make sure you start this containter on Cluster 01 only (required by apps that need access to persistend data)
#placement_constraint_def(){
#    placement_constraint_template='[
#        {
#            "expression": "attribute:ecs.availability-zone =~ eu-west-1%s",
#            "type": "memberOf"
#        }
#    ]'
#
#    placement_constraint=$(printf "$placement_constraint_template" ${ARGS[--zone_constraint]})
#}

deploy_cluster() {

    family="${ARGS[--ecs_service]}-${ARGS[--suffix]}-${ARGS[--colour]}-task-family"
    echo "Family name is ${family}"
    task_role_arn="arn:aws:iam::${ARGS[--aws_account_id]}:role/${ARGS[--aws_role]}"
    echo "Task role is: ${task_role_arn}"

    make_task_definition
    volume_mount_def
    #placement_constraint_def
    register_task_definition

    register_task_definition

    if [[ $(aws ecs update-service --cluster ${ARGS[--cluster_name]}-${ARGS[--colour]} \
                --service ${ARGS[--ecs_service]}-${ARGS[--suffix]}-${ARGS[--colour]} \
                --task-definition $revision | \
                   $JQ '.service.taskDefinition') != $revision ]]; then
        echo "Error updating service."
        return 1
    fi
}

deploy_cluster
