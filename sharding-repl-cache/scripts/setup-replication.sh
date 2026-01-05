#!/bin/bash

set -e

echo "=== Настройка MongoDB Sharding с Репликацией ==="
echo ""

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для ожидания готовности MongoDB
wait_for_mongo() {
    local container=$1
    local port=$2
    echo -e "${YELLOW}Ожидание готовности $container...${NC}"
    for i in {1..30}; do
        if docker compose exec -T $container mongosh --port $port --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
            echo -e "${GREEN}$container готов${NC}"
            return 0
        fi
        sleep 1
    done
    echo "Ошибка: $container не готов"
    return 1
}

echo "1. Инициализация Config Servers Replica Set..."
docker compose exec -T config1 mongosh --port 27019 --quiet <<EOF
try {
    var status = rs.status();
    print("Config Replica Set уже инициализирован");
} catch (e) {
    rs.initiate({
        _id: "configReplSet",
        configsvr: true,
        members: [
            { _id: 0, host: "config1:27019" },
            { _id: 1, host: "config2:27019" },
            { _id: 2, host: "config3:27019" }
        ]
    });
    print("Config Replica Set инициализирован");
}
EOF

echo "Ожидание инициализации Config Replica Set..."
sleep 5

echo ""
echo "2. Настройка репликации для Shard 1..."

echo "2.1. Инициализация Replica Set для Shard 1..."
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
try {
    var status = rs.status();
    print("Shard1 Replica Set уже инициализирован");
} catch (e) {
    rs.initiate({
        _id: "shard1ReplSet",
        members: [
            { _id: 0, host: "shard1:27018" }
        ]
    });
    print("Shard1 Replica Set инициализирован");
}
EOF

echo "Ожидание готовности Primary реплики Shard 1..."
sleep 10

echo "2.2. Добавление Secondary реплик в Shard 1..."
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
var config = rs.conf();
var members = config.members.map(m => m.host);

if (!members.includes("shard1-secondary1:27018")) {
    rs.add("shard1-secondary1:27018");
    print("Добавлена реплика shard1-secondary1");
} else {
    print("Реплика shard1-secondary1 уже добавлена");
}

if (!members.includes("shard1-secondary2:27018")) {
    rs.add("shard1-secondary2:27018");
    print("Добавлена реплика shard1-secondary2");
} else {
    print("Реплика shard1-secondary2 уже добавлена");
}
EOF

echo "Ожидание синхронизации реплик Shard 1..."
sleep 10

echo ""
echo "3. Настройка репликации для Shard 2..."

echo "3.1. Инициализация Replica Set для Shard 2..."
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
try {
    var status = rs.status();
    print("Shard2 Replica Set уже инициализирован");
} catch (e) {
    rs.initiate({
        _id: "shard2ReplSet",
        members: [
            { _id: 0, host: "shard2:27018" }
        ]
    });
    print("Shard2 Replica Set инициализирован");
}
EOF

echo "Ожидание готовности Primary реплики Shard 2..."
sleep 10

echo "3.2. Добавление Secondary реплик в Shard 2..."
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
var config = rs.conf();
var members = config.members.map(m => m.host);

if (!members.includes("shard2-secondary1:27018")) {
    rs.add("shard2-secondary1:27018");
    print("Добавлена реплика shard2-secondary1");
} else {
    print("Реплика shard2-secondary1 уже добавлена");
}

if (!members.includes("shard2-secondary2:27018")) {
    rs.add("shard2-secondary2:27018");
    print("Добавлена реплика shard2-secondary2");
} else {
    print("Реплика shard2-secondary2 уже добавлена");
}
EOF

echo "Ожидание синхронизации реплик Shard 2..."
sleep 10

echo ""
echo "4. Добавление шардов в кластер..."

wait_for_mongo mongos 27017

docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
var shards = sh.status().shards || [];
var shardIds = shards.map(s => s._id);

if (!shardIds.includes("shard1ReplSet")) {
    sh.addShard("shard1ReplSet/shard1:27018,shard1-secondary1:27018,shard1-secondary2:27018");
    print("Добавлен шард shard1ReplSet");
} else {
    print("Шард shard1ReplSet уже добавлен");
}

if (!shardIds.includes("shard2ReplSet")) {
    sh.addShard("shard2ReplSet/shard2:27018,shard2-secondary1:27018,shard2-secondary2:27018");
    print("Добавлен шард shard2ReplSet");
} else {
    print("Шард shard2ReplSet уже добавлен");
}
EOF

echo ""
echo "5. Включение шардирования для базы данных..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
try {
    sh.enableSharding("somedb");
    print("Шардирование включено для базы данных somedb");
} catch (e) {
    print("Шардирование уже включено или ошибка: " + e.message);
}
EOF

echo ""
echo "6. Создание shard key для коллекции..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
try {
    db.helloDoc.createIndex({ age: 1 });
    print("Индекс создан");
} catch (e) {
    print("Индекс уже существует или ошибка: " + e.message);
}

try {
    sh.shardCollection("somedb.helloDoc", { age: 1 });
    print("Шардирование включено для коллекции helloDoc");
} catch (e) {
    print("Шардирование уже включено или ошибка: " + e.message);
}
EOF

echo ""
echo "7. Заполнение базы данных..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
var count = db.helloDoc.countDocuments();
if (count < 1000) {
    for(var i = count; i < 1000; i++) {
        db.helloDoc.insertOne({age:i, name:"ly"+i});
    }
    print("Добавлено документов: " + (1000 - count));
} else {
    print("База данных уже содержит " + count + " документов");
}
EOF

echo ""
echo "8. Распределение данных между шардами..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
try {
    sh.splitFind("somedb.helloDoc", {age: 500});
    print("Chunk разделен");
} catch (e) {
    print("Chunk уже разделен или ошибка: " + e.message);
}

sleep(2000);

try {
    sh.moveChunk("somedb.helloDoc", {age: 500}, "shard2ReplSet");
    print("Chunk перемещен на shard2ReplSet");
} catch (e) {
    print("Chunk уже перемещен или ошибка: " + e.message);
}
EOF

echo ""
echo "Ожидание завершения миграции..."
sleep 5

echo ""
echo "=== Проверка результатов ==="
echo ""

echo "Статус репликации Shard 1:"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
var status = rs.status();
print("Количество реплик: " + status.members.length);
status.members.forEach(function(member) {
    print("  - " + member.name + ": " + member.stateStr);
});
EOF

echo ""
echo "Статус репликации Shard 2:"
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
var status = rs.status();
print("Количество реплик: " + status.members.length);
status.members.forEach(function(member) {
    print("  - " + member.name + ": " + member.stateStr);
});
EOF

echo ""
echo "Общее количество документов:"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
print("Всего документов: " + db.helloDoc.countDocuments());
EOF

echo ""
echo "Количество документов в Shard 1:"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
print("Документов в Shard 1: " + db.helloDoc.countDocuments());
EOF

echo ""
echo "Количество документов в Shard 2:"
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
print("Документов в Shard 2: " + db.helloDoc.countDocuments());
EOF

echo ""
echo -e "${GREEN}=== Настройка завершена! ===${NC}"
echo ""
echo "Проверьте результаты в браузере: http://localhost:8080"

