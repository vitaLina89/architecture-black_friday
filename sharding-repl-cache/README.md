# MongoDB Sharding с Репликацией

## Архитектура

Проект использует MongoDB Sharding с репликацией для каждого шарда:
- 3 Config Server (replica set)
- 1 mongos (Query Router)
- 2 Shard, каждый с 3 репликами (1 Primary + 2 Secondary)

## Как запустить

### 1. Запуск контейнеров

```shell
docker compose up -d
```

Дождитесь запуска всех контейнеров (около 10-15 секунд).

### 2. Инициализация Config Servers Replica Set

Инициализируйте replica set для config servers:

```shell
docker compose exec -T config1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "config1:27019" },
    { _id: 1, host: "config2:27019" },
    { _id: 2, host: "config3:27019" }
  ]
})
EOF
```

Подождите несколько секунд, пока replica set инициализируется. Проверить статус можно командой:

```shell
docker compose exec -T config1 mongosh --port 27019 --quiet <<EOF
rs.status()
EOF
```

### 3. Настройка репликации для Shard 1

#### 3.1. Инициализация Replica Set для Shard 1

Инициализируйте replica set для первого шарда с Primary репликой:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1:27018" }
  ]
})
EOF
```

Подождите 5-10 секунд, пока Primary реплика станет доступной.

#### 3.2. Добавление Secondary реплик в Shard 1

Добавьте первую Secondary реплику:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.add("shard1-secondary1:27018")
EOF
```

Добавьте вторую Secondary реплику:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.add("shard1-secondary2:27018")
EOF
```

Проверьте статус репликации для Shard 1:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.status()
EOF
```

Убедитесь, что все три реплики (1 Primary и 2 Secondary) имеют статус "PRIMARY" или "SECONDARY" и состояние "1" (healthy).

### 4. Настройка репликации для Shard 2

#### 4.1. Инициализация Replica Set для Shard 2

Инициализируйте replica set для второго шарда с Primary репликой:

```shell
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2:27018" }
  ]
})
EOF
```

Подождите 5-10 секунд, пока Primary реплика станет доступной.

#### 4.2. Добавление Secondary реплик в Shard 2

Добавьте первую Secondary реплику:

```shell
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.add("shard2-secondary1:27018")
EOF
```

Добавьте вторую Secondary реплику:

```shell
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.add("shard2-secondary2:27018")
EOF
```

Проверьте статус репликации для Shard 2:

```shell
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.status()
EOF
```

Убедитесь, что все три реплики (1 Primary и 2 Secondary) имеют статус "PRIMARY" или "SECONDARY" и состояние "1" (healthy).

### 5. Добавление шардов в кластер

Добавьте первый шард (используйте строку подключения с Primary репликой):

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1:27018,shard1-secondary1:27018,shard1-secondary2:27018")
EOF
```

Добавьте второй шард:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard2ReplSet/shard2:27018,shard2-secondary1:27018,shard2-secondary2:27018")
EOF
```

Проверить список шардов:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

### 6. Включение шардирования для базы данных

Включите шардирование для базы данных `somedb`:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
EOF
```

### 7. Создание shard key для коллекции

Создайте индекс на поле, которое будет использоваться как shard key (например, `age`):

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.createIndex({ age: 1 })
EOF
```

Затем включите шардирование для коллекции с указанием shard key:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", { age: 1 })
EOF
```

### 8. Заполнение базы данных

Заполните базу данных тестовыми данными:

```shell
./scripts/mongo-init.sh
```

Или вручную:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF
```

### 9. Распределение данных между шардами

По умолчанию все данные попадают в один chunk на первом шарде. Чтобы распределить данные между шардами, нужно разделить chunk и переместить часть на второй шард:

Разделите chunk по середине диапазона:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.splitFind("somedb.helloDoc", {age: 500})
EOF
```

Переместите один из chunks на второй шард:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.moveChunk("somedb.helloDoc", {age: 500}, "shard2ReplSet")
EOF
```

Подождите несколько секунд, пока миграция завершится. Проверить статус можно командой:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

### 10. Проверка репликации и распределения данных

Проверить общее количество документов:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Проверить количество документов в первом шарде (Primary):

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Проверить количество документов во втором шарде (Primary):

```shell
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Проверить количество реплик в Shard 1:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.status().members.length
EOF
```

Проверить количество реплик в Shard 2:

```shell
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.status().members.length
EOF
```

Также можно проверить распределение через mongos:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

## Автоматизация настройки

Для автоматизации всех шагов настройки можно использовать скрипт:

```shell
./scripts/setup-replication.sh
```

Этот скрипт выполнит все необходимые команды для настройки репликации.

## Как проверить

### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080

API покажет:
- Общее количество документов в базе (должно быть ≥ 1000)
- Информацию о шардах
- Количество документов в каждой коллекции
- Количество реплик в каждом шарде

### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины:

```shell
curl --silent http://ifconfig.me
```

Откройте в браузере http://<ip виртуальной машины>:8080

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs

Основной эндпоинт `/` покажет информацию о топологии MongoDB, количестве документов в коллекциях, информацию о шардах и количестве реплик.
