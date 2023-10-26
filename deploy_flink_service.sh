#!/usr/bin/env bash

# THIS SCRIPT CAN BE USED TO RUN FLINK IN ECS. PLEASE NOTE THAT WE RUN FLINK ON DOCKER SWARM NOW

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
  			\"name\": \"${ARGS[--ecs_service]}-${ARGS[--suffix]}-cli-${ARGS[--colour]}\",
  			\"image\": \"${ARGS[--aws_account_id]}.dkr.ecr.eu-west-1.amazonaws.com/${ARGS[--image_name]}:${ARGS[--image_version]}\",
  			\"essential\": false,
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
  			        \"name\": \"vault_context\",
  			        \"value\": \"${ARGS[--ecs_service]}\"
  			    },
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
            },
            {
                \"name\": \"FLINK_ENVIRONMENT\",
                \"value\": \"${ARGS[--environment]}\"
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
        \"entryPoint\": [
          \"/wait-for-it.sh\",
          \"jobmanager:8081\",
          \"--timeout=300\",
          \"--\",
          \"/jobs-entrypoint.sh\"
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
                \"name\": \"vault_context\",
                \"value\": \"${ARGS[--ecs_service]}\"
            },
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
                \"name\": \"AWS_REGION\",
                \"value\": \"${ARGS[--aws_region]}\"
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
            },
            {
                \"name\": \"FLINK_ENVIRONMENT\",
                \"value\": \"${ARGS[--environment]}\"
            },
            {
                \"name\": \"FLINK_GRAPHITE_HOST\",
                \"value\": \"graphite.ft.com\"
            },
            {
                \"name\": \"FLINK_SAVEPOINTS_LOCATION\",
                \"value\": \"${ARGS[--flink_savepoints_location]}\"
            },
            {
                \"name\": \"FLINK_CHECKPOINTS_LOCATION\",
                \"value\": \"${ARGS[--flink_checkpoints_location]}\"
            },
            {
                \"name\": \"FLINK_FS_CHECKPOINTS_LOCATION\",
                \"value\": \"${ARGS[--flink_fs_checkpoints_location]}\"
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
        \"entryPoint\": [
          \"bash\",
          \"/flink-entrypoint.sh\"
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
                \"name\": \"vault_context\",
                \"value\": \"${ARGS[--ecs_service]}\"
            },
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
            },
            {
                \"name\": \"FLINK_ENVIRONMENT\",
                \"value\": \"${ARGS[--environment]}\"
            },
            {
                \"name\": \"FLINK_GRAPHITE_HOST\",
                \"value\": \"graphite.ft.com\"
            },
            {
                \"name\": \"FLINK_SAVEPOINTS_LOCATION\",
                \"value\": \"${ARGS[--flink_savepoints_location]}\"
            },
            {
                \"name\": \"FLINK_CHECKPOINTS_LOCATION\",
                \"value\": \"${ARGS[--flink_checkpoints_location]}\"
            },
            {
                \"name\": \"FLINK_FS_CHECKPOINTS_LOCATION\",
                \"value\": \"${ARGS[--flink_fs_checkpoints_location]}\"
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
        \"entryPoint\": [
          \"/wait-for-it.sh\",
          \"jobmanager:8081\",
          \"--timeout=300\",
          \"--\",
          \"/flink-entrypoint.sh\"
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
                \"sourcePath\": \"/mnt/ebs/logs/flink\"
            }
        },
        {
            \"name\": \"ecs-data\",
            \"host\": {
                \"sourcePath\": \"/mnt/ebs/data/flink\"
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

    if [[ $(aws ecs update-service --cluster ${ARGS[--cluster_name]}-${ARGS[--colour]} \
                --service ${ARGS[--ecs_service]}-${ARGS[--suffix]}-${ARGS[--colour]} \
                --task-definition $revision | \
                   $JQ '.service.taskDefinition') != $revision ]]; then
        echo "Error updating service."
        exit 1
    fi
}

deploy_service
