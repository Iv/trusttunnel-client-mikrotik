# trusttunnel-client-mikrotik

[English](README.md) | **Русский**

Минимальный Docker-образ [клиента TrustTunnel](https://github.com/TrustTunnel/TrustTunnelClient)
для контейнеров MikroTik RouterOS.

- Исходники: [github.com/Iv/trusttunnel-client-mikrotik](https://github.com/Iv/trusttunnel-client-mikrotik)
- Docker Hub: [`quai1rol/trusttunnel-client-mikrotik`](https://hub.docker.com/r/quai1rol/trusttunnel-client-mikrotik)

- **Платформы:** `linux/arm64` (hAP ax2, ax3, …) и `linux/arm/v7` (hAP ac2, ac3, …).
- **Маленький:** ~10 МБ. Бинарники апстрима статические, поэтому базовый образ — это
  просто `busybox:musl` и набор корневых сертификатов.
- **Бережёт флеш:** клиент не пишет лог-файлы. Всё выводится в stdout, а RouterOS
  хранит это в журнале в памяти, если у контейнера `logging=yes`. Единственный файл,
  который пишется во время работы, — сгенерированный `client.toml`, один раз при старте.
- **Перезапускается сам:** клиент завершается после нескольких неудачных попыток
  подключения (например, если при загрузке WAN ещё не поднялся). Entrypoint
  восстанавливает исходный маршрут по умолчанию и запускает клиент заново.
- **Совместим по переменным окружения** с `vardo/trusttunnel-client-mikrotik`.

Идея и первая версия инструкции для RouterOS взяты из
[`vardo/trusttunnel-client-mikrotik`](https://hub.docker.com/r/vardo/trusttunnel-client-mikrotik).
Этот образ — его переработка: более новый клиент, намного меньший размер, чтобы
помещаться во внутреннюю флеш-память устройств без USB-накопителя, цикл перезапуска
и примеры резервирования (failover).

## Переменные окружения

| Переменная | Обязательна | По умолчанию | Описание |
|---|---|---|---|
| `TT_ADDRESS` | да | | Адрес сервера `IP:PORT` |
| `TT_HOSTNAME` | да | | TLS-имя хоста сервера |
| `TT_USER` | да | | Имя пользователя |
| `TT_PASS` | да | | Пароль |
| `TT_EXPOSE` | нет | | Сети через пробел, которые маршрутизируются мимо туннеля (через исходный шлюз контейнера), например ваша LAN. С NAT-схемой ниже не нужна |
| `TT_TUN_DEV` | нет | `tun0` | Имя TUN-интерфейса |
| `TT_IPV6` | нет | `0` | `1` — пускать IPv6 через туннель (`has_ipv6` и маршрут `2000::/3`) |
| `TT_LOGLEVEL` | нет | `info` | `error`, `warn`, `info`, `debug`, `trace` |
| `TT_RESTART` | нет | `1` | `0` — контейнер завершается вместе с клиентом |
| `TT_RESTART_DELAY` | нет | `10` | Пауза в секундах перед перезапуском клиента |
| `TT_CONFIG` | нет | `/opt/trusttunnel/client.toml` | Путь к сгенерированному конфигу |

Сгенерированный конфиг использует `vpn_mode = "general"` и `killswitch_enabled = false`.

## Настройка RouterOS

Проверено на hAP ac³ (armv7, 128 МБ флеш, 256 МБ ОЗУ) с RouterOS 7.25. USB-диск
не нужен: образ занимает на флеше около 7 МБ. Синтаксис может немного отличаться
в разных версиях RouterOS 7.x.

Адреса в примерах (замените на свои):

| | |
|---|---|
| Сторона RouterOS у veth | `172.31.31.1/24` |
| Контейнер | `172.31.31.2/24` |
| Сервер TrustTunnel | `203.0.113.10:443`, имя хоста `vpn.example.com` |

### 1. Включите контейнеры

`device-mode` требует физического подтверждения (кнопка reset или отключение питания), см.
[документацию RouterOS по контейнерам](https://help.mikrotik.com/docs/spaces/ROS/pages/84901929/Container).
Установка пакета перезагружает роутер.

```routeros
/system/device-mode/update container=yes
/system/package/enable container
/system/package/apply-changes
```

### 2. Доверие к TLS-сертификату Docker Hub

Без этого загрузка образа падает с ошибкой `SSL: no trusted CA certificate found`.
Либо включите встроенное хранилище доверенных сертификатов:

```routeros
/certificate/settings/set builtin-trust-store=all
```

либо импортируйте только нужные Docker Hub корневые сертификаты: Amazon Root CA 1 и
Starfield Services Root G2 (registry), ISRG Root X1 (авторизация и CDN для слоёв).
Скачайте их на ПК и скопируйте на роутер:

```sh
curl -fsSLO https://www.amazontrust.com/repository/AmazonRootCA1.pem
curl -fsSLO https://www.amazontrust.com/repository/SFSRootCAG2.pem
curl -fsSLO https://letsencrypt.org/certs/isrgrootx1.pem
scp AmazonRootCA1.pem SFSRootCAG2.pem isrgrootx1.pem admin@ROUTER:
```

```routeros
/certificate/import file-name=AmazonRootCA1.pem passphrase=""
/certificate/import file-name=SFSRootCAG2.pem passphrase=""
/certificate/import file-name=isrgrootx1.pem passphrase=""
```

### 3. Загрузка образа без записи на флеш (необязательно)

Скачанные слои в любом случае распаковываются в корневой каталог контейнера.
RAM-диск для временных файлов избавляет от двойной записи каждого слоя на флеш.

```routeros
/disk/add type=tmpfs tmpfs-max-size=48M slot=ram comment="container pull tmp (RAM)"
/container/config/set tmpdir=ram
```

### 4. Сеть: veth и NAT

```routeros
/interface/veth/add name=TT-VETH address=172.31.31.2/24 gateway=172.31.31.1
/ip/address/add address=172.31.31.1/24 interface=TT-VETH

# Маскарадим всё, что уходит в контейнер: контейнер видит единственный адрес
# источника (172.31.31.1), и ответы возвращаются без дополнительных маршрутов внутри него.
/ip/firewall/nat/add chain=srcnat out-interface=TT-VETH action=masquerade comment="trusttunnel container"
```

Контейнер достаёт до сервера через обычный маскарадинг на WAN роутера. Если цепочка
`forward` заканчивается правилом drop, разрешите также `src-address=172.31.31.2`.

IP сервера всегда должен маршрутизироваться через WAN, а не через туннель. Это
происходит само собой, если только вы не направляете через контейнер маршрут по
умолчанию или большой список префиксов (BGP, address lists). В этом случае добавьте
прямой маршрут:

```routeros
/ip/route/add dst-address=203.0.113.10/32 gateway=WAN_GATEWAY comment="trusttunnel endpoint direct"
```

### 5. Контейнер

`TT_ADDRESS` должен быть IP-адресом, а не именем хоста.

```routeros
/container/envs/add list=tt key=TT_ADDRESS  value=203.0.113.10:443
/container/envs/add list=tt key=TT_HOSTNAME value=vpn.example.com
/container/envs/add list=tt key=TT_USER     value=user
/container/envs/add list=tt key=TT_PASS     value=secret

/container/add remote-image=quai1rol/trusttunnel-client-mikrotik:latest \
    interface=TT-VETH envlist=tt root-dir=tt logging=yes start-on-boot=yes comment=trusttunnel
/container/start [find comment=trusttunnel]
```

Проверьте журнал. При работающем туннеле там будут `VPN_SS_CONNECTED` и
`Successfully connected to endpoint`:

```routeros
/log/print where topics~"container"
```

Изнутри самого контейнера:

```routeros
/container/shell [find comment=trusttunnel] cmd="wget -qO- https://api.ipify.org"
```

Чтобы ничего не писалось в журнал на флеше, убедитесь, что топик `container`
направлен в действие `memory` в `/system/logging` (это настройка RouterOS по умолчанию).

### 6. Направьте трафик в туннель

Шлюз — это IP контейнера (`172.31.31.2`), а не интерфейс. Начните с одного адреса
и проверьте внешний IP с хоста в LAN:

```routeros
/ip/route/add dst-address=1.0.0.1/32 gateway=172.31.31.2 comment="tt-probe: health check via trusttunnel"
```

```sh
curl -s https://1.0.0.1/cdn-cgi/trace | grep ^ip=    # должен показать внешний IP VPN
```

ICMP через туннель не передаётся, поэтому проверяйте по TCP (curl, fetch), а не ping.

### 7. Переключение на другой VPN (failover)

Пока контейнер запущен, veth-интерфейс всегда поднят, даже если туннель упал, поэтому
`check-gateway` и состояние интерфейса не помогут обнаружить сбой. Используйте netwatch
с TCP-проверкой через туннель и пометьте переключаемые маршруты префиксом в комментарии
(`tt-failover`).

Схема ниже направляет список BGP-префиксов (или любые другие маршруты) через
виртуальный next hop `10.255.99.1`. Этот next hop разрешается в первую очередь через
TrustTunnel, а в качестве резерва — через другой VPN (здесь `sstp-vr`):

```routeros
# Входной фильтр BGP (или статические маршруты): gateway = виртуальный next hop
/routing/filter/rule/add chain=bgp-in rule="set gw 10.255.99.1; accept;"

# Next hop: TrustTunnel (основной), SSTP (резерв). scope=10 нужен для рекурсивного разрешения.
/ip/route/add dst-address=10.255.99.1/32 gateway=172.31.31.2 distance=1 scope=10 target-scope=10 \
    comment="tt-failover: next hop via trusttunnel"
/ip/route/add dst-address=10.255.99.1/32 gateway=sstp-vr distance=2 scope=10 target-scope=10 \
    comment="next hop via sstp (backup)"

# Таблица policy routing: та же идея для маршрута по умолчанию
/routing/table/add name=xoxo fib
/ip/route/add dst-address=0.0.0.0/0 routing-table=xoxo gateway=172.31.31.2 distance=1 \
    comment="tt-failover: xoxo via trusttunnel"
/ip/route/add dst-address=0.0.0.0/0 routing-table=xoxo gateway=sstp-vr distance=2 \
    comment="xoxo via sstp (backup)"

# Проверка здоровья: 1.0.0.1 всегда через туннель, никогда не утекает в WAN
/ip/route/add dst-address=1.0.0.1/32 gateway=172.31.31.2 distance=1 comment="tt-probe: via trusttunnel"
/ip/route/add dst-address=1.0.0.1/32 blackhole distance=2 comment="tt-probe: never leak to WAN"

/tool/netwatch/add name=tt-health type=tcp-conn host=1.0.0.1 port=443 interval=10s timeout=5s \
    up-script="/ip/route/enable [find comment~\"^tt-failover\"]; :log info \"tt-health: UP\"" \
    down-script="/ip/route/disable [find comment~\"^tt-failover\"]; :log warning \"tt-health: DOWN\""
```

Как это работает:

- туннель упал, контейнер работает: netwatch переходит в `down` за 10–20 с, маршруты
  `tt-failover` отключаются, и трафик уходит на резерв. Когда туннель восстанавливается,
  маршруты снова включаются;
- контейнер остановлен: veth опускается, маршруты через `172.31.31.2` сами становятся
  неактивными, и резерв подхватывает трафик сразу.

Всё, от чего зависит сам резервный канал (например, сеть BGP-пира или IP сервера),
держите на маршрутах, которые не идут через контейнер.

## Публикация (GitHub Actions)

[`.github/workflows/publish.yml`](.github/workflows/publish.yml) собирает `linux/arm64` + `linux/arm/v7`
и публикует `:<version>` и `:latest` в Docker Hub:

- при push в `main`, который меняет файлы образа (собирается версия из `VERSION`);
- вручную (*Actions → Publish to Docker Hub → Run workflow*), при желании с указанием версии;
- еженедельно: если в апстриме вышел новый **стабильный** релиз, он собирается, а новый
  `VERSION` коммитится.

Также workflow синхронизирует английский README с описанием на Docker Hub.

Нужные настройки репозитория:

- переменная `DOCKERHUB_USERNAME` = `quai1rol`;
- секрет `DOCKERHUB_TOKEN` = токен доступа Docker Hub. Для публикации достаточно
  **Read & Write**; для обновления описания на Docker Hub нужен **Read, Write, Delete**.

## Локальная сборка

Архивы релизов скачиваются на хосте в `dist/`, затем собираются через buildx:

```sh
./build.sh                   # собрать версию из VERSION
./build.sh 1.1.11 --push     # собрать и опубликовать :1.1.11 и :latest
```

`build.sh` использует buildx-сборщик с именем `tt-builder`. Чтобы использовать другой,
задайте `BUILDER=<имя>`. Сборщику нужен QEMU/binfmt для arm64 и arm/v7.
