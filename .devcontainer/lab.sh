#!/usr/bin/env bash
# =============================================================================
#  lab — lệnh tắt điều khiển cụm CT428 trong codespace
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$ROOT"
CORE=(-f docker-compose.yml)
ALL=(-f docker-compose.yml -f docker-compose.extras.yml)

url() {  # url <cổng> → đường dẫn mở được trong trình duyệt
  if [ -n "${CODESPACE_NAME:-}" ]; then
    echo "https://${CODESPACE_NAME}-$1.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
  else echo "http://localhost:$1"; fi
}

case "${1:-help}" in
  start)   docker compose "${CORE[@]}" up -d --no-build --wait --wait-timeout 300 ;;
  hive)    docker compose "${ALL[@]}" up -d --wait --wait-timeout 420 hiveserver2 ;;
  nosql)   docker compose "${ALL[@]}" up -d --wait --wait-timeout 300 hbase mongodb ;;
  kafka)   docker compose "${ALL[@]}" up -d --wait --wait-timeout 300 kafka ;;
  extras)
    mem_gb=$(awk '/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo)
    if [ "${mem_gb:-0}" -lt 12 ]; then
      echo "CẢNH BÁO: máy có ~${mem_gb} GB RAM. Bật cùng lúc mọi dịch vụ bổ sung chỉ còn ~2 GB trống,"
      echo "job Spark có thể lỗi ngẫu nhiên. Nên bật theo bài: lab hive | lab nosql | lab kafka."
      echo "Vẫn bật tất cả sau 5 giây (Ctrl+C để huỷ)..."; sleep 5
    fi
    docker compose "${ALL[@]}" up -d --wait --wait-timeout 420 ;;
  stop-extras) docker compose "${ALL[@]}" stop hiveserver2 hive-metastore hive-metastore-db kafka hbase mongodb ;;
  stop)    docker compose "${ALL[@]}" stop ;;
  status)
    docker compose "${ALL[@]}" ps --format 'table {{.Name}}\t{{.Status}}'
    echo
    r=$(docker exec namenode hdfs dfsadmin -report 2>/dev/null); echo "$r" | grep -q "Live datanodes" \
      && echo "HDFS: $(echo "$r" | grep -m1 'Live datanodes')" || echo "HDFS: chưa chạy"
    r=$(docker exec resourcemanager yarn node -list 2>/dev/null); echo "$r" | grep -q "Total Nodes" \
      && echo "YARN: $(echo "$r" | grep -m1 'Total Nodes')" || echo "YARN: chưa chạy"
    docker stats --no-stream --format '{{.MemUsage}}' 2>/dev/null | awk '{v=$1; u=v; gsub(/[0-9.]/,"",u); gsub(/[A-Za-z]/,"",v);
      if(u=="GiB")v*=1024; else if(u=="KiB")v/=1024; else if(u=="B")v/=1048576; s+=v} END{printf "RAM các container: %.1f GB\n", s/1024}'
    ;;
  ui)
    printf '%-24s %s\n' "HDFS NameNode" "$(url 9870)" "YARN ResourceManager" "$(url 8088)" \
      "Spark Master" "$(url 8080)" "Spark UI (job đang chạy)" "$(url 4040)" \
      "Spark History" "$(url 18080)" "MapReduce JobHistory" "$(url 19888)" \
      "HiveServer2 UI" "$(url 10002)" "HBase Master" "$(url 16010)"
    [ -n "${CODESPACE_NAME:-}" ] && echo "(Hoặc mở tab PORTS bên cạnh TERMINAL, bấm biểu tượng quả địa cầu.)" ;;
  test)    bash scripts-host/smoke_test.sh ;;
  data)
    if command -v python3 >/dev/null; then python3 gen_data.py --rows "${2:-200000}" --out ./data
    else docker run --rm --entrypoint python3 --user "$(id -u):$(id -g)" -v "$ROOT":/w -w /w bigdata-lab:2026.10 \
           gen_data.py --rows "${2:-200000}" --out ./data; fi ;;
  reset)
    read -r -p "XOÁ TOÀN BỘ dữ liệu HDFS/Hive/Kafka/HBase/MongoDB? Gõ 'xoa' để xác nhận: " a
    [ "$a" = "xoa" ] && docker compose "${ALL[@]}" down -v && echo "Đã xoá. Gõ: lab start" || echo "Huỷ." ;;
  *)
    cat <<'H'
Các lệnh:
  lab start        bật cụm lõi (HDFS, YARN, Spark) — tự chạy khi mở codespace
  lab hive         bật Hive (Lab 3)          lab nosql   bật HBase + MongoDB (Lab 4)
  lab kafka        bật Kafka (Lab 6)         lab extras  bật tất cả dịch vụ bổ sung
  lab stop-extras  tắt dịch vụ bổ sung để giải phóng RAM
  lab stop         dừng mọi container (GIỮ dữ liệu)
  lab status       trạng thái container, HDFS, YARN, RAM
  lab ui           đường dẫn Web UI
  lab test         chạy smoke test toàn cụm
  lab data [N]     sinh lại dữ liệu mẫu N dòng (mặc định 200000)
  lab reset        xoá sạch dữ liệu cụm, làm lại từ đầu
Các lệnh trong README.md (docker exec -it namenode bash, ...) dùng nguyên như cũ.
H
    ;;
esac
