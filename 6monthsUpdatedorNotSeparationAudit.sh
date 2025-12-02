#!/bin/bash

# API Audit Automation Script
# This script analyzes your API files and generates reports

# Configuration
API_DIR="$HOME/Downloads/afto/afto_api/resources"
OUTPUT_DIR="./api_audit_reports"
SIX_MONTHS_AGO=$(date -d "6 months ago" +%s 2>/dev/null || date -v-6m +%s)

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "=== API Audit Script Started ==="
echo "Analyzing directory: $API_DIR"
echo "Reports will be saved to: $OUTPUT_DIR"
echo ""

# Function to get file info
get_file_info() {
    local file="$1"
    local relative_path="${file#$API_DIR/}"
    
    # Get last commit info
    cd "$(dirname "$file")" || return
    local last_commit_date=$(git log -1 --format=%ci "$file" 2>/dev/null | cut -d' ' -f1)
    local last_commit_author=$(git log -1 --format='%an' "$file" 2>/dev/null)
    local last_commit_email=$(git log -1 --format='%ae' "$file" 2>/dev/null)
    local last_commit_hash=$(git log -1 --format='%h' "$file" 2>/dev/null)
    
    # If no git info, use file modification date
    if [ -z "$last_commit_date" ]; then
        last_commit_date=$(date -r "$file" +%Y-%m-%d 2>/dev/null || stat -f %Sm -t %Y-%m-%d "$file")
        last_commit_author="Unknown (no git history)"
        last_commit_email=""
        last_commit_hash=""
    fi
    
    echo "$relative_path|$last_commit_date|$last_commit_author|$last_commit_email|$last_commit_hash"
}

# Main analysis
echo "Scanning JavaScript files..."

# Initialize CSV files
echo "File Path,Last Modified Date,Last Author,Author Email,Commit Hash,Category" > "$OUTPUT_DIR/recent_files.csv"
echo "File Path,Last Modified Date,Last Author,Author Email,Commit Hash,Category" > "$OUTPUT_DIR/old_files.csv"
echo "File Path,Last Modified Date,Last Author,Author Email,Commit Hash,Category" > "$OUTPUT_DIR/all_files.csv"

# Find all .js files
total_files=0
recent_files=0
old_files=0

while IFS= read -r file; do
    total_files=$((total_files + 1))
    
    # Get file info
    info=$(get_file_info "$file")
    IFS='|' read -r path date author email hash <<< "$info"
    
    # Convert date to timestamp for comparison
    file_timestamp=$(date -d "$date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$date" +%s 2>/dev/null || echo "0")
    
    # Categorize file
    if [ "$file_timestamp" -ge "$SIX_MONTHS_AGO" ] 2>/dev/null; then
        category="Recent (< 6 months)"
        echo "\"$path\",\"$date\",\"$author\",\"$email\",\"$hash\",\"$category\"" >> "$OUTPUT_DIR/recent_files.csv"
        recent_files=$((recent_files + 1))
    else
        category="Old (> 6 months)"
        echo "\"$path\",\"$date\",\"$author\",\"$email\",\"$hash\",\"$category\"" >> "$OUTPUT_DIR/old_files.csv"
        old_files=$((old_files + 1))
    fi
    
    # Add to all files report
    echo "\"$path\",\"$date\",\"$author\",\"$email\",\"$hash\",\"$category\"" >> "$OUTPUT_DIR/all_files.csv"
    
    # Progress indicator
    if [ $((total_files % 10)) -eq 0 ]; then
        echo "Processed $total_files files..."
    fi
done < <(find "$API_DIR" -type f -name "*.js")

echo ""
echo "=== Audit Complete ==="
echo "Total files analyzed: $total_files"
echo "Recent files (< 6 months): $recent_files"
echo "Old files (> 6 months): $old_files"
echo ""
echo "Reports generated:"
echo "  1. $OUTPUT_DIR/all_files.csv - Complete list"
echo "  2. $OUTPUT_DIR/recent_files.csv - Updated in last 6 months"
echo "  3. $OUTPUT_DIR/old_files.csv - Not updated in 6+ months"
echo ""

# Generate summary by author
echo "Generating author summary..."
echo "Author,Recent Files,Old Files,Total Files" > "$OUTPUT_DIR/author_summary.csv"

awk -F',' 'NR>1 {author=$3; category=$6; gsub(/"/, "", author); gsub(/"/, "", category); 
    if(category ~ /Recent/) recent[author]++; 
    else old[author]++; 
    total[author]++
} 
END {
    for(a in total) print "\""a"\","recent[a]+0","old[a]+0","total[a]
}' "$OUTPUT_DIR/all_files.csv" | sort -t',' -k4 -nr >> "$OUTPUT_DIR/author_summary.csv"

echo "  4. $OUTPUT_DIR/author_summary.csv - Summary by author"
echo ""
echo "Next steps:"
echo "  1. Review old_files.csv to identify APIs not updated in 6+ months"
echo "  2. Use author_summary.csv to contact relevant developers"
echo "  3. Run the usage check script to find if APIs are actually being used"
