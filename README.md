# error-context

Zig error wrappers containing context data.

Experimental, proof of concept.

## Build

```shell
zig build
```

## Build docs

```shell
zig build docs
```

The docs need a server to render properly, for example:

```shell
python3 -m http.server -b 127.0.0.1 8000 -d zig-out/docs/
```

Open the browser and go to `127.0.0.1:8000` page.

If the docs were installed into some other directory, replace the default `zig-out` with its path.

## Test

```shell
zig build test
```
