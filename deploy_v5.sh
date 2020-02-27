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
#  --aws_role="FTApplicationRoleFor_passtool" \
#  --volume-mounts="ecs-logs:/mnt/source1:/mount/destination1/:read_only_true;ecs-data:/mnt/source2:/mnt/destination2/:read_only_false" \
#  --structured-logging="false" \
#  --splunk_index_prefix="data_" \
#  --hard-cpu-limit=256

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
  --aws_role
)

#Deliberately fail if a required variable is empty
for VARIABLE_NAME in ${VARIABLES_THAT_SHOULD_NOT_BE_EMPTY[@]}; do
  if [ -z ${ARGS[${VARIABLE_NAME}]} ]; then
    echo "Required parameter \"${VARIABLE_NAME}\" is not set. Exitting"
    exit 1
  fi
done

#ULIMITS_SNIPPETS=()

# more bash-friendly output for jq
JQ="jq --raw-output --exit-status"

install_aws_cli() {
  pip install --upgrade pip
  pip install --upgrade awscli
  sudo apt-get install jq
}

# Check whether to install aws clis
which aws &>/dev/null || install_aws_cli

aws configure set default.region ${ARGS[--aws_region]}

if [ "${ARGS[--structured-logging]}" == "true" ]; then
  SPLUNK_FORMAT="raw"
  CONTAINER_ID_STRING='"tag": "containerId=\"{{.ID}}\"",'
else
  SPLUNK_FORMAT="json"
  CONTAINER_ID_STRING=""
fi

VOLUME_MOUNTS=${ARGS[--volume-mounts]}

for SINGLE_RECORD in $(tr \; \  <<< ${VOLUME_MOUNTS}) ; do
  VOLUME_MOUNT_ARRAY+=("$SINGLE_RECORD")
done

#Build the ulimits snipped if the appropriate trigger has been passed to the script
if [ ! -z "${ARGS[--hard-cpu-limit]}" ]; then
  #Make the separator to newline, which makes it possible to add strings that contain spaces as a single array element
  IFS=$'\n'
  #Builds a limit string that will go in the ECS task definition for the CPU limit
  ULIMITS_CPU_HARD_LIMIT=("{ \"Name\": \"cpu\", \"Soft\": ${ARGS[--hard-cpu-limit]}, \"Hard\": ${ARGS[--hard-cpu-limit]} }")
  #Append this particular string to an array that contains all limits, which will be used to build the final limits string
  ULIMITS_SNIPPLETS+=("${ULIMITS_CPU_HARD_LIMIT}")
  unset IFS
fi

#Start building the limits string if any limits have been specified
if [ "${#ULIMITS_SNIPPLETS[@]}" -gt 0 ]; then
  IFS=$'\n'
  CURRENT_ELEMENT=0
  ULIMITS_STRING+=$'"ulimits": [\n'
  for LIMIT in ${ULIMITS_SNIPPLETS[@]}; do
    CURRENT_ELEMENT=$((CURRENT_ELEMENT+1))
    ULIMITS_STRING+="        ${LIMIT}"
    if [ "${#ULIMITS_SNIPPLETS[@]}" != "${CURRENT_ELEMENT}" ]; then ULIMITS_STRING+=$',\n' ; fi
  done
  ULIMITS_STRING+=$'\n      ],'
  unset IFS
fi
##End of ulimits string generation section

define_volumes() {
  local lcl_VOLUME_MOUNTS=${1}
  local lcl_VOLUME_MOUNT_ARRAY=()
  local lcl_RECORD_NUMBER=""
  local lcl_SOURCE_MOUNT_FOLDER=""
  local lcl_VOLUME_NAME=""
  local lcl_VOLUME_MOUNT_STRING=""    

  for SINGLE_RECORD in $(tr \; \  <<< ${lcl_VOLUME_MOUNTS}) ; do
    #Only get the volume definining part of the string, so the logic determining uniqueness works
    SINGLE_RECORD=$(cut -d: -f1-2 <<< $SINGLE_RECORD)
    lcl_VOLUME_MOUNT_ARRAY+=("$SINGLE_RECORD")
  done
  #This should delete the duplicates from the array. Just make sure you dont have whitespace in the volumes string.
  lcl_VOLUME_MOUNT_ARRAY=($(echo ${lcl_VOLUME_MOUNT_ARRAY[@]} | tr " " "\n" | sort -u))

  #Start building up the string with the volumes definition
  lcl_VOLUME_MOUNT_STRING="["
  
  lcl_RECORD_NUMBER=0
  for SINGLE_RECORD in ${lcl_VOLUME_MOUNT_ARRAY[@]}; do
    lcl_RECORD_NUMBER=$((lcl_RECORD_NUMBER + 1))
    lcl_SOURCE_MOUNT_FOLDER="$(cut -d: -f2 <<< ${SINGLE_RECORD})"
    lcl_VOLUME_NAME="$(cut -d: -f1 <<< ${SINGLE_RECORD})"
    #Add an entry for each defined folume
    lcl_VOLUME_MOUNT_STRING="${lcl_VOLUME_MOUNT_STRING} {\"name\": \"${lcl_VOLUME_NAME}\", \"host\": { \"sourcePath\": \"${lcl_SOURCE_MOUNT_FOLDER}\" }    }"
    #Check whether this is the last element of the array to decide whether to put a comma
    if [[ ${lcl_RECORD_NUMBER} != ${#lcl_VOLUME_MOUNT_ARRAY[@]} ]]; then
      lcl_VOLUME_MOUNT_STRING="${lcl_VOLUME_MOUNT_STRING}, "
    fi
  done

  #If no volumes were defined output an empty value
  lcl_VOLUME_MOUNT_STRING="${lcl_VOLUME_MOUNT_STRING} ]"
  if [[ ${lcl_RECORD_NUMBER} != 0 ]]; then
    echo "${lcl_VOLUME_MOUNT_STRING}"
  else
    echo ""
  fi
}


mount_points_def(){
  local lcl_VOLUME_MOUNTS=${1}
  local lcl_VOLUME_MOUNT_ARRAY=()
  local lcl_RECORD_NUMBER=""
  local lcl_VOLUME_NAME=""
  local lcl_DESTINATION_MOUNT_FOLDER=""
  local lcl_READ_ONLY_MOUNT=""

  local lcl_VOLUME_MOUNT_STRING=""    

  for SINGLE_RECORD in $(tr \; \  <<< ${lcl_VOLUME_MOUNTS}) ; do
    lcl_VOLUME_MOUNT_ARRAY+=("$SINGLE_RECORD")
  done
  #This should delete the duplicates from the array. Just make sure you dont have whitespace in the volumes string
  lcl_VOLUME_MOUNT_ARRAY=($(echo ${lcl_VOLUME_MOUNT_ARRAY[@]} | tr " " "\n" | sort -u))

  #Start building up the mount points string
  lcl_MOUNT_POINTS_STRING=",\"mountPoints\": ["
  
  lcl_RECORD_NUMBER=0
  for SINGLE_RECORD in ${lcl_VOLUME_MOUNT_ARRAY[@]}; do
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
    #Add a comma only if this is not the last element
    if [[ ${lcl_RECORD_NUMBER} != ${#lcl_VOLUME_MOUNT_ARRAY[@]} ]]; then
      lcl_MOUNT_POINTS_STRING="${lcl_MOUNT_POINTS_STRING}, "
    fi
  done
  
  #Output an empty string if no mount folders were defined
  lcl_MOUNT_POINTS_STRING="${lcl_MOUNT_POINTS_STRING} ]"
  if [[ ${lcl_RECORD_NUMBER} != 0 ]]; then
    echo "${lcl_MOUNT_POINTS_STRING}"
  else
    echo ""
  fi
}

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

  DEFAULT_SPLUNK_INDEX_PREFIX="data_"
  SPLUNK_INDEX_PREFIX=${ARGS[--splunk_index_prefix]:=$DEFAULT_SPLUNK_INDEX_PREFIX}

  task_def="[
    {
      \"name\": \"${ARGS[--ecs_service]}-${ARGS[--suffix]}-${ARGS[--colour]}\",
      \"image\": \"${ARGS[--aws_account_id]}.dkr.ecr.eu-west-1.amazonaws.com/${ARGS[--image_name]}:${ARGS[--image_version]}\",
      \"essential\": true,
      \"memory\": ${ARGS[--memory]},
      \"cpu\": ${ARGS[--cpu]},
      ${ULIMITS_STRING}
      \"logConfiguration\": {
        \"logDriver\": \"splunk\",
        \"options\": {
          \"splunk-url\": \"https://http-inputs-financialtimes.splunkcloud.com\",
          \"splunk-token\": \"${ARGS[--splunk]}\",
          \"splunk-index\": \"${SPLUNK_INDEX_PREFIX}${ARGS[--environment]}\",
          \"splunk-source\": \"${ARGS[--ecs_service]}\",
          \"splunk-insecureskipverify\": \"true\",
          ${CONTAINER_ID_STRING}
          \"splunk-format\": \"${SPLUNK_FORMAT}\"
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

register_task_definition() {
    #If there is someting in $volumes set this variable to "--volumes $volumes" otherwise leave it completely empty as there will be no value for the --volumes parameter
    local lcl_VOLUMES_SWITCH=${volumes:+"--volumes"}
    echo "Registering task definition ${task_def}"
    if revision=$(aws ecs register-task-definition \
            ${lcl_VOLUMES_SWITCH} "${volumes}"\
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

deploy_cluster() {

    family="${ARGS[--ecs_service]}-${ARGS[--suffix]}-${ARGS[--colour]}-task-family"
    echo "Family name is ${family}"
    task_role_arn="arn:aws:iam::${ARGS[--aws_account_id]}:role/${ARGS[--aws_role]}"
    echo "Task role is: ${task_role_arn}"

    volumes="$(define_volumes ${VOLUME_MOUNTS})"
    volume_mounts="$(mount_points_def ${VOLUME_MOUNTS})"

    make_task_definition
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
