#!/bin/bash

START_TIME=$(date +%s)
TIMEOUT_DURATION=1800 #30 minutes
TIMEOUT_TIME=$(($START_TIME+$TIMEOUT_DURATION))
POLL_INTERVAL_SECONDS=30

function usage() {
    echo "CLUSTER must be set to desired ecs-cluster"
    echo "TASK_DEF must be set to desired task-definition:revision number"
    echo "Example:"
    echo "$ CLUSTER=data-platform-ecs-cluster-green TASK_DEF=hello-world-task:6 ./run_task_and_await_result.sh"
    exit 1
}

function require {
    command -v $1 > /dev/null 2>&1 || {
        echo "Some of the required software is not installed:"
        echo "    please install $1" >&2;
        exit 1;
    }
}

function timeout {
    echo "Timed out while waiting for $TASK_DEF to finish after $TIMEOUT_DURATION seconds"
    exit 1
}

#Check tools are installed
require aws
require jq

#Check correct variables are set
if [[ -z "$CLUSTER" ]] || [[ -z "$TASK_DEF" ]]; then
    usage
fi

#Run the ecs-task and extract the ARN
TASK_ARN=$(aws ecs run-task --cluster $CLUSTER --task-definition $TASK_DEF | jq -r .tasks[0].containers[0].taskArn)
echo "TASK_ARN is $TASK_ARN"

#Wait for ecs task to finish and obtain result
while [[ "$TASK_STATUS" != "STOPPED" ]]; do
    if [[ $(date +%s) -gt $TIMEOUT_TIME ]]; then
        timeout
    fi

    sleep $POLL_INTERVAL_SECONDS
    TASK_JSON=$(aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARN)
    TASK_STATUS=$(jq -r .tasks[0].containers[0].lastStatus <<< $TASK_JSON)
    echo "`date`: Current task status is $TASK_STATUS"
done

TASK_EXIT_CODE=$(jq -r .tasks[0].containers[0].exitCode <<< $TASK_JSON)
echo "Task status eventually reached $TASK_STATUS"

echo "Exit code for container $(jq .tasks[0].containers[0].name <<< $TASK_JSON) was $TASK_EXIT_CODE"
exit $TASK_EXIT_CODE
