#!/usr/bin/env bash

source $(dirname $0)/common.sh || echo "$0: Failed to source common.sh"

processCliArgs $@

# more bash-friendly output for jq
JQ="jq --raw-output --exit-status"

install_tools() {
  pip install --upgrade pip
  pip install --upgrade awscli
  sudo apt-get install jq
}

# Check whether to install aws cli or jq
which aws &>/dev/null || install_tools
which jq &>/dev/null || install_tools

echo "Set AWS region"
aws configure set default.region ${ARGS[--aws_region]}

make_task_def() {
	task_def_json="[
  		{
  			\"name\": \"${ARGS[--ecs_service]}-${ARGS[--suffix]}-${ARGS[--colour]}\",
  			\"image\": \"${ARGS[--aws_account_id]}.dkr.ecr.eu-west-1.amazonaws.com/${ARGS[--image_name]}:${ARGS[--image_version]}\",
  			\"essential\": true,
  			\"memory\": ${ARGS[--memory]},
  			\"cpu\": ${ARGS[--cpu]},
        \"logConfiguration\": {
  	        \"logDriver\": \"splunk\",
  	        \"options\": {
                \"splunk-url\": \"https://http-inputs-financialtimes.splunkcloud.com\",
                \"splunk-token\": \"${ARGS[--splunk]}\",
                \"splunk-index\": \"data_${ARGS[--environment]}\",
                \"splunk-source\": \"${ARGS[--ecs_service]}\",
                \"splunk-insecureskipverify\": \"true\",
                \"splunk-format\": \"json\"
  	        }
        },
  			\"environment\": [
  			    {
  			        \"name\": \"ENVIRONMENT\",
  			        \"value\": \"${ARGS[--environment]}\"
  			    },
  			    {
  			        \"name\": \"SUFFIX\",
  			        \"value\": \"${ARGS[--suffix]}\"
            },
  			    {
  			        \"name\": \"CONTEXT\",
  			        \"value\": \"${ARGS[--context]}\"
  			    },
  			    {
  			        \"name\": \"ENABLE_VAULT\",
  			        \"value\": \"${ARGS[--enable_vault]}\"
  			    },
                {
                    \"name\": \"AWS_REGION\",
                    \"value\": \"${ARGS[--aws_region]}\"
                }
  			],
  			\"mountPoints\": [
            {
                \"sourceVolume\": \"ecs-data\",
                \"containerPath\": \"/tmp/data\",
                \"readOnly\": false
            },
            {
                \"sourceVolume\": \"ecs-logs\",
                \"containerPath\": \"/tmp/logs\",
                \"readOnly\": false
            }
        ],
        \"portMappings\": [
  				{
  					\"containerPort\": 8080,
  					\"hostPort\": ${ARGS[--httpPort]}
  				},
  				{
  					\"containerPort\": 8081,
  					\"hostPort\": ${ARGS[--adminPort]}
  				}
  			]
  		}
  	]"

    task_def=$(printf "$task_def_json")
}

make_volumes() {
    volumes_json="[
        {
            \"name\": \"ecs-logs\",
            \"host\": {
                \"sourcePath\": \"/mnt/ebs/logs/\"
            }
        },
        {
            \"name\": \"ecs-data\",
            \"host\": {
                \"sourcePath\": \"/mnt/ebs/data/\"
            }
        }
    ]"

    volumes=$(printf "$volumes_json")
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
        exit 1
    fi

}

# make sure you start this containter on Cluster 01 only (required by apps that need access to persistend data)
#make_placement_constraint() {
#    placement_constraint_template='[
#        {
#            "expression": "attribute:ecs.availability-zone =~ eu-west-1%s",
#            "type": "memberOf"
#        }
#    ]'
#
#    placement_constraint=$(printf "$placement_constraint_template" ${ARGS[--zone_constraint]})
#}

deploy_service() {
    family="${ARGS[--ecs_service]}-${ARGS[--suffix]}-${ARGS[--colour]}-task-family"
    echo "Family name is ${family}"

    task_role_arn="arn:aws:iam::${ARGS[--aws_account_id]}:role/${ARGS[--aws_role]}"
    echo "Task role is: ${task_role_arn}"

    make_task_def
    make_volumes
    #make_placement_constraint

    register_task_definition
    register_task_definition

    if [[ $(aws ecs update-service --cluster ${ARGS[--cluster_name]}-${ARGS[--colour]} \
                --service ${ARGS[--ecs_service]}-${ARGS[--suffix]}-${ARGS[--colour]} \
                --task-definition $revision | \
                   $JQ '.service.taskDefinition') != $revision ]]; then
        echo "Error updating service."
        exit 1
    fi
}

deploy_service
