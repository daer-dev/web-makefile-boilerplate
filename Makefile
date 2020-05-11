SHELL:=/bin/bash

#############################
# GENERIC MAKEFILE COMMANDS #
#############################

.DEFAULT_GOAL:=help

.PHONY: help

check-var-%: ## Checks if a variable exists (using it like "| check-var-VAR_NAME").
	@: $(if $(value $*),,$(error $* is undefined))

help:  ## Displays this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

##########
# DOCKER #
##########

.PHONY: install install-dev start start-dev prune conn web docker-push-images

ENV_FILE?=.env.example
DOCKER_COMPOSE_OPTIONS?=-f docker-compose.yml
DOCKER_COMPOSE_OPTIONS_DEV=-f docker-compose.yml -f docker-compose.dev.yml

# Remove the entrypoint part if it doesn't apply to your project (it is forced to not throw an error if the file doesn't exists anyway).
install: ## Builds the enviroment with the settings specified in the env var "ENV_FILE" and options in "DOCKER_COMPOSE_OPTIONS".
	$(info Building environment with vars defined in "$(ENV_FILE)" and "$(DOCKER_COMPOSE_OPTIONS)" options...)
	@chmod 777 ./docker/entrypoint.sh  || true && \
		cp -f $(ENV_FILE) .env && \
		docker-compose $(DOCKER_COMPOSE_OPTIONS) build

# To be used only if you have a development specific config.
install-dev:  ## Builds the development enviroment.
	@ENV_FILE=.env.dev.example DOCKER_COMPOSE_OPTIONS="$(DOCKER_COMPOSE_OPTIONS_DEV)" make install

start:| check-var-DOCKER_COMPOSE_OPTIONS ## Starts the server with Docker.
	$(info Starting server...)
	@docker-compose $(DOCKER_COMPOSE_OPTIONS) up

start-dev:  ## Builds the development enviroment.
	@DOCKER_COMPOSE_OPTIONS="$(DOCKER_COMPOSE_OPTIONS_DEV)" make start

# Write your project name in the label filter to avoid deleting other projects' files by mistake.
prune: ## Deletes all Docker's containers, networks, volumes, images and cache with the label specified in the env var "LABEL".
	$(info Removing all Docker related info...)
	@docker system prune -af --volumes --filter label=your_project_name

conn:| check-var-CONTAINER_NAME check-var-DOCKER_COMPOSE_OPTIONS ## Connects to the container specified in the environment var "CONTAINER_NAME".
	$(info Connecting to "$(CONTAINER_NAME)" container...)
	@docker-compose $(DOCKER_COMPOSE_OPTIONS_DEV) run --no-deps --rm $(CONTAINER_NAME) bash -l

web:  ## Connects to the web container.
	@CONTAINER_NAME=web make conn

# Edit the executable file to specify the route of your images.
docker-push-images:| check-var-DOCKERHUB_PREFIX ## Pushes both Redis and Web images to DockerHub. The "DOCKERHUB_PREFIX" arg should be in "user_in_dockerhub/any_prefix-" format.
	$(info Pushing web & redis images to DockerHub...)
	@./docker/push-images.sh $(DOCKERHUB_PREFIX)

##########
# HEROKU #
##########

.PHONY: heroku-login heroku-create-app heroku-send-vars heroku-push heroku-deploy heroku-restart heroku-open heroku-log heroku-bash heroku-vars

heroku-login: ## Identifies the user into Heroku.
	$(info Connecting to Heroku...)
	@heroku login; heroku container:login

heroku-create-app:| check-var-HEROKU_PROJECT_NAME ## [OPTIONAL] App creation. Only needed the first time and if you don't have the project created yet.
	$(info Running tests...)
	@heroku create -a $(HEROKU_PROJECT_NAME)

heroku-send-vars:| check-var-HEROKU_PROJECT_NAME ## Sends environment variables to Heroku.
	$(info Sending environment variables to Heroku...)
	@export $(grep -v '^#' .env) && \
		heroku config:set $(grep -v '^#' .env) -a $(HEROKU_PROJECT_NAME)

heroku-push:| check-var-HEROKU_PROJECT_NAME ## Pushes container changes to the remote one.
	$(info Pushing changes to Heroku...)
	@heroku container:push --recursive -a $(HEROKU_PROJECT_NAME)

heroku-deploy:| check-var-HEROKU_PROJECT_NAME ## Deploys the latest changes to the production environment.
	$(info Deploying changes to Heroku...)
	@heroku container:release web -a $(HEROKU_PROJECT_NAME)

heroku-restart:| check-var-HEROKU_PROJECT_NAME ## Restarts the app.
	$(info Restarting app...)
	@heroku restart -a $(HEROKU_PROJECT_NAME)

heroku-open:| check-var-HEROKU_PROJECT_NAME ## Opens the app in a browser.
	$(info Opening app...)
	@heroku open -a $(HEROKU_PROJECT_NAME)

heroku-log:| check-var-HEROKU_PROJECT_NAME ## Shows the production log tail of the the production environment.
	$(info Opening log...)
	@heroku logs --tail -a $(HEROKU_PROJECT_NAME)

heroku-bash:| check-var-HEROKU_PROJECT_NAME ## Connects to the production server's terminal.
	$(info Connecting and opening bash...)
	@heroku run bash -a $(HEROKU_PROJECT_NAME)

heroku-vars:| check-var-HEROKU_PROJECT_NAME ## Returns the value of every environment var available.
	$(info Opening log...)
	@heroku config -a $(HEROKU_PROJECT_NAME)

##############
# KUBERNETES #
##############

.PHONY: k8s-start k8s-create k8s-create-secrets k8s-setup

k8s-start: ## Starts Minikube with Docker.
	$(info Starting Minikube...)
	@minikube start --driver=docker

k8s-create: ## Creates all the Kubernetes objects related to the project.
	$(info Creating Kubernetes objects...)
	@kubectl create -f k8s/web/* -f k8s/postgres/* -f ./k8s/redis/* -f ./k8s/sidekiq/* -f ./k8s/cable/*

k8s-create-secrets: ## Creates Kubernetes secrets with the content of the ".env" file.
	$(info Creating Kubernetes secrets from ".env" file...)
	@kubectl create secret generic secrets --from-env-file=.env

k8s-setup: k8s-start k8s-create k8s-create-secrets ## Starts Minikube and creates Kubernetes objects and secrets.

#################
# RUBY ON RAILS #
#################

.PHONY: rails-gems rails-test-setup rails-test

rails-gems:  ## Checks and installs new gems.
	$(info Checking and installing gems...)
	@docker-compose run --rm web bundle check || bundle install

rails-test-setup: install ## Installs and prepares the test suite environment.
	$(info Setting up the test environment...)
	@docker-compose run --rm web bundle exec rails db:drop db:create db:migrate RAILS_ENV=test

rails-test: ## Starts the test runner.
	$(info Running tests...)
	@docker-compose run --rm web bin/rspec

###########
# PHOENIX #
###########

.PHONY: phoenix-test

phoenix-test: ## Starts the test runner.
	$(info Running tests...)
	@docker-compose run web mix test

#################
# NODEJS #
#################

.PHONY: node-npm

node-npm:  ## Checks and install new NPM packages.
	$(info Checking and installing NPM packages...)
	@docker-compose run --rm web npm install
