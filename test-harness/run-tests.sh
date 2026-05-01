#!/usr/bin/env bash
# Axiom-Folia smoke test harness.
# Boots a fresh Folia (Luminol) server with the AxiomPaper plugin, watches the
# log for plugin enable + Done + a quiet post-Done period, then tears down the
# JVM and writes ~/axiom-folia/test-harness/result.txt.
#
# Exit code: 0 = PASS, 1 = FAIL.

set -u

HARNESS_DIR="/Users/paulchauvat/axiom-folia/test-harness"
SERVER_DIR="${HARNESS_DIR}/server"
RESULT_FILE="${HARNESS_DIR}/result.txt"
LOG_FILE="${SERVER_DIR}/logs/latest.log"
RUN_LOG="${HARNESS_DIR}/run.log"
PID_FILE="${HARNESS_DIR}/server.pid"

JAVA_HOME_DIR="/opt/homebrew/opt/openjdk@25/libexec/openjdk.jdk/Contents/Home"
JAVA_BIN="${JAVA_HOME_DIR}/bin/java"
SERVER_JAR="luminol-paperclip-26.1.2.local-SNAPSHOT.jar"

RCON_HOST="127.0.0.1"
RCON_PORT="25698"
RCON_PASS="axiomtest"

BOOT_TIMEOUT_SECS=90
QUIET_WINDOW_SECS=10
POST_RCON_WAIT_SECS=15

# Error patterns that indicate FAIL (egrep-style).
FAIL_PATTERNS=(
    "WrongThreadException"
    "is not Folia compatible"
    "java\\.lang\\.IllegalStateException.*axiom"
    "com\\.moulberry\\.axiom.*Exception"
    "SEVERE.*com\\.moulberry\\.axiom"
    "Could not load 'plugins/AxiomPaper"
    "Error occurred while enabling AxiomPaper"
)

cleanup() {
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            echo "[harness] terminating server pid=${pid}" >&2
            kill -TERM "${pid}" 2>/dev/null || true
            for _ in $(seq 1 10); do
                kill -0 "${pid}" 2>/dev/null || break
                sleep 1
            done
            if kill -0 "${pid}" 2>/dev/null; then
                echo "[harness] force-killing pid=${pid}" >&2
                kill -KILL "${pid}" 2>/dev/null || true
            fi
        fi
        rm -f "${PID_FILE}"
    fi
    # Belt-and-suspenders: kill any java still bound to our port.
    local stragglers
    stragglers="$(lsof -ti tcp:25699 2>/dev/null || true)"
    if [[ -n "${stragglers}" ]]; then
        echo "[harness] killing leftover listeners on 25699: ${stragglers}" >&2
        kill -KILL ${stragglers} 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

write_result() {
    local verdict="$1"
    local diag="$2"
    {
        echo "${verdict}"
        echo ""
        echo "${diag}"
        echo ""
        echo "harness: ${HARNESS_DIR}"
        echo "log: ${LOG_FILE}"
        echo "run.log: ${RUN_LOG}"
    } > "${RESULT_FILE}"
}

scan_for_fail() {
    # Returns 0 if a fail pattern is matched, prints the matching line(s).
    local file="$1"
    [[ -f "${file}" ]] || return 1
    local pat
    for pat in "${FAIL_PATTERNS[@]}"; do
        if grep -E -m1 "${pat}" "${file}" >/dev/null 2>&1; then
            grep -E -n "${pat}" "${file}" | head -n5
            return 0
        fi
    done
    return 1
}

send_rcon() {
    local cmd="$1"
    /usr/bin/python3 - "${RCON_HOST}" "${RCON_PORT}" "${RCON_PASS}" "${cmd}" <<'PY'
import socket, struct, sys, time

host, port, password, command = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]

def pack(req_id, ptype, body):
    payload = struct.pack('<ii', req_id, ptype) + body.encode('utf-8') + b'\x00\x00'
    return struct.pack('<i', len(payload)) + payload

def recv_pkt(sock):
    raw_len = b''
    while len(raw_len) < 4:
        chunk = sock.recv(4 - len(raw_len))
        if not chunk:
            return None
        raw_len += chunk
    (length,) = struct.unpack('<i', raw_len)
    data = b''
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            return None
        data += chunk
    req_id, ptype = struct.unpack('<ii', data[:8])
    body = data[8:-2]
    return req_id, ptype, body.decode('utf-8', errors='replace')

s = socket.create_connection((host, port), timeout=10)
s.sendall(pack(1, 3, password))   # SERVERDATA_AUTH
pkt = recv_pkt(s)
if pkt is None or pkt[0] == -1:
    print("RCON_AUTH_FAIL", file=sys.stderr)
    sys.exit(2)
s.sendall(pack(2, 2, command))    # SERVERDATA_EXECCOMMAND
pkt = recv_pkt(s)
if pkt is None:
    print("RCON_NO_RESPONSE", file=sys.stderr)
    sys.exit(3)
print(pkt[2])
s.close()
PY
}

mkdir -p "${HARNESS_DIR}"
rm -f "${RESULT_FILE}" "${RUN_LOG}" "${PID_FILE}"
# Wipe stale logs/world from previous runs to keep things hermetic, but keep
# the server jar + plugins + props + eula.
rm -rf "${SERVER_DIR}/logs" "${SERVER_DIR}/world" "${SERVER_DIR}/world_nether" \
       "${SERVER_DIR}/world_the_end" "${SERVER_DIR}/cache" "${SERVER_DIR}/versions" \
       "${SERVER_DIR}/libraries" "${SERVER_DIR}/usercache.json" \
       "${SERVER_DIR}/banned-ips.json" "${SERVER_DIR}/banned-players.json" \
       "${SERVER_DIR}/ops.json" "${SERVER_DIR}/whitelist.json" \
       "${SERVER_DIR}/config" "${SERVER_DIR}/plugins/.paper-remapped"

if [[ ! -x "${JAVA_BIN}" ]]; then
    write_result "FAIL" "JDK 25 not found at ${JAVA_BIN}"
    exit 1
fi

if [[ ! -f "${SERVER_DIR}/${SERVER_JAR}" ]]; then
    write_result "FAIL" "Server jar missing: ${SERVER_DIR}/${SERVER_JAR}"
    exit 1
fi

if ! ls "${SERVER_DIR}/plugins/"AxiomPaper-*.jar >/dev/null 2>&1; then
    write_result "FAIL" "AxiomPaper jar missing in ${SERVER_DIR}/plugins/"
    exit 1
fi

echo "[harness] booting server (port 25699, rcon 25698)..." >&2
(
    cd "${SERVER_DIR}" || exit 99
    export JAVA_HOME="${JAVA_HOME_DIR}"
    exec "${JAVA_BIN}" -Xmx2G -Xms2G --add-modules=jdk.incubator.vector \
        -jar "${SERVER_JAR}" nogui
) >"${RUN_LOG}" 2>&1 &
SERVER_PID=$!
echo "${SERVER_PID}" > "${PID_FILE}"
echo "[harness] server pid=${SERVER_PID}" >&2

# Wait for "Done (" within BOOT_TIMEOUT_SECS, while watching for fail patterns.
deadline=$(( $(date +%s) + BOOT_TIMEOUT_SECS ))
saw_enabling=0
saw_done=0
done_time=0

while :; do
    now=$(date +%s)
    if (( now > deadline )); then
        break
    fi
    if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
        echo "[harness] server JVM died before Done" >&2
        break
    fi
    if [[ -f "${RUN_LOG}" ]]; then
        if (( saw_enabling == 0 )) && grep -F "[AxiomPaper] Enabling" "${RUN_LOG}" >/dev/null 2>&1; then
            saw_enabling=1
            echo "[harness] saw AxiomPaper Enabling" >&2
        fi
        if (( saw_done == 0 )) && grep -E "Done \(" "${RUN_LOG}" >/dev/null 2>&1; then
            saw_done=1
            done_time=$(date +%s)
            echo "[harness] saw Done(" >&2
            break
        fi
        if fail_hit="$(scan_for_fail "${RUN_LOG}")"; then
            echo "[harness] fail pattern matched during boot:" >&2
            echo "${fail_hit}" >&2
            break
        fi
    fi
    sleep 1
done

if (( saw_done == 0 )); then
    diag="Server did not reach 'Done (' within ${BOOT_TIMEOUT_SECS}s."
    if (( saw_enabling == 1 )); then
        diag="${diag} AxiomPaper began enabling but boot stalled."
    else
        diag="${diag} AxiomPaper Enabling line was never observed."
    fi
    if fail_hit="$(scan_for_fail "${RUN_LOG}")"; then
        diag="${diag}\nFail pattern hits:\n${fail_hit}"
    fi
    tail_log="$(tail -n40 "${RUN_LOG}" 2>/dev/null || true)"
    diag_full="$(printf '%s\nLast 40 log lines:\n%s\n' "${diag}" "${tail_log}")"
    write_result "FAIL" "${diag_full}"
    exit 1
fi

# Quiet window: watch QUIET_WINDOW_SECS of post-Done log for fail patterns.
echo "[harness] observing ${QUIET_WINDOW_SECS}s quiet window..." >&2
quiet_end=$(( done_time + QUIET_WINDOW_SECS ))
while (( $(date +%s) < quiet_end )); do
    if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
        diag="Server JVM exited during quiet window."
        diag_full="$(printf '%s\nLast 40 log lines:\n%s\n' "${diag}" "$(tail -n40 "${RUN_LOG}" 2>/dev/null)")"
        write_result "FAIL" "${diag_full}"
        exit 1
    fi
    if fail_hit="$(scan_for_fail "${RUN_LOG}")"; then
        diag="$(printf 'Fail pattern matched in quiet window:\n%s\n\nLast 40 log lines:\n%s\n' \
            "${fail_hit}" "$(tail -n40 "${RUN_LOG}" 2>/dev/null)")"
        write_result "FAIL" "${diag}"
        exit 1
    fi
    sleep 1
done

echo "[harness] quiet window clean; firing rcon commands..." >&2
rcon_diag=""
RCON_CMDS=(
    "op smoketest"
    "time set day"
    "weather clear"
    "tps"
    "list"
    "save-all"
)
for cmd in "${RCON_CMDS[@]}"; do
    if rcon_out="$(send_rcon "$cmd" 2>&1)"; then
        rcon_diag+="${cmd} -> ${rcon_out}\n"
    else
        rcon_diag+="${cmd} -> RCON_FAILED: ${rcon_out}\n"
    fi
    sleep 1
done

echo "[harness] post-rcon ${POST_RCON_WAIT_SECS}s settle..." >&2
post_end=$(( $(date +%s) + POST_RCON_WAIT_SECS ))
while (( $(date +%s) < post_end )); do
    if fail_hit="$(scan_for_fail "${RUN_LOG}")"; then
        diag="$(printf 'Fail pattern matched after rcon:\n%s\n\nLast 40 log lines:\n%s\n' \
            "${fail_hit}" "$(tail -n40 "${RUN_LOG}" 2>/dev/null)")"
        write_result "FAIL" "${diag}"
        exit 1
    fi
    sleep 1
done

# Final scan covers anything we may have missed.
if fail_hit="$(scan_for_fail "${RUN_LOG}")"; then
    diag="$(printf 'Fail pattern matched (final scan):\n%s\n\nLast 40 log lines:\n%s\n' \
        "${fail_hit}" "$(tail -n40 "${RUN_LOG}" 2>/dev/null)")"
    write_result "FAIL" "${diag}"
    exit 1
fi

done_line="$(grep -E 'Done \(' "${RUN_LOG}" | head -n1)"
enabling_line="$(grep -F '[AxiomPaper] Enabling' "${RUN_LOG}" | head -n1)"
diag_full="$(printf 'AxiomPaper enabled and survived %ss quiet + rcon shake-out.\n\nEnabling: %s\nDone:     %s\n\nRCON:\n%b' \
    "$((QUIET_WINDOW_SECS + POST_RCON_WAIT_SECS))" "${enabling_line}" "${done_line}" "${rcon_diag}")"
write_result "PASS" "${diag_full}"
echo "[harness] PASS" >&2
exit 0
