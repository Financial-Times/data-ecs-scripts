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
  			\"memory\": 600,
  			\"cpu\": 512,
        \"hostname\": \"job\",
        \"links\": [\"${ARGS[--ecs_service]}-${ARGS[--suffix]}-jobmanager-${ARGS[--colour]}:jobmanager\"],
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
  			        \"name\": \"environment\",
  			        \"value\": \"${ARGS[--environment]}\"
  			    },
  			    {
  			        \"name\": \"suffix\",
  			        \"value\": \"${ARGS[--suffix]}\"
            },
  			    {
  			        \"name\": \"context\",
  			        \"value\": \"${ARGS[--context]}\"
  			    },
            {
                \"name\": \"JOB_MANAGER_RPC_ADDRESS\",
                \"value\": \"jobmanager\"
            },
            {
                \"name\": \"FLINK_JM_HEAP\",
                \"value\": \"${ARGS[--flink_jobmanager_heap]}\"
            },
            {
                \"name\": \"FLINK_TM_HEAP\",
                \"value\": \"${ARGS[--flink_taskmanager_heap]}\"
            }
  			],
        \"mountPoints\": [
            {
                \"sourceVolume\": \"ecs-data\",
                \"containerPath\": \"/tmp\",
                \"readOnly\": false
            }
        ],
        \"ulimits\": [
            {
                \"name\": \"nofile\",
                \"softLimit\": 10000,
                \"hardLimit\": 10000
            }
        ]
  		},
      {
        \"name\": \"${ARGS[--ecs_service]}-${ARGS[--suffix]}-jobmanager-${ARGS[--colour]}\",
        \"image\": \"${ARGS[--aws_account_id]}.dkr.ecr.eu-west-1.amazonaws.com/${ARGS[--flink_image_name]}:${ARGS[--flink_image_version]}\",
        \"essential\": true,
        \"memory\": ${ARGS[--flink_jobmanager_container_memory]},
        \"cpu\": 512,
        \"hostname\": \"jobmanager\",
        \"logConfiguration\": {
            \"logDriver\": \"splunk\",
            \"options\": {
                \"splunk-url\": \"https://http-inputs-financialtimes.splunkcloud.com\",
                \"splunk-token\": \"${ARGS[--splunk]}\",
                \"splunk-index\": \"data_${ARGS[--environment]}\",
                \"splunk-source\": \"${ARGS[--ecs_service]}-jobmanager\",
                \"splunk-insecureskipverify\": \"true\",
                \"splunk-format\": \"json\"
            }
        },
        \"environment\": [
            {
                \"name\": \"environment\",
                \"value\": \"${ARGS[--environment]}\"
            },
            {
                \"name\": \"suffix\",
                \"value\": \"${ARGS[--suffix]}\"
            },
            {
                \"name\": \"context\",
                \"value\": \"${ARGS[--context]}\"
            },
            {
                \"name\": \"JOB_MANAGER_RPC_ADDRESS\",
                \"value\": \"jobmanager\"
            },
            {
                \"name\": \"FLINK_JM_HEAP\",
                \"value\": \"${ARGS[--flink_jobmanager_heap]}\"
            },
            {
                \"name\": \"FLINK_TM_HEAP\",
                \"value\": \"${ARGS[--flink_taskmanager_heap]}\"
            }
        ],
        \"mountPoints\": [
            {
                \"sourceVolume\": \"ecs-data\",
                \"containerPath\": \"/tmp\",
                \"readOnly\": false
            }
        ],
        \"ulimits\": [
            {
                \"name\": \"nofile\",
                \"softLimit\": 10000,
                \"hardLimit\": 10000
            }
        ],
        \"command\": [\"jobmanager\"]
      },
      {
        \"name\": \"${ARGS[--ecs_service]}-${ARGS[--suffix]}-taskmanager-${ARGS[--colour]}\",
        \"image\": \"${ARGS[--aws_account_id]}.dkr.ecr.eu-west-1.amazonaws.com/${ARGS[--flink_image_name]}:${ARGS[--flink_image_version]}\",
        \"essential\": true,
        \"memory\": ${ARGS[--flink_taskmanager_container_memory]},
        \"cpu\": 512,
        \"hostname\": \"taskmanager\",
        \"links\": [\"${ARGS[--ecs_service]}-${ARGS[--suffix]}-jobmanager-${ARGS[--colour]}:jobmanager\"],
        \"logConfiguration\": {
            \"logDriver\": \"splunk\",
            \"options\": {
                \"splunk-url\": \"https://http-inputs-financialtimes.splunkcloud.com\",
                \"splunk-token\": \"${ARGS[--splunk]}\",
                \"splunk-index\": \"data_${ARGS[--environment]}\",
                \"splunk-source\": \"${ARGS[--ecs_service]}-taskmanager\",
                \"splunk-insecureskipverify\": \"true\",
                \"splunk-format\": \"json\"
            }
        },
        \"environment\": [
            {
                \"name\": \"environment\",
                \"value\": \"${ARGS[--environment]}\"
            },
            {
                \"name\": \"suffix\",
                \"value\": \"${ARGS[--suffix]}\"
            },
            {
                \"name\": \"context\",
                \"value\": \"${ARGS[--context]}\"
            },
            {
                \"name\": \"JOB_MANAGER_RPC_ADDRESS\",
                \"value\": \"jobmanager\"
            },
            {
                \"name\": \"FLINK_JM_HEAP\",
                \"value\": \"${ARGS[--flink_jobmanager_heap]}\"
            },
            {
                \"name\": \"FLINK_TM_HEAP\",
                \"value\": \"${ARGS[--flink_taskmanager_heap]}\"
            }
        ],
        \"mountPoints\": [
            {
                \"sourceVolume\": \"ecs-data\",
                \"containerPath\": \"/tmp\",
                \"readOnly\": false
            }
        ],
        \"ulimits\": [
            {
                \"name\": \"nofile\",
                \"softLimit\": 10000,
                \"hardLimit\": 10000
            }
        ],
        \"command\": [\"taskmanager\"]
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
}

deploy_service
