# Omesh

Distributed full-text search engine for aarch64 .

## Build

```bash
make build/omesh
```

## Run

```bash
# Start with HTTP API
./build/omesh --http 8080 --mesh-port 9000

# Or run setup wizard
./build/omesh --setup
```

## Usage

```bash
# Index a document
curl -X POST -d '{"content":"your text here"}' http://localhost:8080/index

# Search
curl "http://localhost:8080/search?q=your+query"

# Health check
curl http://localhost:8080/health
```

## Mesh Networking

```bash
# Start second node connecting to first
./build/omesh --http 8081 --mesh-port 9001 --peer <first-node-ip>:9000
```

Search from either node finds documents on both.

## Requirements

- aarch64 Linux (Raspberry Pi, ARM server, WSL2 on snapdragon)
- GNU binutils (`apt install binutils`)

## License

See LICENSE file.
