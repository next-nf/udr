# Configuration Reference: Data Store (`udr_db`, `udr_db_mongo`)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## 1. Scope

This reference covers data-store configuration: the backend selection in `udr_db` (`backend`, `backend_opts`) and the [MongoDB](../glossary.md) connection options read by `udr_db_mongo` from `backend_opts` when the MongoDB backend is selected. It documents how to keep the default in-memory [ETS](../glossary.md) backend or select MongoDB instead.

The document model and collection layout are out of scope here. The data-access seam (`udr_data`) reads no configuration of its own and is not documented here.

## 2. Terms

- **Backend** — the storage module `udr_db` dispatches to. The shipped backends are `udr_db_ets` (in-memory ETS) and `udr_db_mongo` (MongoDB).
- **`backend_opts`** — a map passed unchanged to the selected backend's `child_spec/1`. For the MongoDB backend it carries the connection options in §5.2.

## 3. Where configuration lives

Configuration is in `config/sys.config` under the `udr_db` key, applied at boot. The shipped block is:

```erlang
{udr_db, [
  {backend, udr_db_ets},
  {backend_opts, #{}}
]}
```

> [!IMPORTANT]
> `udr_db` caches the resolved backend in a `persistent_term` on first use. Changing `backend` at runtime does not take effect until the node restarts.

## 4. Parameter reference

| Parameter | Type | Default | Allowed values | Unit | Description | Effect | Since |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `backend` | atom (module) | `udr_db_ets` | `udr_db_ets`, `udr_db_mongo` | — | The storage backend module `udr_db` dispatches every read and write to. | Selects in-memory ETS (no external database) or MongoDB (persistent). | 0.1.0 |
| `backend_opts` | map | `#{}` | a map; keys depend on the backend (see §5.2 for MongoDB) | — | Options passed to the selected backend's `child_spec/1`. | For `udr_db_mongo`, supplies the MongoDB connection parameters; for `udr_db_ets`, ignored. | 0.1.0 |

### MongoDB connection options (within `backend_opts`)

These map keys are read by `udr_db_mongo_conn` only when `backend` is `udr_db_mongo`. Each key is optional and falls back to the default shown.

| Key | Type | Default | Allowed values | Unit | Description | Effect | Since |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `database` | binary | `<<"udr">>` | a MongoDB database name | — | The database the backend reads and writes. | Selects which MongoDB database holds the collections. | 0.1.0 |
| `host` | string | `"127.0.0.1"` | a hostname or IPv4 address string | — | The MongoDB server host. | Selects which MongoDB server the node connects to. | 0.1.0 |
| `port` | integer | `27017` | a TCP port number, `1`–`65535` | port | The MongoDB server port. | Sets the port used for the MongoDB connection. | 0.1.0 |
| `login` | binary | *not set* (no authentication) | a MongoDB user name | — | The user name for MongoDB authentication. | When absent, the backend connects without authentication; when present, it authenticates as this user. | 0.1.0 |
| `password` | binary | `<<>>` | the password for `login` | — | The password used with `login`. | Read only when `login` is set; supplies the credential for authentication. | 0.1.0 |
| `auth_source` | binary | `<<"admin">>` | a MongoDB authentication database name | — | The database against which `login` is authenticated. | Read only when `login` is set; selects the auth database. | 0.1.0 |

## 5. Parameter detail

### 5.1 `backend`

`backend` selects the storage module at boot.

- The default `udr_db_ets` backend `may` be used for development and for deployments that do not need persistence; it requires no external database, and its data does not survive a node restart.
- The `udr_db_mongo` backend `may` be selected in place of ETS where subscriber data is to persist across restarts.
- After changing `backend`, the node `shall` be restarted for the change to take effect, because the resolved backend is cached in a `persistent_term`.

> [!WARNING]
> The ETS backend is in-memory. All provisioned subscriber data is lost when the node stops. Where subscriber data is to survive a restart, select the MongoDB backend.

### 5.2 `backend_opts` for MongoDB

When `backend` is `udr_db_mongo`, `backend_opts` is the MongoDB connection map. The keys are listed in the table above.

- `login` `shall` be set to enable authentication; when `login` is absent, the backend connects without authenticating and `password` and `auth_source` are not read.
- When `login` is set, `password` and `auth_source` `should` be set to match the MongoDB user's credential and authentication database.
- The `mongodb` driver application is started on demand the first time the backend connects; it is not booted for an ETS-only deployment.

> [!NOTE]
> The `udr_db_mongo` application is loaded by the release but not auto-started. It is started on demand by `udr_db`'s supervisor only when `backend` selects it, so an ETS-only node never starts the MongoDB driver.

## 6. Example

Select MongoDB on a dedicated database host with authentication:

```erlang
{udr_db, [
  {backend, udr_db_mongo},
  {backend_opts, #{
    host => "10.0.0.20",
    port => 27017,
    database => <<"hss">>,
    login => <<"hss_app">>,
    password => <<"s3cr3t">>,
    auth_source => <<"admin">>
  }}
]}
```

This makes the node persist subscriber data in the `hss` database on `10.0.0.20:27017`, authenticating as `hss_app` against the `admin` database.

## 7. Verify

- Confirm which backend resolved. From the running Erlang shell:

  ```erlang
  udr_db:backend().
  ```

  The result `shall` be the configured module, `udr_db_ets` or `udr_db_mongo`.

- For the MongoDB backend, confirm the connection handle exists:

  ```erlang
  is_pid(udr_db_mongo_conn:conn()).
  ```

  The result `shall` be `true` once the backend has connected.

- End to end, provision a subscriber and read it back; a `GET` that returns `200 OK` with the subscriber document confirms the backend stores and serves data. For the MongoDB backend, restarting the node and reading the same subscriber back confirms persistence.
