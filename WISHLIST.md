# NixActions Wishlist

Пожелания от пользователей и разработчиков для будущих версий.

---

## 🔥 Critical (Must-have для production)

### 1. **Retry Failed Jobs/Actions**
```nix
{
  actions = [{
    name = "flaky-test";
    bash = "npm test";
    retry = {
      max_attempts = 3;
      backoff = "exponential";  # 1s, 2s, 4s
    };
  }];
}
```

**Почему важно:**
- Сетевые запросы фейлятся (npm install, docker pull)
- Тесты могут быть flaky
- External API могут быть недоступны временно

**Альтернатива сейчас:**
```bash
bash = ''
  for i in {1..3}; do
    npm test && break
    sleep $((i * 2))
  done
''
```

---

### 2. **Timeout Support**
```nix
{
  jobs = {
    build = {
      timeout = "30m";  # Job timeout
      actions = [
        {
          bash = "npm run build";
          timeout = "10m";  # Action timeout
        }
      ];
    };
  };
}
```

**Почему важно:**
- Зависшие процессы блокируют CI
- Нужен контроль над временем выполнения
- Защита от infinite loops

**Сейчас:** Нет защиты от зависания.

---

### 3. **Cancellation Support**
```nix
{
  jobs = {
    cleanup = {
      condition = "cancelled()";
      actions = [{
        bash = "docker stop $CONTAINER_ID";
      }];
    };
  };
}
```

**Почему важно:**
- Ctrl+C должен корректно останавливать workflow
- Cleanup должен выполняться даже при отмене
- Graceful shutdown контейнеров/VMs

**Сейчас:** `cancelled()` есть в документации, но не реализовано.

---

### 4. **Structured Logging** ✅ IMPLEMENTED
```nix
{
  logging = {
    format = "structured";  # "structured", "simple", or "json"
    level = "info";         # "info" or "debug"
  };
}
```

```bash
# Structured format (default):
[2025-12-23T10:58:44.123Z] [workflow:ci] [job:test] [action:checkout] Starting
[2025-12-23T10:58:44.321Z] [workflow:ci] [job:test] [action:checkout] Cloning repository...
[2025-12-23T10:58:45.456Z] [workflow:ci] [job:test] [action:checkout] Completed (duration: 1.333s, exit: 0)

# JSON format:
{"timestamp":"2025-12-23T10:58:44.123Z","workflow":"ci","job":"test","action":"checkout","message":"Starting"}
{"timestamp":"2025-12-23T10:58:45.456Z","workflow":"ci","job":"test","action":"checkout","message":"Completed","duration_ms":1333,"exit_code":0}

# Simple format (legacy):
→ checkout
✓ Job succeeded
```

**Реализовано:**
- ✅ Три формата: structured (default), JSON, simple
- ✅ Timestamp с миллисекундами
- ✅ Время выполнения каждого action (duration)
- ✅ Exit code для каждого action
- ✅ Все stdout/stderr экшенов обёрнуты в структурированный формат
- ✅ Переменная окружения NIXACTIONS_LOG_FORMAT для runtime override

**Использование:**
```bash
# Structured logs (default)
nix run .#my-workflow

# JSON logs for parsing
NIXACTIONS_LOG_FORMAT=json nix run .#my-workflow | jq 'select(.event == "complete")'

# Simple logs (legacy)
NIXACTIONS_LOG_FORMAT=simple nix run .#my-workflow
```

---

### 5. **Better Error Messages**
```bash
# Сейчас:
error: cannot coerce null to a string: null

# Хочется:
Error in workflow 'ci', job 'test', action 'deploy':
  ✗ Action condition failed to evaluate
  ✗ Condition: [ "$BRANCH" = "main" ]
  ✗ Reason: Variable $BRANCH is not set
  
  Hint: Set BRANCH at workflow/job/action level:
    env = { BRANCH = "main"; };
  
  Or provide at runtime:
    BRANCH=main nix run .#ci
```

**Почему важно:**
- Nix ошибки cryptic для новичков
- Нужен контекст (workflow/job/action)
- Подсказки как исправить

---

## 🚀 High Priority (Сильно упростят жизнь)

### 6. **Job Outputs**
```nix
{
  jobs = {
    version = {
      outputs = {
        VERSION = "1.2.3";
        BUILD_ID = "${{ github.sha }}";
      };
      actions = [{
        bash = ''
          echo "VERSION=1.2.3" >> $GITHUB_OUTPUT
          echo "BUILD_ID=$(git rev-parse HEAD)" >> $GITHUB_OUTPUT
        '';
      }];
    };
    
    deploy = {
      needs = ["version"];
      actions = [{
        bash = ''
          # Use outputs from 'version' job
          echo "Deploying version: ${{ needs.version.outputs.VERSION }}"
          kubectl set image deployment/app app=myapp:${{ needs.version.outputs.VERSION }}
        '';
      }];
    };
  };
}
```

**Почему важно:**
- Передача данных между jobs (не только файлы)
- Вычисленные значения (version, commit hash, build ID)
- Условия на основе outputs: `if: needs.build.outputs.changed == 'true'`

**Альтернатива сейчас:** Только через artifacts (файлы).

---

### 7. **Matrix Builds**
```nix
{
  jobs = {
    test = {
      strategy = {
        matrix = {
          node = ["18" "20" "22"];
          os = ["ubuntu" "macos"];
        };
      };
      
      executor = platform.executors.oci { 
        image = "node:${{ matrix.node }}"; 
      };
      
      actions = [{
        bash = "npm test";
      }];
      
      # Creates 6 jobs:
      # test-node18-ubuntu, test-node18-macos,
      # test-node20-ubuntu, test-node20-macos,
      # test-node22-ubuntu, test-node22-macos
    };
  };
}
```

**Почему важно:**
- Тестирование на разных версиях (node, python, ruby)
- Cross-platform testing (linux, macos, windows)
- Параллельное выполнение комбинаций

**Альтернатива сейчас:** Дублировать jobs вручную.

---

### 8. **Secrets Masking in Logs**
```bash
# Сейчас:
→ Deploying with key: sk_live_123abc456def

# Хочется:
→ Deploying with key: ***
```

**Почему важно:**
- Утечка секретов в логах
- Compliance требования
- Безопасность

**Реализация:**
```nix
{
  secrets = ["API_KEY" "DB_PASSWORD"];
  # Автоматически mask в логах
}
```

---

### 9. **Caching**
```nix
{
  jobs = {
    test = {
      cache = {
        paths = ["node_modules" ".pytest_cache"];
        key = "deps-${{ hashFiles('package-lock.json') }}";
        restore-keys = ["deps-"];
      };
      
      actions = [
        {
          name = "restore-cache";
          # Автоматически восстанавливает из кэша
        }
        {
          bash = "npm install";
          # Только если кэш не найден
        }
        {
          name = "save-cache";
          # Автоматически сохраняет в кэш
        }
      ];
    };
  };
}
```

**Почему важно:**
- Ускорение CI (npm install, pip install)
- Экономия времени и трафика
- GitHub Actions cache - killer feature

**Альтернатива сейчас:** Artifacts (но они не кэшируются между runs).

---

### 10. **Reusable Workflows**
```nix
# lib/workflows/nodejs-ci.nix
{ pkgs, platform, nodeVersion ? "20" }:

platform.mkWorkflow {
  name = "nodejs-ci";
  jobs = {
    test = {
      executor = platform.executors.oci { image = "node:${nodeVersion}"; };
      actions = [
        { bash = "npm install"; }
        { bash = "npm test"; }
      ];
    };
  };
}

# my-project/ci.nix
{ pkgs, platform }:

import ../lib/workflows/nodejs-ci.nix {
  inherit pkgs platform;
  nodeVersion = "22";
}
```

**Почему важно:**
- DRY принцип
- Переиспользование workflows между проектами
- Композиция workflows

**Сейчас:** Работает через Nix imports, но нужна best practice документация.

---

## 💡 Nice to Have (Удобство)

### 11. **CLI Tool**
```bash
# Инициализация
$ nixactions init
Choose template:
  1. Node.js CI/CD
  2. Python CI/CD
  3. Rust CI/CD
  4. Docker Build
  5. Custom

# Валидация
$ nixactions validate
✓ Workflow 'ci' is valid
✓ All dependencies resolved
✗ Job 'deploy' has circular dependency

# Запуск
$ nixactions run ci
$ nixactions run ci --job=test
$ nixactions run ci --dry-run

# Список workflows
$ nixactions list
Available workflows:
  - ci (3 jobs, 12 actions)
  - deploy (2 jobs, 5 actions)
  - release (1 job, 3 actions)

# Граф зависимостей
$ nixactions graph ci
digraph G {
  test -> build;
  lint -> build;
  build -> deploy;
}

# Watch mode (для development)
$ nixactions watch ci
Watching for changes in flake.nix...
```

**Почему важно:**
- `nix run .#ci` многословно
- Нужна валидация без запуска
- Визуализация DAG

---

### 12. **Local Development Mode**
```bash
# Быстрый режим для development
$ nixactions dev ci

# Что делает:
# 1. Skip build-time checks (fast feedback)
# 2. Mount current directory (no copy)
# 3. Cache environment (reuse container)
# 4. Hot reload on changes
# 5. Interactive mode (можно войти в контейнер)

# Interactive mode
$ nixactions dev ci --interactive
→ Starting job 'test'
→ Container ready
$ docker exec -it $CONTAINER bash
```

**Почему важно:**
- CI должен быть быстрым в dev
- Edit → Test cycle должен быть мгновенным
- Debugging в контейнере

---

### 13. **Workflow Visualization**
```bash
$ nixactions graph ci --output ci.png
```

```
Level 0:
  ┌──────────┐  ┌──────────┐
  │   lint   │  │ validate │
  └─────┬────┘  └─────┬────┘
        │             │
        └──────┬──────┘
               │
Level 1:      ┌▼──────┐
              │  test │
              └───┬───┘
                  │
Level 2:      ┌───▼───┐
              │ build │
              └───┬───┘
                  │
Level 3:      ┌───▼────┐
              │ deploy │
              └────────┘
```

**Почему важно:**
- Понимание workflow сложно из кода
- Документация
- Onboarding новых разработчиков

---

### 14. **GitHub Actions Converter**
```bash
$ nixactions import .github/workflows/ci.yml > ci.nix

# .github/workflows/ci.yml
name: CI
on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm install
      - run: npm test

# →

# ci.nix
{ pkgs, platform }:

platform.mkWorkflow {
  name = "CI";
  
  jobs = {
    test = {
      executor = platform.executors.oci { image = "ubuntu:latest"; };
      actions = [
        platform.actions.checkout
        (platform.actions.setupNode { version = "20"; })
        { bash = "npm install"; }
        { bash = "npm test"; }
      ];
    };
  };
}
```

**Почему важно:**
- Миграция с GitHub Actions
- Снижает entry barrier
- Автоматическая конвертация

---

### 15. **Templates System**
```bash
$ nix flake init -t nixactions#nodejs
$ nix flake init -t nixactions#python
$ nix flake init -t nixactions#rust
$ nix flake init -t nixactions#docker-build
$ nix flake init -t nixactions#k8s-deploy

# Creates:
# - flake.nix with nixactions input
# - ci.nix with sensible defaults
# - .gitignore
# - README.md with instructions
```

**Почему важно:**
- Быстрый старт (5 минут → production-ready CI)
- Best practices из коробки
- Примеры для копирования

---

## 🎯 Advanced Features (Для power users)

### 16. **Parallel Actions in Job**
```nix
{
  jobs = {
    test = {
      actions = [
        # Sequential
        { bash = "npm install"; }
        
        # Parallel
        {
          parallel = [
            { bash = "npm run test:unit"; }
            { bash = "npm run test:integration"; }
            { bash = "npm run lint"; }
          ];
        }
        
        # Sequential again
        { bash = "npm run build"; }
      ];
    };
  };
}
```

**Почему важно:**
- Ускорение job execution
- Independent tasks в одном job

---

### 17. **Custom Executors Plugin System**
```nix
# ~/.config/nixactions/executors/my-cloud.nix
{ pkgs, lib, mkExecutor }:

{ region ? "us-east-1", instance_type ? "t3.micro" }:

mkExecutor {
  name = "my-cloud-${region}";
  
  setupWorkspace = { actionDerivations }: ''
    # Provision VM in cloud
    INSTANCE_ID=$(my-cloud create-instance \
      --region ${region} \
      --type ${instance_type})
    
    # Upload actions
    for action in ${toString actionDerivations}; do
      my-cloud upload $INSTANCE_ID $action
    done
  '';
  
  executeJob = { jobName, actionDerivations, env }: ''
    my-cloud exec $INSTANCE_ID -- bash -c '...'
  '';
  
  # ...
}

# Usage:
platform.executors.myCloud = import ~/.config/nixactions/executors/my-cloud.nix {
  inherit pkgs lib mkExecutor;
};
```

**Почему важно:**
- Кастомные cloud providers
- Специфичные execution environments
- Extensibility

---

### 18. **Conditional Steps Based on Changes**
```nix
{
  jobs = {
    frontend = {
      actions = [
        {
          name = "build-frontend";
          bash = "cd frontend && npm run build";
          if = "changed('frontend/**')";
        }
      ];
    };
    
    backend = {
      actions = [
        {
          name = "build-backend";
          bash = "cd backend && cargo build";
          if = "changed('backend/**')";
        }
      ];
    };
  };
}
```

**Реализация:**
```bash
changed() {
  git diff --quiet HEAD~1 -- "$1"
  return $?
}
```

**Почему важно:**
- Monorepo workflows
- Skip unnecessary builds
- Ускорение CI

---

### 19. **Workflow Inputs**
```nix
{ pkgs, platform, inputs }:

platform.mkWorkflow {
  name = "deploy";
  
  inputs = {
    environment = {
      type = "choice";
      options = ["staging" "production"];
      required = true;
    };
    version = {
      type = "string";
      default = "latest";
    };
  };
  
  jobs = {
    deploy = {
      actions = [{
        bash = ''
          kubectl apply -f k8s/${inputs.environment}/
          kubectl set image deployment/app app=myapp:${inputs.version}
        '';
      }];
    };
  };
}
```

```bash
$ nixactions run deploy --input environment=production --input version=v1.2.3
```

**Почему важно:**
- Параметризованные workflows
- Manual triggers
- Flexibility

---

### 20. **Artifacts Upload to Remote Storage**
```nix
{
  jobs = {
    build = {
      outputs = {
        dist = "dist/";
      };
      
      artifacts = {
        upload = {
          provider = "s3";
          bucket = "my-artifacts";
          key = "builds/${{ github.sha }}/dist.tar.gz";
        };
      };
    };
  };
}
```

**Почему важно:**
- Хранение артефактов долгосрочно
- Sharing между workflows
- S3/GCS/Azure Blob integration

---

## 🔧 Developer Experience

### 21. **Better REPL Experience**
```bash
$ nix repl
nix-repl> :l flake.nix
nix-repl> :p packages.x86_64-linux.example-ci

# Show workflow structure
nix-repl> lib.visualize packages.x86_64-linux.example-ci
{
  jobs = {
    test = {
      level = 0;
      actions = [ "checkout" "test" ];
    };
    build = {
      level = 1;
      needs = ["test"];
      actions = [ "build" ];
    };
  };
}
```

---

### 22. **VS Code Extension**
- Syntax highlighting для workflow files
- Autocomplete для platform.actions.*
- Inline documentation
- Run workflow из editor
- View logs в VS Code

---

### 23. **Metrics and Monitoring**
```nix
{
  monitoring = {
    prometheus = {
      enabled = true;
      port = 9090;
    };
    
    metrics = [
      "workflow_duration_seconds"
      "job_duration_seconds"
      "action_duration_seconds"
      "workflow_failures_total"
      "job_failures_total"
    ];
  };
}
```

```bash
# Prometheus metrics endpoint
$ curl localhost:9090/metrics

workflow_duration_seconds{workflow="ci"} 45.2
job_duration_seconds{workflow="ci",job="test"} 12.3
action_duration_seconds{workflow="ci",job="test",action="npm-test"} 8.1
```

---

### 24. **Notifications**
```nix
{
  notifications = {
    slack = {
      webhook = "$SLACK_WEBHOOK";
      on = ["failure" "success"];
      channel = "#ci-notifications";
    };
    
    telegram = {
      token = "$TELEGRAM_TOKEN";
      chat_id = "$TELEGRAM_CHAT_ID";
      on = ["failure"];
    };
    
    email = {
      to = "team@company.com";
      on = ["failure"];
    };
  };
}
```

---

### 25. **Workflow Scheduler (Cron)**
```nix
{
  schedule = {
    cron = "0 0 * * *";  # Daily at midnight
  };
  
  # OR
  
  schedule = {
    interval = "6h";  # Every 6 hours
  };
}
```

```bash
# Run in background with systemd timer
$ nixactions schedule ci --cron "0 0 * * *"
```

---

## 🎨 Quality of Life

### 26. **Smart Defaults**
```nix
# Minimal workflow (автоматически добавляет checkout, setup, cleanup)
{
  jobs = {
    test.bash = "npm test";
  };
}

# Эквивалентно:
{
  jobs = {
    test = {
      executor = platform.executors.local;  # default
      actions = [
        platform.actions.checkout            # auto-injected
        { bash = "npm test"; }
        platform.actions.cleanup             # auto-injected
      ];
    };
  };
}
```

---

### 27. **Action Marketplace / Registry**
```bash
$ nixactions search docker
Results:
  - docker-build - Build Docker images
  - docker-push - Push to registry
  - docker-scan - Security scanning

$ nixactions install docker-build
Added to flake inputs: nixactions-actions-docker-build
```

```nix
{
  actions = [
    nixactions-actions.docker-build {
      context = ".";
      file = "Dockerfile";
      tags = ["myapp:latest"];
    }
  ];
}
```

---

### 28. **Debugging Tools**
```bash
# Dry run (показывает что будет выполнено)
$ nixactions run ci --dry-run

# Step-by-step execution
$ nixactions run ci --step

# Debug mode (verbose logging)
$ nixactions run ci --debug

# Stop on failure (не выполнять cleanup)
$ nixactions run ci --stop-on-error

# Preserve workspace
$ NIXACTIONS_KEEP_WORKSPACE=1 nixactions run ci
```

---

## 🌟 Moonshots (Мечты)

### 29. **AI-Powered Workflow Generation**
```bash
$ nixactions ai "Create CI for Node.js app with TypeScript, Jest, Docker deployment to k8s"

Generated workflow:
  ✓ Install dependencies
  ✓ TypeScript type checking
  ✓ Jest unit tests
  ✓ Build Docker image
  ✓ Push to registry
  ✓ Deploy to k8s
  ✓ Smoke tests

Save to ci.nix? (y/n)
```

---

### 30. **Workflow Testing Framework**
```nix
# tests/ci_test.nix
{ pkgs, platform, nixactionsTest }:

nixactionsTest.suite {
  workflow = import ../ci.nix { inherit pkgs platform; };
  
  tests = {
    "test job should succeed with valid code" = {
      setup = ''
        echo "console.log('test')" > test.js
      '';
      
      expect = {
        job = "test";
        status = "success";
        duration_max = "30s";
      };
    };
    
    "test job should fail with broken code" = {
      setup = ''
        echo "syntax error" > test.js
      '';
      
      expect = {
        job = "test";
        status = "failure";
        output = "contains:syntax error";
      };
    };
  };
}
```

```bash
$ nixactions test
Running tests...
  ✓ test job should succeed with valid code (2.1s)
  ✓ test job should fail with broken code (0.8s)

2 passed, 0 failed
```

---

## 📊 Приоритизация

### Must Have (для 1.0)
1. Retry
2. Timeout
3. Cancellation
4. Better errors
5. Structured logging

### Should Have (для 2.0)
6. Job outputs
7. Matrix builds
8. Secrets masking
9. Caching
10. CLI tool

### Nice to Have (для 3.0+)
11. Templates
12. Reusable workflows
13. GitHub Actions converter
14. Visualization
15. VS Code extension

### Future Research
16. AI workflow generation
17. Workflow testing framework
18. Advanced monitoring
19. Marketplace

---

## 💬 Обратная связь

Какие фичи самые важные для вас? Создайте issue в GitHub!

Или голосуйте за существующие:
- 👍 - Must have
- ❤️ - Very useful
- 🎉 - Nice to have
- 🚀 - Game changer
