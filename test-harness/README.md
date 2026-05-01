# Smoke-test harness

Boots a Folia 26.1.2 server (Luminol fork or vanilla Folia) with the freshly-built `AxiomPaper-*-all.jar` in `plugins/`, watches the log for plugin enable + Done + a quiet post-Done period, fires a few rcon commands, and tears down. Writes `result.txt` (PASS/FAIL).

Used during development to confirm the Folia port loads cleanly and the global region tick survives without `WrongThreadException`.

## Layout (paths in `run-tests.sh` are absolute on the maintainer's machine)

```
test-harness/
  server/                     # hermetic server, fresh world per run
    luminol-paperclip-26.1.2.local-SNAPSHOT.jar
    eula.txt, server.properties (port=25699, rcon=25698)
    plugins/AxiomPaper-*.jar
  run-tests.sh                # boot/watch/teardown driver
  result.txt                  # PASS or FAIL marker
  run.log                     # full server stdout/stderr
```

## Adapting to your setup

The script in this repo is the maintainer's local copy with hard-coded absolute paths under `/Users/paulchauvat/axiom-folia/test-harness`. To run it elsewhere:

1. Copy the script.
2. Edit the `HARNESS_DIR` and `JAVA_HOME_DIR` constants at the top.
3. Place a Folia/Luminol/Paper-with-Folia-API jar at `${SERVER_DIR}/luminol-paperclip-26.1.2.local-SNAPSHOT.jar` (or update `SERVER_JAR`).
4. `mkdir -p ${SERVER_DIR}/plugins && echo "eula=true" > ${SERVER_DIR}/eula.txt && cp /path/to/AxiomPaper-*-all.jar ${SERVER_DIR}/plugins/`.
5. `bash run-tests.sh`.

PASS = plugin enabled, server reached `Done (`, 25 s of post-load tick + 6 rcon commands ran without any of: `WrongThreadException`, `is not Folia compatible`, `IllegalStateException` from AxiomPaper, severe stack traces in `com.moulberry.axiom`.
