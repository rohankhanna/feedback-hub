#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIAGRAM_DIR="${REPO_ROOT}/docs/diagrams"

usage() {
  cat <<'EOF_USAGE'
Usage:
  ./scripts/render_architecture.sh [--write|--check]
  ./scripts/render_architecture.sh --stdout <diagram-name>

Examples:
  ./scripts/render_architecture.sh --write
  ./scripts/render_architecture.sh --check
  ./scripts/render_architecture.sh --stdout repo-local-integration
EOF_USAGE
}

xml_escape() {
  printf '%s' "$1" \
    | sed \
      -e 's/&/\&amp;/g' \
      -e 's/</\&lt;/g' \
      -e 's/>/\&gt;/g' \
      -e "s/'/\&apos;/g" \
      -e 's/"/\&quot;/g'
}

list_sources() {
  find "${DIAGRAM_DIR}" -maxdepth 1 -type f -name '*.diagram.json' | sort
}

require_source() {
  if [ ! -d "${DIAGRAM_DIR}" ]; then
    echo "Error: missing diagram directory: ${DIAGRAM_DIR}" >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required to render the architecture diagrams." >&2
    exit 1
  fi
  if [ -z "$(list_sources)" ]; then
    echo "Error: no *.diagram.json files found in ${DIAGRAM_DIR}" >&2
    exit 1
  fi
}

render_svg() {
  local source_file="$1"
  local title description width height
  title="$(jq -r '.title' "${source_file}")"
  description="$(jq -r '.description // empty' "${source_file}")"
  width="$(jq -r '.width' "${source_file}")"
  height="$(jq -r '.height' "${source_file}")"
  if [ -z "${description}" ]; then
    description="feedback-hub architecture diagram."
  fi

  cat <<EOF_SVG
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title desc">
  <title id="title">$(xml_escape "${title}")</title>
  <desc id="desc">$(xml_escape "${description}")</desc>
  <defs>
    <marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto" markerUnits="strokeWidth">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="#4A4A4A" />
    </marker>
    <filter id="card-shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="8" stdDeviation="10" flood-color="#000000" flood-opacity="0.08" />
    </filter>
  </defs>
  <rect x="0" y="0" width="${width}" height="${height}" fill="#F7F4EE" />
  <text x="32" y="46" font-family="Helvetica, Arial, sans-serif" font-size="32" font-weight="700" fill="#1F1F1F">$(xml_escape "${title}")</text>
  <text x="32" y="76" font-family="Helvetica, Arial, sans-serif" font-size="16" fill="#5A5A5A">$(xml_escape "${description}")</text>
EOF_SVG

  jq -r '.groups[]? | [ .x, .y, .w, .h, .label, (.subtitle // "") ] | @tsv' "${source_file}" \
    | while IFS=$'\t' read -r x y w h label subtitle; do
        cat <<EOF_GROUP
  <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="24" fill="#FFFFFF" stroke="#D1CCC1" stroke-width="1.5" filter="url(#card-shadow)" />
  <text x="$((x + 24))" y="$((y + 34))" font-family="Helvetica, Arial, sans-serif" font-size="20" font-weight="700" fill="#393939">$(xml_escape "${label}")</text>
EOF_GROUP
        if [ -n "${subtitle}" ]; then
          cat <<EOF_GROUP_SUB
  <text x="$((x + 24))" y="$((y + 58))" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#6A6A6A">$(xml_escape "${subtitle}")</text>
EOF_GROUP_SUB
        fi
      done

  jq -r '.edges[] | [(.x1|tostring), (.y1|tostring), (.x2|tostring), (.y2|tostring), .label, ((.label_dx // 0)|tostring), ((.label_dy // 0)|tostring)] | @tsv' "${source_file}" \
    | while IFS=$'\t' read -r x1 y1 x2 y2 label label_dx label_dy; do
        local label_x label_y escaped_label label_width label_rect_x
        label_x=$(( (x1 + x2) / 2 ))
        label_y=$(( (y1 + y2) / 2 - 8 ))
        label_x=$(( label_x + label_dx ))
        label_y=$(( label_y + label_dy ))
        label_width=$(( ${#label} * 7 + 24 ))
        if [ "${label_width}" -lt 104 ]; then
          label_width=104
        fi
        label_rect_x=$(( label_x - label_width / 2 ))
        escaped_label="$(xml_escape "${label}")"
        cat <<EOF_EDGE
  <line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="#4A4A4A" stroke-width="2.5" marker-end="url(#arrow)" />
  <rect x="${label_rect_x}" y="$((label_y - 17))" width="${label_width}" height="24" rx="12" fill="#FBFBFB" stroke="#E2DED6" stroke-width="1" />
  <text x="${label_x}" y="${label_y}" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#333333">${escaped_label}</text>
EOF_EDGE
      done

  jq -r '.nodes[] | [ .x, .y, .w, .h, .fill, .stroke, (.lines | join("\u001f")) ] | @tsv' "${source_file}" \
    | while IFS=$'\t' read -r x y w h fill stroke lines_blob; do
        local text_x text_y line_index line font_weight font_size
        cat <<EOF_NODE
  <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="20" fill="${fill}" stroke="${stroke}" stroke-width="2.5" filter="url(#card-shadow)" />
EOF_NODE
        text_x=$(( x + w / 2 ))
        text_y=$(( y + 36 ))
        line_index=0
        IFS=$'\037' read -r -a lines <<< "${lines_blob}"
        printf '  <text x="%s" y="%s" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" fill="#1F1F1F">\n' "${text_x}" "${text_y}"
        for line in "${lines[@]}"; do
          font_weight="400"
          font_size="16"
          if [ "${line_index}" -eq 0 ]; then
            font_weight="700"
            font_size="18"
          fi
          printf '    <tspan x="%s" dy="%s" font-size="%s" font-weight="%s">%s</tspan>\n' \
            "${text_x}" \
            "$( [ "${line_index}" -eq 0 ] && printf '0' || printf '24' )" \
            "${font_size}" \
            "${font_weight}" \
            "$(xml_escape "${line}")"
          line_index=$((line_index + 1))
        done
        printf '  </text>\n'
      done

  jq -r '.notes[]? | [ .x, .y, .w, .h, (.fill // "#FFFFFF"), (.stroke // "#777777"), (.dasharray // ""), (.lines | join("\u001f")) ] | @tsv' "${source_file}" \
    | while IFS=$'\t' read -r x y w h fill stroke dasharray lines_blob; do
        local text_x text_y line_index line font_weight font_size
        if [ -n "${dasharray}" ]; then
          printf '  <rect x="%s" y="%s" width="%s" height="%s" rx="20" fill="%s" stroke="%s" stroke-width="2" stroke-dasharray="%s" />\n' \
            "${x}" "${y}" "${w}" "${h}" "${fill}" "${stroke}" "${dasharray}"
        else
          printf '  <rect x="%s" y="%s" width="%s" height="%s" rx="20" fill="%s" stroke="%s" stroke-width="2" />\n' \
            "${x}" "${y}" "${w}" "${h}" "${fill}" "${stroke}"
        fi
        text_x=$(( x + 24 ))
        text_y=$(( y + 32 ))
        line_index=0
        IFS=$'\037' read -r -a lines <<< "${lines_blob}"
        printf '  <text x="%s" y="%s" font-family="Helvetica, Arial, sans-serif" fill="#2B2B2B">\n' "${text_x}" "${text_y}"
        for line in "${lines[@]}"; do
          font_weight="400"
          font_size="16"
          if [ "${line_index}" -eq 0 ]; then
            font_weight="700"
            font_size="18"
          fi
          printf '    <tspan x="%s" dy="%s" font-size="%s" font-weight="%s">%s</tspan>\n' \
            "${text_x}" \
            "$( [ "${line_index}" -eq 0 ] && printf '0' || printf '24' )" \
            "${font_size}" \
            "${font_weight}" \
            "$(xml_escape "${line}")"
          line_index=$((line_index + 1))
        done
        printf '  </text>\n'
      done

  cat <<'EOF_END'
</svg>
EOF_END
}

render_to_path() {
  local source_file="$1"
  local target_file="$2"
  local tmp_file
  tmp_file="$(mktemp)"
  render_svg "${source_file}" > "${tmp_file}"
  mv "${tmp_file}" "${target_file}"
}

check_path() {
  local source_file="$1"
  local target_file="$2"
  local tmp_file
  tmp_file="$(mktemp)"
  render_svg "${source_file}" > "${tmp_file}"
  if [ ! -f "${target_file}" ]; then
    echo "Error: missing ${target_file}. Run ./scripts/render_architecture.sh --write" >&2
    rm -f "${tmp_file}"
    exit 1
  fi
  if ! cmp -s "${tmp_file}" "${target_file}"; then
    echo "Error: ${target_file} is out of date. Run ./scripts/render_architecture.sh --write" >&2
    rm -f "${tmp_file}"
    exit 1
  fi
  rm -f "${tmp_file}"
}

mode="${1:---write}"
case "${mode}" in
  --write|--check) ;;
  --stdout)
    if [ "$#" -ne 2 ]; then
      usage >&2
      exit 1
    fi
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

require_source

case "${mode}" in
  --stdout)
    render_svg "${DIAGRAM_DIR}/${2}.diagram.json"
    ;;
  --write)
    while IFS= read -r source_file; do
      render_to_path "${source_file}" "${source_file%.diagram.json}.svg"
      echo "Rendered: ${source_file%.diagram.json}.svg"
    done < <(list_sources)
    ;;
  --check)
    while IFS= read -r source_file; do
      check_path "${source_file}" "${source_file%.diagram.json}.svg"
    done < <(list_sources)
    echo "Architecture diagrams are up to date."
    ;;
esac
