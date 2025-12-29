# SDK v2 Design

## Проблемы SDK v1

### 1. Extension для валидации
SDK v1 требовал `extensions = [ sdk.validation ]` в mkWorkflow. Это плохо:
- SDK не автономный, зависит от хука в компилятор
- Если забыл extension - валидация молча не работает
- Extension как костыль для дизайна = архитектурный запах

### 2. Искусственные переменные
`INPUT_*`, `OUTPUT_*`, `STEP_OUTPUT_step_var` - своя конвенция вместо обычных env.
Почему не просто `$VAR`?

### 3. Типы ради типов
`types.string`, `types.int` - eval-time проверка работает только для литералов.
Для `$VAR` всё равно runtime. Много кода, мало пользы.

### 4. Refs создали проблему
`stepOutput "build" "imageRef"` потребовал:
- Уникальные имена `STEP_OUTPUT_build_imageRef`
- Extension для валидации ссылок
- Кодогенерацию маппинга

Цепочка костылей для решения проблемы которую сами создали.

### 5. defineJob - удалили как оверинжиниринг
Сигнал что что-то не так с подходом.

---

## SDK v2 - Простой подход

### Концепция

```nix
buildImage = sdk.mkAction {
  reads = [ "REGISTRY" "TAG" ];
  writes = [ "IMAGE_REF" ];
  run = ''
    docker build -t $REGISTRY:$TAG .
    IMAGE_REF="$REGISTRY:$TAG"
  '';
};
```

### Использование

```nix
steps = [
  buildImage                        # дефолт - читает $REGISTRY, $TAG
  (buildImage { TAG = "v2"; })      # оверрайд TAG
  (buildImage {
    REGISTRY = "$PROD_REGISTRY";    # маппинг на другую env
    IMAGE_REF = "MY_OUTPUT";        # пишет в другую переменную
  })
];
```

### Функтор - без пустых скобок

Используем `__functor` чтобы работало и так и так:

```nix
buildImage = {
  name = "build-image";
  bash = "...";
  __functor = self: overrides: { /* apply overrides */ };
};

steps = [
  buildImage                   # без скобок - step как есть
  (buildImage { TAG = "v2"; }) # со скобками - вызов функтора
];
```

---

## Что делает mkAction

### reads - входы
- Объявляет какие env переменные нужны скрипту
- При оверрайде можно замапить на другой источник:
  - `REGISTRY = "$OTHER_VAR"` - другая env
  - `REGISTRY = "ghcr.io"` - литерал

### writes - выходы  
- Автоматический экспорт в `$JOB_ENV`
- При оверрайде можно замапить имя:
  - `IMAGE_REF = "BUILD_OUTPUT"` - пишет в другую переменную

### run - скрипт
- Обычный bash
- Обычные `$VAR`, никаких `INPUT_*`

---

## Генерация bash

### Дефолт (без оверрайдов)
```bash
# run как есть
docker build -t $REGISTRY:$TAG .
IMAGE_REF="$REGISTRY:$TAG"

# auto-export writes
echo "IMAGE_REF=$IMAGE_REF" >> $JOB_ENV
```

### С оверрайдом reads
```nix
(buildImage { REGISTRY = "$PROD_REGISTRY"; TAG = "v1.0"; })
```
```bash
# маппинг reads
REGISTRY="$PROD_REGISTRY"
TAG="v1.0"

# run
docker build -t $REGISTRY:$TAG .
IMAGE_REF="$REGISTRY:$TAG"

# auto-export writes
echo "IMAGE_REF=$IMAGE_REF" >> $JOB_ENV
```

### С оверрайдом writes
```nix
(buildImage { IMAGE_REF = "MY_OUTPUT"; })
```
```bash
# run
docker build -t $REGISTRY:$TAG .
IMAGE_REF="$REGISTRY:$TAG"

# auto-export с маппингом имени
echo "MY_OUTPUT=$IMAGE_REF" >> $JOB_ENV
```

---

## Валидация (опционально)

### Чекеры вместо типов
```nix
writes = {
  IMAGE_REF = sdk.check.notEmpty;
  PORT = sdk.check.int;
  CONFIG = sdk.check.json;
};
```

Генерирует bash-проверку перед экспортом:
```bash
# check.notEmpty
[ -n "$IMAGE_REF" ] || { echo "IMAGE_REF is empty" >&2; exit 1; }

# check.int
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "PORT must be int" >&2; exit 1; }
```

Никаких extensions - проверка прямо в сгенерированном bash.

---

## Сравнение v1 vs v2

| | v1 | v2 |
|---|---|---|
| Переменные в run | `$INPUT_*`, `$OUTPUT_*` | `$VAR` |
| Маппинг | refs: `fromEnv`, `stepOutput` | просто строки |
| Валидация | extension в mkWorkflow | чекеры в bash |
| Без оверрайдов | `(action {})` | `action` |
| Файлов в sdk/ | 5 | 1-2 |
| Extensions нужны | да | нет |

---

## Философия

### GitHub Actions vs GitLab

**GitLab**: вот тебе shell, ебись сам
**GitHub Actions**: контракт - inputs/outputs, GITHUB_OUTPUT

SDK v2 = минимальный контракт:
- `reads` - что читаю
- `writes` - что пишу
- Возможность оверрайда

Без переусложнения.

### KISS

Если можно сделать проще - делай проще.
`$VAR` вместо `$INPUT_var`.
Функтор вместо обязательных `{}`.
Bash чекеры вместо eval-time типов.
