#!/bin/sh

DOCKER_VERSION=`docker --version`

if [ "$?" -ne "0" ]; then
  echo "Please install Docker before proceeding."
  exit 1
fi

DOCKER_COMPOSE_COMMAND="docker compose"
if ! $DOCKER_COMPOSE_COMMAND > /dev/null 2>&1; then
  DOCKER_COMPOSE_COMMAND="docker-compose"
fi

checkConfigFiles() {
  if [ ! -f ".env" ]; then echo "Could not find syncing-server environment file. Please run the './server.sh setup' command and try again." && exit 1; fi
  if [ ! -f "docker/api-gateway.env" ]; then echo "Could not find api-gateway environment file. Please run the './server.sh setup' command and try again." && exit 1; fi
  if [ ! -f "docker/auth.env" ]; then echo "Could not find auth environment file. Please run the './server.sh setup' command and try again." && exit 1; fi
  if [ ! -f "docker/files.env" ]; then echo "Could not find file service environment file. Please run the './server.sh setup' command and try again." && exit 1; fi
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

  FILES_ENV_FILE_SAMPLE_LINES=$(wc -l docker/files.env.sample | awk '{ print $1 }')
  FILES_ENV_FILE_LINES=$(wc -l docker/files.env | awk '{ print $1 }')
  if [ "$FILES_ENV_FILE_SAMPLE_LINES" -ne "$FILES_ENV_FILE_LINES" ]; then echo "The docker/files.env file contains different amount of lines than docker/files.env.sample. This may be caused by the fact that there is a new environment variable to configure. Please update your environment file and try again." && exit 1; fi
}

function cleanup {
  local output_logs=$1
  if [ $output_logs == 1 ]
  then
    echo "Outputing last 100 lines of logs"
    $DOCKER_COMPOSE_COMMAND logs --tail=100
  fi
}

function waitForServices {
  attempt=0
  while [ $attempt -le 180 ]; do
      attempt=$(( $attempt + 1 ))
      echo "# Waiting for all services to be up (attempt: $attempt) ..."
      result=$($DOCKER_COMPOSE_COMMAND logs api-gateway)
      if grep -q 'Server started on port' <<< $result ; then
          sleep 2 # for warmup
          echo "# All services are up!"
          break
      fi
      sleep 2
  done
}

COMMAND=$1 && shift 1

case "$COMMAND" in
  'setup' )
    echo "Initializing default configuration"
    if [ ! -f ".env" ]; then cp .env.sample .env; fi
    if [ ! -f "docker/api-gateway.env" ]; then cp docker/api-gateway.env.sample docker/api-gateway.env; fi
    if [ ! -f "docker/auth.env" ]; then cp docker/auth.env.sample docker/auth.env; fi
    if [ ! -f "docker/files.env" ]; then cp docker/files.env.sample docker/files.env; fi
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
    $DOCKER_COMPOSE_COMMAND kill --remove-orphans || true
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
  'create-subscription' )
    EMAIL=$1
    if [[ "$EMAIL" = "" ]]; then
      echo "Please provide an email for the subscription."
      exit 1
    fi
    shift 1

    $DOCKER_COMPOSE_COMMAND exec db sh -c "MYSQL_PWD=\$MYSQL_ROOT_PASSWORD mysql \$MYSQL_DATABASE -e \
      'INSERT INTO user_roles (role_uuid , user_uuid) VALUES ((SELECT uuid FROM roles WHERE name=\"PRO_USER\" ORDER BY version DESC limit 1) ,(SELECT uuid FROM users WHERE email=\"$EMAIL\")) ON DUPLICATE KEY UPDATE role_uuid = VALUES(role_uuid);' \
    "

    $DOCKER_COMPOSE_COMMAND exec db sh -c "MYSQL_PWD=\$MYSQL_ROOT_PASSWORD mysql \$MYSQL_DATABASE -e \
      'INSERT INTO user_subscriptions SET uuid=UUID(), plan_name=\"PRO_PLAN\", ends_at=8640000000000000, created_at=0, updated_at=0, user_uuid=(SELECT uuid FROM users WHERE email=\"$EMAIL\"), subscription_id=1, subscription_type=\"regular\";' \
    "

    echo "Subscription successfully created. Please consider donating if you do not plan on purchasing a subscription."
    ;;
  'stop' )
    echo "Stopping all service"
    $DOCKER_COMPOSE_COMMAND kill --remove-orphans
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
        $DOCKER_COMPOSE_COMMAND kill --remove-orphans && $DOCKER_COMPOSE_COMMAND rm -fv
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
  'generate-keys' )
    sed -i "s/auth_jwt_secret/$(openssl rand -hex 32)/g" .env
    sed -i "s/legacy_jwt_secret/$(openssl rand -hex 32)/g" docker/auth.env
    sed -i "s/secret_key/$(openssl rand -hex 32)/g" docker/auth.env
    sed -i "s/server_key/$(openssl rand -hex 32)/g" docker/auth.env
    sed -i "s/secret/$(openssl rand -hex 32)/g" docker/auth.env
    ;;
  'test' )
    waitForServices

    echo "# Starting test suite ..."
    npx mocha-headless-chrome --timeout 1200000 -f http://localhost:9001/mocha/test.html
    test_result=$?

    cleanup $test_result

    if [[ $test_result == 0 ]]
    then
      exit 0
    else
      exit 1
    fi
    ;;
  * )
    echo "Unknown command"
    ;;
esac

exec "$@"
