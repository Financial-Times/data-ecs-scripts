#!/bin/bash 
function usage() {
    echo "CLUSTER must be set to desired ecs-cluster"
    echo "TASK_DEF must be set to desired task-definition:revision number"
    echo "Example:"
    echo "$ CLUSTER=data-platform-ecs-cluster-green TASK_DEF=hello-world-task:6 ./run_task_and_await_result.sh"
    exit 1
}

#check requirements
function require {
    command -v $1 > /dev/null 2>&1 || {
        echo "Some of the required software is not installed:"
        echo "    please install $1" >&2;
        exit 1;
    }
}

require aws
require jq

if [[ -z "$CLUSTER" ]]; then
    usage
fi

if [[ -z "$TASK_DEF" ]]; then
    usage
fi

TASK_ARN=$(aws ecs run-task --cluster $CLUSTER --task-definition $TASK_DEF | jq -r .tasks[0].containers[0].taskArn)
echo "TASK_ARN is $TASK_ARN"

function wait_for_result { 
    while [[ "$TASK_STATUS" != "STOPPED" ]]; do 
        sleep 3
        TASK_JSON=$(aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARN)
        TASK_STATUS=$(jq -r .tasks[0].containers[0].lastStatus <<< $TASK_JSON)
        echo "Current task status is $TASK_STATUS"
    done

    TASK_EXIT_CODE=$(jq -r .tasks[0].containers[0].exitCode <<< $TASK_JSON)
    echo "Task staus eventually reached $TASK_STATUS"
}

wait_for_result

echo "Exit code for container $(jq .tasks[0].containers[0].name <<< $TASK_JSON) was $TASK_EXIT_CODE"
echo "Exiting with code $TASK_EXIT_CODE"
exit $TASK_EXIT_CODE
