# Development environment

## Prerequisites

- Docker and Docker Compose
- VS Code with the **Dev Containers** extension

## Starting the container

```bash
docker compose -f docker-compose.dev.yml up -d --build
```

This builds a single development image with all tools needed for both backend and frontend development, and mounts the source code into the container.

## Attaching VS Code

1. Open the command palette (`Ctrl+Shift+P`)
2. Run **Dev Containers: Attach to Running Container...**
3. Select `filebrowser-dev`

## Running the project

Inside the container, use the dev tasks for fast iteration:

```bash
# start the Vite dev server with hot-reload (port 5173)
task dev:frontend

# build and run the backend only
task dev:backend

# both concurrently
task dev
```

`task dev:frontend` skips typechecking, minification, and legacy polyfill generation — it starts in seconds and reflects frontend changes instantly via HMR.

`task dev:backend` does a plain `go build` and binds to `0.0.0.0:8080`, reachable from the Docker host at `http://localhost:8080`.

> **Note:** The backend defaults to `127.0.0.1` (loopback only). The `dev:backend` task passes `--address 0.0.0.0` so it's accessible outside the container.

## Debugging with Delve

Start the debugger headless so VS Code can attach:

```bash
dlv debug --headless --listen=:2345 --api-version=2 .
```

Then in VS Code, use a launch configuration like:

```json
{
  "name": "Attach to Delve",
  "type": "go",
  "request": "attach",
  "mode": "remote",
  "port": 2345,
  "host": "127.0.0.1"
}
```

## Exposed ports

| Port | Purpose | --- | --- |
| 8080 | Go backend |
| 5173 | Vite dev server |
| 2345 | Delve debugger |

## Available tools inside the container

- **Go 1.25** — compiler and toolchain
- **Node.js 24 + pnpm** — frontend toolchain
- **Delve** (`dlv`) — Go debugger
- **gopls** — Go language server
- **Task** — task runner (see `Taskfile.yml`)
- git, curl, wget, jq, vim
