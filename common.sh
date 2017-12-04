#!/usr/bin/env bash
#
# Common functions
unset ERROR #
declare -A ARGS

error() {
  echo -e "\e[31mERROR: $1\e[0m"
  ERROR=$2
}

errorAndExit() {
  echo -e "\e[31mERROR: $1\e[0m"
  exit $2
}

info() {
  echo -e "\e[34mINFO: ${1}\e[0m"
}

printCliArgs() {
  for each in "${!ARGS[@]}"
  do
    echo "ARGS[${each}]=${ARGS[${each}]}"
  done
}

processCliArgs() {
  #  Reads arguments into associative array ARGS[]
  #  Key-Value argument such as --myarg="argvalue" adds an element ARGS[--myarg]="argvalue"
  #
  #  USAGE: processCliArgs $*
  for each in $*; do
    if [[ "$(echo ${each} | grep '=' >/dev/null ; echo $?)" == "0" ]]; then
      key=$(echo ${each} | cut -d '=' -f 1)
      value=$(echo ${each} | cut -d '=' -f 2)
      if [[ "${ARGS[--debug]}" ]]; then
        if [[ "${key}" =~ "key" ]]; then
          info "Processing Key-Value argument ${key}=${value:0:4}********************"
        else
          info "Processing Key-Value argument ${key}=${value}"
        fi
      fi
      ARGS[${key}]="${value}"
    else
      errorAndExit "Argument must contain = character as in --key=value"
    fi
  done
}

warn() {
  echo -e "\e[33mWARNING: ${1}\e[0m"
}