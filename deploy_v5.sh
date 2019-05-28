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
#  --volume-mounts="ecs-logs:/mnt/source1:/mount/destination1/:read_only_true;ecs-data:/mnt/source2:/mnt/destination2/:read_only_false"

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

#Deliberately fail if a required variable is empty
for VARIABLE_NAME in ${VARIABLES_THAT_SHOULD_NOT_BE_EMPTY[@]}; do
  if [ -z ${ARGS[${VARIABLE_NAME}]} ]; then
    echo "Required parameter \"${VARIABLE_NAME}\" is not set. Exitting"
    exit 1
  fi
done

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

#DEFAULT_VOLUME_MOUNTS="ecs-logs:/mnt/source1:/mount/destination1/:read_only_true;ecs-data:/mnt/source2:/mnt/destination2/:read_only_false"
VOLUME_MOUNTS=${ARGS[--volume-mounts]}

for SINGLE_RECORD in $(tr \; \  <<< ${VOLUME_MOUNTS}) ; do
  VOLUME_MOUNT_ARRAY+=("$SINGLE_RECORD")
done

define_volumes() {
  local lcl_VOLUME_MOUNTS=${1}
  local lcl_VOLUME_MOUNT_ARRAY=()
  local lcl_RECORD_NUMBER=""
  local lcl_SOURCE_MOUNT_FOLDER=""
  local lcl_VOLUME_NAME=""
  local lcl_DESTINATION_MOUNT_FOLDER=""
  local lcl_READ_ONLY_MOUNT=""

  local lcl_VOLUME_MOUNT_STRING=""    

  for SINGLE_RECORD in $(tr \; \  <<< ${lcl_VOLUME_MOUNTS}) ; do
    lcl_VOLUME_MOUNT_ARRAY+=("$SINGLE_RECORD")
  done


  lcl_VOLUME_MOUNT_STRING="'["
  
  
  local lcl_RECORD_NUMBER=0
  for SINGLE_RECORD in ${VOLUME_MOUNT_ARRAY[@]}; do
    lcl_RECORD_NUMBER=$((lcl_RECORD_NUMBER + 1))
    lcl_SOURCE_MOUNT_FOLDER="$(cut -d: -f2 <<< ${SINGLE_RECORD})"
    lcl_VOLUME_NAME="$(cut -d: -f1 <<< ${SINGLE_RECORD})"
    lcl_VOLUME_MOUNT_STRING="${lcl_VOLUME_MOUNT_STRING} {\"name\": \"${lcl_VOLUME_NAME}\", \"host\": { \"sourcePath\": \"${lcl_SOURCE_MOUNT_FOLDER}\" }    }"
    #Check whether this is the last element of the array to decide whether to put a comma
    if [[ ${lcl_RECORD_NUMBER} != ${#lcl_VOLUME_MOUNT_ARRAY[@]} ]]; then
      lcl_VOLUME_MOUNT_STRING="${lcl_VOLUME_MOUNT_STRING}, "
    fi
  done

#  volumes="${lcl_VOLUME_MOUNT_STRING}"
  echo "${lcl_VOLUME_MOUNT_STRING}"
}


mount_points_def(){
  local lcl_VOLUME_MOUNTS=${1}
  local lcl_VOLUME_MOUNT_ARRAY=()
  local lcl_RECORD_NUMBER=""
  local lcl_SOURCE_MOUNT_FOLDER=""
  local lcl_VOLUME_NAME=""
  local lcl_DESTINATION_MOUNT_FOLDER=""
  local lcl_READ_ONLY_MOUNT=""

  local lcl_VOLUME_MOUNT_STRING=""    

  for SINGLE_RECORD in $(tr \; \  <<< ${lcl_VOLUME_MOUNTS}) ; do
    lcl_VOLUME_MOUNT_ARRAY+=("$SINGLE_RECORD")
  done

  lcl_MOUNT_POINTS_STRING=",\"mountPoints\": ["
  
  lcl_RECORD_NUMBER=0
  for SINGLE_RECORD in ${VOLUME_MOUNT_ARRAY[@]}; do
    lcl_RECORD_NUMBER=$((lcl_RECORD_NUMBER + 1))
    lcl_VOLUME_NAME="$(cut -d: -f1 <<< ${SINGLE_RECORD})"
    lcl_DESTINATION_MOUNT_FOLDER="$(cut -d: -f3 <<< ${SINGLE_RECORD})"
    lcl_READ_ONLY_MOUNT="$(cut -d: -f4 <<< ${SINGLE_RECORD})"
    #Yeah, I know it looks stupid. I just wanted to make the parameter more verbose, and decided to reuse the variable afterwards
    if [[ ${lcl_READ_ONLY_MOUNT} == "read_only_true" ]]; then
      lcl_READ_ONLY_MOUNT="true"
    else
      lcl_READ_ONLY_MOUNT="false"
    fi
      lcl_MOUNT_POINTS_STRING="${lcl_MOUNT_POINTS_STRING} { \"sourceVolume\": \"${lcl_VOLUME_NAME}\",  \"containerPath\": \"${lcl_DESTINATION_MOUNT_FOLDER}\", \"readOnly\": ${lcl_READ_ONLY_MOUNT} }"
    if [[ ${lcl_RECORD_NUMBER} != ${#lcl_VOLUME_MOUNT_ARRAY[@]} ]]; then
      lcl_MOUNT_POINTS_STRING="${lcl_MOUNT_POINTS_STRING}, "
    fi
  done
  lcl_MOUNT_POINTS_STRING="${lcl_MOUNT_POINTS_STRING} ]"
  echo "${lcl_MOUNT_POINTS_STRING}"
}

volumes=$(define_volumes ${VOLUME_MOUNTS})
volume_mounts=$(mount_points_def ${VOLUME_MOUNTS})

#We want to be able to add or remove this section dynamically
make_task_definition(){
  if [[ "${ARGS[--skip-setting-up-port-mapping-to-host]}" == "true" ]]; then
    task_ports_section=""
  else
    task_ports_section=",
    \"portMappings\": [
      {
        \"containerPort\": 8080,
        \"hostPort\": ${ARGS[--port1]}
      },
      {
        \"containerPort\": 8081,
        \"hostPort\": ${ARGS[--port2]}
      }
    ]"
  fi
  
  task_def="[
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
        \"name\": \"environment\",
        \"value\": \"${ARGS[--environment]}\"
      },
      {
        \"name\": \"suffix\",
        \"value\": \"${ARGS[--suffix]}\"
      },
      {
        \"name\": \"service_name\",
        \"value\":\"${ARGS[--ecs_service]}\"
      }
      ]${volume_mounts}${task_ports_section}
    }
  ]"
}

#volume_mount_def(){
#    volume_mount='[
#        {
#            "name": "ecs-logs",
#            "host": {
#                "sourcePath": "/mnt/ebs/logs/"
#            }
#        },
#        {
#            "name": "ecs-data",
#            "host": {
#                "sourcePath": "/mnt/ebs/data/"
#            }
#        }
#    ]'
#
#    volumes=$(printf "$volume_mount")
#}

register_task_definition() {
    echo "Registering task definition ${task_def}"
    if revision=$(aws ecs register-task-definition \
            --volumes $volumes \
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

    volumes=$(define_volumes ${VOLUME_MOUNTS})
    volume_mounts=$(mount_points_def ${VOLUME_MOUNTS})
    make_task_definition
    #placement_constraint_def

#
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
