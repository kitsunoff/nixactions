# Buildah Job Template - Summary

## Что создано

### 1. Job Template: `buildahBuildPush`
**Файл:** `lib/jobs/buildah-build-push.nix`

Полнофункциональный job template для сборки и публикации контейнерных образов с помощью buildah.

**Возможности:**
- ✅ Rootless контейнерная сборка (buildah)
- ✅ Поддержка нескольких образов в одном pipeline
- ✅ Мульти-платформенные сборки (linux/amd64, linux/arm64, etc.)
- ✅ Настраиваемые теги для образов
- ✅ Build arguments
- ✅ Опциональное тестирование образов
- ✅ Опциональная публикация в registry
- ✅ Сохранение образов как artifacts
- ✅ Аутентификация в registry (Docker Hub, GitHub CR, etc.)
- ✅ Настраиваемые переменные окружения
- ✅ Scoped job names (избегает конфликтов)

**Создаваемые jobs:**
- `{jobPrefix}build` - Сборка образов
- `{jobPrefix}test` - Тестирование (опционально)
- `{jobPrefix}push` - Публикация в registry (опционально)

### 2. Примеры использования

#### `examples/03-real-world/buildah-pipeline.nix`
Базовый пример с одним образом:
- Сборка demo-app
- Тестирование с podman/docker
- Публикация в Docker Hub
- Сохранение artifacts

#### `examples/03-real-world/buildah-multi-image.nix`
Продвинутый пример с несколькими образами:
- Сборка frontend и backend образов
- Различные теги для каждого образа
- Тестирование
- Без публикации (для локального тестирования)

### 3. Документация
**Файл:** `examples/03-real-world/BUILDAH_EXAMPLES.md`

Подробная документация с примерами:
- Базовая сборка
- Несколько образов
- Мульти-платформенная сборка
- Тестирование
- GitHub Container Registry
- Docker Hub
- Советы и трюки
- Устранение неполадок

### 4. Bugfix в `mk-workflow.nix`
**Проблема:** Workflow падал с ошибкой при использовании `lib.optionalAttrs` в job templates, когда условие было `false`.

**Решение:** Добавлена фильтрация пустых jobs:
```nix
nonEmptyJobs = lib.filterAttrs (name: job: 
  job != {} && (job.actions or null) != null
) jobs;
```

Это позволяет job templates использовать:
```nix
${pushJob} = lib.optionalAttrs pushOnSuccess {
  # job configuration
};
```

## Соответствие STYLE_GUIDE.md

✅ **Multi-Job Workflow Pattern** - Возвращает несколько jobs  
✅ **jobPrefix Parameter** - Scoped job names  
✅ **executor Required Parameter** - Executor как обязательный параметр  
✅ **Configurable Inputs/Outputs** - Настраиваемые artifact names  
✅ **Configurable Environment Variables** - Настраиваемые env var names  
✅ **Comprehensive Documentation** - Полная документация с примерами  
✅ **envProviders Configurable** - Пользователь управляет secrets  

## Использование

### Базовый пример
```nix
{ platform }:

platform.mkWorkflow {
  name = "container-build";
  
  jobs = platform.jobs.buildahBuildPush {
    executor = platform.executors.local;
    
    registry = "docker.io/myuser";
    images = [{ name = "myapp"; }];
    
    pushOnSuccess = true;
    
    envProviders = [
      (platform.envProviders.required [
        "REGISTRY_USERNAME"
        "REGISTRY_PASSWORD"
      ])
    ];
  };
}
```

### Сборка и запуск
```bash
# Сборка workflow
nix build .#example-buildah-pipeline

# Запуск
export REGISTRY_USERNAME="myuser"
export REGISTRY_PASSWORD="mytoken"
./result/bin/buildah-pipeline
```

## Преимущества buildah

1. **Rootless** - Не требует root прав
2. **Daemonless** - Не требует Docker daemon
3. **OCI-совместимость** - Создаёт OCI-совместимые образы
4. **Безопасность** - Лучшая изоляция и безопасность
5. **Nix-friendly** - Отлично работает в Nix окружении

## Дальнейшие улучшения

Возможные расширения:
- [ ] Поддержка multi-stage builds
- [ ] Интеграция с kaniko для Kubernetes
- [ ] Кэширование слоёв между сборками
- [ ] Подписывание образов (cosign)
- [ ] SBOM generation
- [ ] Vulnerability scanning

## Тестирование

Все примеры успешно собираются:
```bash
✓ nix build .#example-buildah-pipeline
✓ nix build .#example-buildah-multi-image
```

Сгенерированные scripts корректны и готовы к использованию.
