#!/bin/sh
set -e

DOCKER_VERSION=`docker --version`

if [ "$?" -ne "0" ]; then
  echo "Please install Docker before proceeding."
  exit 1
fi

DOCKER_COMPOSE_COMMAND="docker compose"
if ! $DOCKER_COMPOSE_COMMAND > /dev/null 2>&1; then
  DOCKER_COMPOSE_COMMAND="docker-compose"
fi

printUsage() {
  cat <<EOF
usage: $(basename $0) [command]
where [command] can be:
  help       Shows this help message.
  cleanup    Removes ALL data for a clean environment.
  logs       Prints logs from all running services.
  setup      Initializes the default configuration files.
  start      Starts the Standard Notes infrastructure.
  status     Prints the status of services (name, command, state, ports).
  update     Pulls latest changes and updates images.
  version    Shows the current version of all containers.
EOF
}

checkConfigFiles() {
  if [ ! -f ".env" ]; then echo "Could not find syncing-server environment file. Please run the './server.sh setup' command and try again." && exit 1; fi
  if [ ! -f "docker/api-gateway.env" ]; then echo "Could not find api-gateway environment file. Please run the './server.sh setup' command and try again." && exit 1; fi
  if [ ! -f "docker/auth.env" ]; then echo "Could not find auth environment file. Please run the './server.sh setup' command and try again." && exit 1; fi
}

checkForConfigFileChanges() {
  checkConfigFiles
  compareLineCount
}

compareLineCount() {
  MAIN_ENV_FILE_SAMPLE_LINES=$(wc -l .env.sample | awk '{ print $1 }')
  MAIN_ENV_FILE_LINES=$(wc -l .env | awk '{ print $1 }')
  if [ "$MAIN_ENV_FILE_SAMPLE_LINES" -ne "$MAIN_ENV_FILE_LINES" ]; then echo "The .env file contains different amount of lines than .env.sample. This may be caused by the fact that there is a new environment variable to configure. Please update your environment file and try again." && exit 1; fi

  API_GATEWAY_ENV_FILE_SAMPLE_LINES=$(wc -l docker/api-gateway.env.sample | awk '{ print $1 }')
  API_GATEWAY_ENV_FILE_LINES=$(wc -l docker/api-gateway.env | awk '{ print $1 }')
  if [ "$API_GATEWAY_ENV_FILE_SAMPLE_LINES" -ne "$API_GATEWAY_ENV_FILE_LINES" ]; then echo "The docker/api-gateway.env file contains different amount of lines than docker/api-gateway.env.sample. This may be caused by the fact that there is a new environment variable to configure. Please update your environment file and try again." && exit 1; fi

  AUTH_ENV_FILE_SAMPLE_LINES=$(wc -l docker/auth.env.sample | awk '{ print $1 }')
  AUTH_ENV_FILE_LINES=$(wc -l docker/auth.env | awk '{ print $1 }')
  if [ "$AUTH_ENV_FILE_SAMPLE_LINES" -ne "$AUTH_ENV_FILE_LINES" ]; then echo "The docker/auth.env file contains different amount of lines than docker/auth.env.sample. This may be caused by the fact that there is a new environment variable to configure. Please update your environment file and try again." && exit 1; fi
}

COMMAND=$1 && shift 1

case "$COMMAND" in
  'setup' )
    echo "Initializing default configuration"
    if [ ! -f ".env" ]; then cp .env.sample .env; fi
    if [ ! -f "docker/api-gateway.env" ]; then cp docker/api-gateway.env.sample docker/api-gateway.env; fi
    if [ ! -f "docker/auth.env" ]; then cp docker/auth.env.sample docker/auth.env; fi
    echo "Default configuration files created as .env and docker/*.env files. Feel free to modify values if needed."
    ;;
  'start' )
    checkForConfigFileChanges
    echo "Starting up infrastructure"
    $DOCKER_COMPOSE_COMMAND up -d
    echo "Infrastructure started. Give it a moment to warm up. If you wish please run the './server.sh logs' command to see details."
    ;;
  'status' )
    echo "Services State:"
    $DOCKER_COMPOSE_COMMAND ps
    ;;
  'logs' )
    $DOCKER_COMPOSE_COMMAND logs -f
    ;;
  'update' )
    echo "Stopping all services."
    $DOCKER_COMPOSE_COMMAND kill || true
    echo "Pulling changes from Git."
    git pull origin $(git rev-parse --abbrev-ref HEAD)
    echo "Checking for env file changes"
    checkForConfigFileChanges
    echo "Downloading latest images of Standard Notes services."
    $DOCKER_COMPOSE_COMMAND pull
    echo "Images up to date. Starting all services."
    $DOCKER_COMPOSE_COMMAND up -d
    echo "Infrastructure started. Give it a moment to warm up. If you wish please run the './server.sh logs' command to see details."
    ;;
  'stop' )
    echo "Stopping all service"
    $DOCKER_COMPOSE_COMMAND kill
    echo "Services stopped"
    ;;
  'version' )
    $DOCKER_COMPOSE_COMMAND images
    ;;
  'cleanup' )
    echo "WARNING: This will permanently delete all of you data! Are you sure?"
    read -p "Continue (y/n)?" choice
    case "$choice" in
      y|Y )
        $DOCKER_COMPOSE_COMMAND kill && $DOCKER_COMPOSE_COMMAND rm -fv
        rm -rf data/mysql
        rm -rf data/redis
        echo "Cleanup performed. You can start your server with a clean environment."
        ;;
      n|N )
        echo "Cleanup aborted"
        exit 0
        ;;
      * )
        echo "Invalid option supplied. Aborted cleanup."
        ;;
    esac
    ;;
  'help' )
    printUsage
    exit 0
    ;;
  * )
    echo "Unknown command"
    printUsage
    ;;
esac

exec "$@"
