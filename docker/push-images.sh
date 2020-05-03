#!/bin/bash

IMAGES=( web redis )
DOCKER_PREFIX=$1
IMAGE_TAG=`git rev-parse --short HEAD`

for image in "${IMAGES[@]}"
do
  echo "Building $image image..."
  DOCKERHUB_PATH="${DOCKER_PREFIX}_${image}"
  docker build -f ./docker/$image.dockerfile -t $DOCKERHUB_PATH:$IMAGE_TAG .

  echo "Tagging $image latest image..."
  IMAGE_ID=`docker images | grep $DOCKERHUB_PATH | head -n1 | awk '{print $3}'`
  docker tag ${IMAGE_ID} $DOCKERHUB_PATH:latest

  echo "Pushing $image image to Docker..."
  docker push $DOCKERHUB_PATH:$IMAGE_TAG
  docker push $DOCKERHUB_PATH:latest

  echo "Done!"
done
