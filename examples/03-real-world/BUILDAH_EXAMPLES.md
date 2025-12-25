# Buildah Pipeline Examples

Примеры использования `buildahBuildPush` job template для сборки и публикации контейнерных образов.

## Содержание

1. [Базовый пример](#базовый-пример)
2. [Несколько образов](#несколько-образов)
3. [Мульти-платформенная сборка](#мульти-платформенная-сборка)
4. [С тестированием](#с-тестированием)
5. [GitHub Container Registry](#github-container-registry)
6. [Docker Hub](#docker-hub)

## Базовый пример

Простая сборка и публикация одного образа:

```nix
{ nixactions }:

nixactions.mkWorkflow {
  name = "simple-build";
  
  jobs = nixactions.jobs.buildahBuildPush {
    executor = nixactions.executors.local;
    
    registry = "docker.io/myusername";
    
    images = [
      {
        name = "myapp";
        context = ".";
        tags = ["latest"];
      }
    ];
    
    # Отключаем push для тестирования
    pushOnSuccess = false;
  };
}
```

## Несколько образов

Сборка нескольких образов в одном пайплайне:

```nix
{ nixactions }:

nixactions.mkWorkflow {
  name = "multi-service";
  
  jobs = nixactions.jobs.buildahBuildPush {
    executor = nixactions.executors.local;
    
    registry = "docker.io/myusername";
    
    images = [
      {
        name = "api";
        context = "./services/api";
        dockerfile = "Dockerfile";
        tags = ["latest" "v1.0.0"];
      }
      {
        name = "worker";
        context = "./services/worker";
        dockerfile = "Dockerfile.prod";
        tags = ["latest" "v1.0.0"];
      }
      {
        name = "frontend";
        context = "./web";
        tags = ["latest"];
      }
    ];
    
    buildArgs = {
      BUILD_DATE = "2024-01-01";
      VERSION = "1.0.0";
    };
  };
}
```

## Мульти-платформенная сборка

Сборка для нескольких архитектур:

```nix
{ nixactions }:

nixactions.mkWorkflow {
  name = "multi-arch-build";
  
  jobs = nixactions.jobs.buildahBuildPush {
    executor = nixactions.executors.local;
    
    registry = "docker.io/myusername";
    
    images = [
      {
        name = "cross-platform-app";
        context = ".";
        tags = ["latest" "v1.0.0"];
        platforms = [
          "linux/amd64"
          "linux/arm64"
          "linux/arm/v7"
        ];
      }
    ];
    
    # Дополнительные аргументы buildah
    buildahExtraArgs = "--layers --cache-from docker.io/myusername/cross-platform-app:latest";
  };
}
```

**Примечание:** Для мульти-архитектурных сборок может потребоваться QEMU:

```bash
# На хост-системе
sudo apt-get install qemu-user-static
```

## С тестированием

Запуск тестов перед публикацией:

```nix
{ nixactions }:

nixactions.mkWorkflow {
  name = "test-and-push";
  
  jobs = nixactions.jobs.buildahBuildPush {
    executor = nixactions.executors.local;
    
    registry = "docker.io/myusername";
    
    images = [
      {
        name = "tested-app";
        context = ".";
        tags = ["latest" "test-${builtins.getEnv "BUILD_NUMBER"}"];
      }
    ];
    
    # Включаем тестирование
    runTests = true;
    
    # Кастомная команда тестирования
    testCommand = ''
      echo "Running tests for $IMAGE_REF"
      
      # Запускаем контейнер с тестами
      podman run --rm $IMAGE_REF npm test
      
      # Проверяем размер образа
      IMAGE_SIZE=$(podman image inspect $IMAGE_REF --format '{{.Size}}')
      MAX_SIZE=$((500 * 1024 * 1024))  # 500MB
      
      if [ $IMAGE_SIZE -gt $MAX_SIZE ]; then
        echo "Error: Image size $IMAGE_SIZE exceeds maximum $MAX_SIZE"
        exit 1
      fi
      
      echo "✓ All tests passed"
    '';
    
    # Публикуем только после успешных тестов
    pushOnSuccess = true;
  };
}
```

## GitHub Container Registry

Публикация в GitHub Container Registry:

```nix
{ nixactions }:

nixactions.mkWorkflow {
  name = "github-registry";
  
  jobs = nixactions.jobs.buildahBuildPush {
    executor = nixactions.executors.local;
    
    # GitHub Container Registry
    registry = "ghcr.io/myorg";
    
    images = [
      {
        name = "myapp";
        context = ".";
        tags = ["latest" "main"];
      }
    ];
    
    # Кастомные имена переменных окружения для GitHub
    registryUsername = "GITHUB_ACTOR";
    registryPassword = "GITHUB_TOKEN";
    
    pushOnSuccess = true;
    
    # Провайдеры секретов
    envProviders = [
      # Вариант 1: SOPS
      (nixactions.platform.envProviders.sops {
        file = ./secrets.sops.yaml;
      })
      
      # Вариант 2: Required env vars
      # (nixactions.platform.envProviders.required [
      #   "GITHUB_ACTOR"
      #   "GITHUB_TOKEN"
      # ])
    ];
  };
}
```

Создайте `secrets.sops.yaml`:

```yaml
GITHUB_ACTOR: your-username
GITHUB_TOKEN: ghp_your_token_here
```

Зашифруйте с помощью SOPS:

```bash
sops -e -i secrets.sops.yaml
```

## Docker Hub

Публикация в Docker Hub:

```nix
{ nixactions }:

nixactions.mkWorkflow {
  name = "dockerhub-push";
  
  jobs = nixactions.jobs.buildahBuildPush {
    executor = nixactions.executors.local;
    
    # Docker Hub
    registry = "docker.io/myusername";
    
    images = [
      {
        name = "myapp";
        context = ".";
        tags = [
          "latest"
          "1.0.0"
          "1.0"
          "1"
        ];
      }
    ];
    
    buildArgs = {
      NODE_VERSION = "20";
      BUILD_ENV = "production";
    };
    
    runTests = true;
    pushOnSuccess = true;
    
    # Сохраняем артефакты
    saveArtifacts = true;
    artifactName = "docker-images";
    
    # Провайдеры секретов
    envProviders = [
      (nixactions.platform.envProviders.required [
        "REGISTRY_USERNAME"  # Docker Hub username
        "REGISTRY_PASSWORD"  # Docker Hub token/password
      ])
    ];
  };
}
```

## Запуск примеров

### 1. Компиляция workflow

```bash
# Базовый пример
nix build .#buildah-pipeline

# Мульти-образ
nix build .#buildah-multi-image
```

### 2. Просмотр сгенерированного скрипта

```bash
cat result/bin/buildah-pipeline
```

### 3. Запуск локально

```bash
# Установите необходимые переменные окружения
export REGISTRY_USERNAME="myusername"
export REGISTRY_PASSWORD="mypassword"

# Запустите workflow
./result/bin/buildah-pipeline
```

### 4. Проверка результатов

```bash
# Список локальных образов
buildah images

# Или с podman
podman images

# Запуск образа
podman run --rm docker.io/myusername/myapp:latest
```

## Советы и трюки

### Кэширование слоев

Используйте `buildahExtraArgs` для оптимизации:

```nix
buildahExtraArgs = "--layers --cache-from ${registry}/${name}:latest";
```

### Rootless builds

Buildah поддерживает rootless режим по умолчанию:

```bash
# Настройка для rootless
buildah unshare cat /proc/self/uid_map
```

### Оптимизация образов

```nix
testCommand = ''
  # Проверка размера
  SIZE=$(podman image inspect $IMAGE_REF --format '{{.Size}}')
  echo "Image size: $SIZE bytes"
  
  # Проверка безопасности
  if podman image inspect $IMAGE_REF --format '{{.User}}' | grep -q '^root$'; then
    echo "Warning: Image runs as root"
  fi
'';
```

### Debug сборки

```nix
buildahExtraArgs = "--log-level debug";
```

## Интеграция с CI/CD

### Комбинирование с другими job'ами

```nix
{ nixactions }:

nixactions.mkWorkflow {
  name = "full-pipeline";
  
  jobs = {
    # Сначала тестируем код
    test = {
      executor = nixactions.executors.local;
      actions = [
        nixactions.actions.checkout
        (nixactions.actions.runCommand "npm test")
      ];
    };
    
    # Затем собираем контейнеры
  } // (nixactions.jobs.buildahBuildPush {
    executor = nixactions.executors.local;
    jobPrefix = "container-";
    
    registry = "docker.io/myusername";
    images = [{ name = "myapp"; }];
    
    # Зависим от успешных тестов
    # Это нужно добавить вручную:
  });
  
  # Вручную добавляем зависимость
  jobs = builtins.mapAttrs (name: job:
    if lib.hasPrefix "container-" name
    then job // { needs = job.needs or [] ++ ["test"]; }
    else job
  ) jobs;
}
```

## Устранение неполадок

### Buildah не найден

```bash
# Установка buildah в NixOS
nix-shell -p buildah

# Или в flake.nix добавьте buildah в devShell
```

### Ошибка аутентификации

Проверьте учетные данные:

```bash
echo $REGISTRY_PASSWORD | buildah login --username $REGISTRY_USERNAME --password-stdin docker.io
```

### Проблемы с хранилищем

```bash
# Очистка кэша buildah
buildah rm --all
buildah rmi --all

# Проверка хранилища
buildah info
```

## Дополнительные ресурсы

- [Buildah Documentation](https://buildah.io/)
- [Buildah Tutorial](https://github.com/containers/buildah/tree/main/docs/tutorials)
- [Rootless Containers](https://github.com/containers/buildah/blob/main/docs/tutorials/05-rootless-containers.md)
