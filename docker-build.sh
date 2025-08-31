#!/bin/bash

# Script para construir y publicar imagen Docker de Cortex

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración
DOCKER_HUB_USER=${DOCKER_HUB_USER:-""}
IMAGE_NAME="cortex"
VERSION=$(grep 'version:' mix.exs | head -1 | awk -F'"' '{print $2}')
LATEST_TAG="latest"

print_header() {
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}🧠 Cortex Docker Build Script${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Mostrar header
print_header

# Función para construir imagen
build_image() {
    echo -e "${BLUE}Building Docker image...${NC}"
    echo "Version: $VERSION"
    echo ""
    
    if docker build -t $IMAGE_NAME:$VERSION -t $IMAGE_NAME:$LATEST_TAG .; then
        print_success "Image built successfully"
        echo ""
        echo "Images created:"
        echo "  - $IMAGE_NAME:$VERSION"
        echo "  - $IMAGE_NAME:$LATEST_TAG"
        return 0
    else
        print_error "Failed to build image"
        return 1
    fi
}

# Función para probar la imagen
test_image() {
    echo ""
    echo -e "${BLUE}Testing Docker image...${NC}"
    
    # Verificar si hay API keys en .env
    if [ -f .env ] && grep -q "API_KEYS" .env; then
        echo "Using .env file for testing"
        docker run --rm -d \
            --name cortex-test \
            --env-file .env \
            -p 4000:4000 \
            $IMAGE_NAME:$LATEST_TAG
    else
        print_warning "No .env file found, using dummy key for test"
        docker run --rm -d \
            --name cortex-test \
            -e GROQ_API_KEYS=test_key \
            -p 4000:4000 \
            $IMAGE_NAME:$LATEST_TAG
    fi
    
    echo "Waiting for container to start..."
    sleep 5
    
    # Verificar health
    if curl -s http://localhost:4000/api/health > /dev/null 2>&1; then
        print_success "Container is healthy"
        docker stop cortex-test > /dev/null 2>&1
        return 0
    else
        print_error "Container health check failed"
        docker stop cortex-test > /dev/null 2>&1
        return 1
    fi
}

# Función para publicar en Docker Hub
publish_image() {
    echo ""
    echo -e "${BLUE}Publishing to Docker Hub...${NC}"
    
    if [ -z "$DOCKER_HUB_USER" ]; then
        print_warning "DOCKER_HUB_USER not set. Skipping publish."
        echo "To publish, run:"
        echo "  export DOCKER_HUB_USER=your-username"
        echo "  ./docker-build.sh --publish"
        return 0
    fi
    
    # Tag para Docker Hub
    docker tag $IMAGE_NAME:$VERSION $DOCKER_HUB_USER/$IMAGE_NAME:$VERSION
    docker tag $IMAGE_NAME:$LATEST_TAG $DOCKER_HUB_USER/$IMAGE_NAME:$LATEST_TAG
    
    # Push
    echo "Pushing $DOCKER_HUB_USER/$IMAGE_NAME:$VERSION..."
    docker push $DOCKER_HUB_USER/$IMAGE_NAME:$VERSION
    
    echo "Pushing $DOCKER_HUB_USER/$IMAGE_NAME:$LATEST_TAG..."
    docker push $DOCKER_HUB_USER/$IMAGE_NAME:$LATEST_TAG
    
    print_success "Images published to Docker Hub"
    echo ""
    echo "Pull commands:"
    echo "  docker pull $DOCKER_HUB_USER/$IMAGE_NAME:$VERSION"
    echo "  docker pull $DOCKER_HUB_USER/$IMAGE_NAME:$LATEST_TAG"
}

# Función para mostrar uso
show_usage() {
    echo ""
    echo "Usage: ./docker-build.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --build       Build Docker image only"
    echo "  --test        Build and test image"
    echo "  --publish     Build, test and publish to Docker Hub"
    echo "  --help        Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  DOCKER_HUB_USER   Your Docker Hub username (for publishing)"
    echo ""
    echo "Examples:"
    echo "  ./docker-build.sh --build"
    echo "  ./docker-build.sh --test"
    echo "  DOCKER_HUB_USER=myuser ./docker-build.sh --publish"
}

# Parsear argumentos
case "$1" in
    --build)
        build_image
        ;;
    --test)
        build_image && test_image
        ;;
    --publish)
        build_image && test_image && publish_image
        ;;
    --help)
        show_usage
        ;;
    *)
        # Por defecto, construir y probar
        build_image && test_image
        ;;
esac

echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${GREEN}Done!${NC}"
echo -e "${BLUE}=====================================${NC}"