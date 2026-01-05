# MongoDB Sharding Setup

## Архитектура

Проект использует MongoDB Sharding с следующими компонентами:
- 3 Config Server (replica set)
- 1 mongos (Query Router)
- 2 Shard

## Как запустить

### 1. Запуск контейнеров

```shell
docker compose up -d
```

### 2. Инициализация Config Servers Replica Set

Дождитесь запуска всех контейнеров, затем инициализируйте replica set для config servers:

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

### 3. Инициализация Replica Sets для шардов

Инициализируйте replica set для первого шарда:

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

Инициализируйте replica set для второго шарда:

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

Подождите несколько секунд, пока replica sets инициализируются.

### 4. Добавление шардов в кластер

Добавьте первый шард:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1:27018")
EOF
```

Добавьте второй шард:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard2ReplSet/shard2:27018")
EOF
```

Проверить список шардов:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

### 5. Включение шардирования для базы данных

Включите шардирование для базы данных `somedb`:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
EOF
```

### 6. Создание shard key для коллекции

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

### 7. Заполнение базы данных

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

### 8. Распределение данных между шардами

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

### 9. Проверка распределения данных по шардам

Проверить общее количество документов:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Проверить количество документов в первом шарде:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Проверить количество документов во втором шарде:

```shell
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Также можно проверить распределение через mongos:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

## Как проверить

### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080

API покажет:
- Общее количество документов в базе (должно быть ≥ 1000)
- Информацию о шардах
- Количество документов в каждой коллекции

### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины:

```shell
curl --silent http://ifconfig.me
```

Откройте в браузере http://<ip виртуальной машины>:8080

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs

Основной эндпоинт `/` покажет информацию о топологии MongoDB, количестве документов в коллекциях и информацию о шардах.

