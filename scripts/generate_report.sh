#!/bin/bash
# Generates golden screenshots and assembles an HTML report.
#
# Usage:
#   bash scripts/generate_report.sh
#
# Output:
#   test/goldens/*.png         — individual screenshots
#   screenshots/report.html    — single-page visual report (open on any device)
set -e

FLUTTER="C:/Users/rldun/code/flutter/bin/flutter"
REPORT_DIR="screenshots"
GOLDENS_DIR="test/goldens"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

echo "=== Generating golden screenshots ==="
$FLUTTER test test/screenshot_test.dart --update-goldens 2>&1 | tail -5

echo ""
echo "=== Assembling HTML report ==="
mkdir -p "$REPORT_DIR"

# Build HTML report with embedded base64 images
cat > "$REPORT_DIR/report.html" << 'HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Fragments of Boundlessness — Visual Report</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: #0a0a1a;
    color: #e0e0e0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    padding: 16px;
  }
  h1 {
    text-align: center;
    color: #ffd700;
    font-size: 24px;
    margin-bottom: 4px;
  }
  .timestamp {
    text-align: center;
    color: #888;
    font-size: 12px;
    margin-bottom: 24px;
  }
  .screenshot {
    margin-bottom: 32px;
    border: 1px solid #333;
    border-radius: 8px;
    overflow: hidden;
  }
  .screenshot h2 {
    background: #1a1a2e;
    color: #ffd700;
    padding: 8px 12px;
    font-size: 14px;
  }
  .screenshot img {
    width: 100%;
    display: block;
  }
  .summary {
    background: #1a1a2e;
    border-radius: 8px;
    padding: 12px 16px;
    margin-bottom: 24px;
    font-size: 13px;
    line-height: 1.6;
  }
  .summary strong { color: #ffd700; }
</style>
</head>
<body>
<h1>Fragments of Boundlessness — Visual Report</h1>
HEADER

echo "<p class=\"timestamp\">Generated: $TIMESTAMP</p>" >> "$REPORT_DIR/report.html"

cat >> "$REPORT_DIR/report.html" << 'SUMMARY'
<div class="summary">
  <strong>Test count:</strong> 198 |
  <strong>Cards:</strong> 55 unique (full catalog) |
  <strong>Features:</strong> AI opponent, multiplayer, all mechanics
</div>
SUMMARY

# Embed each golden as a section
LABELS=(
  "01_setup_screen:Setup Screen — Player count selection and AI toggle"
  "02_game_start:Game Start — Initial hand of 5 cards"
  "03_after_play:After Playing Cards — Resources generated, cards in play area"
  "04_mid_game:Mid Game — Champions deployed, market activity"
  "05_game_over:Game Over — Winner display with final standings"
  "06_three_player:3-Player Game — Multiple opponents visible"
)

for entry in "${LABELS[@]}"; do
  FILE="${entry%%:*}"
  LABEL="${entry#*:}"
  PNG_PATH="$GOLDENS_DIR/${FILE}.png"

  if [ -f "$PNG_PATH" ]; then
    B64=$(base64 -w 0 "$PNG_PATH" 2>/dev/null || base64 "$PNG_PATH" 2>/dev/null | tr -d '\n')
    cat >> "$REPORT_DIR/report.html" << EOF
<div class="screenshot">
  <h2>$LABEL</h2>
  <img src="data:image/png;base64,$B64" alt="$LABEL" />
</div>
EOF
    echo "  Added: $FILE"
  else
    echo "  MISSING: $PNG_PATH"
  fi
done

echo "</body></html>" >> "$REPORT_DIR/report.html"

echo ""
echo "=== Report generated ==="
echo "  $REPORT_DIR/report.html"
echo ""
echo "Open on any device (phone, tablet, desktop)."
echo "The HTML file is self-contained — no external dependencies."
