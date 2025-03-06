#!/bin/bash

# DNS Verification Script
# Usage: ./DNS-check.sh [options] [config_file]
# If no config file is specified, defaults to dns-config.txt

# Default settings
FORCE_FRESH=false
CONFIG_FILE="dns-config.txt"
DNS_SERVER="1.1.1.1"  # Default DNS server
QUERY_COUNT=1         # Default number of queries
VERBOSE=false         # Verbose output
DNS_SERVER_CLI=false  # Flag to track if DNS server was set via CLI
MULTI_SERVER=false    # Flag to use multiple DNS servers
PROPAGATION_TEST=false # Flag for propagation test mode
PROPAGATION_DOMAIN="" # Domain to test for propagation
PROPAGATION_TYPE="A"  # Record type for propagation test
DNS_SERVERS_FILE="dns-servers.txt" # File containing DNS server list

# Load DNS servers from file
load_dns_servers() {
  local dns_file="$1"
  
  # Check if the DNS servers file exists
  if [ ! -f "$dns_file" ]; then
    echo "Warning: DNS servers file '$dns_file' not found. Using default servers."
    # Default DNS servers to use if file not found
    DEFAULT_DNS_SERVERS=("1.1.1.1" "8.8.8.8" "208.67.222.222")
    DNS_SERVER_NAMES=("Cloudflare" "Google" "OpenDNS")
    return
  fi
  
  # Clear arrays
  DEFAULT_DNS_SERVERS=()
  DNS_SERVER_NAMES=()
  
  # Read DNS servers from file
  while IFS='|' read -r NAME IP || [ -n "$NAME" ]; do
    # Skip empty lines and comments
    if [[ -z "$NAME" || "$NAME" == \#* ]]; then
      continue
    fi
    
    # Trim whitespace
    NAME=$(echo "$NAME" | xargs)
    IP=$(echo "$IP" | xargs)
    
    # Add to arrays
    DNS_SERVER_NAMES+=("$NAME")
    DEFAULT_DNS_SERVERS+=("$IP")
  done < "$dns_file"
  
  # Check if we loaded any servers
  if [ ${#DEFAULT_DNS_SERVERS[@]} -eq 0 ]; then
    echo "Warning: No DNS servers loaded from '$dns_file'. Using default servers."
    # Default DNS servers to use if no servers loaded
    DEFAULT_DNS_SERVERS=("1.1.1.1" "8.8.8.8" "208.67.222.222")
    DNS_SERVER_NAMES=("Cloudflare" "Google" "OpenDNS")
  fi
}

# Function to query TXT records - consistent handling for both verification and propagation modes
query_txt_records() {
  local hostname="$1"
  local dns_server="$2"
  
  # Get TXT records using the +short option
  dig +short @"$dns_server" "$hostname" TXT
}

# Function to print a table row with column data
print_table_row() {
  local col1="$1"
  local col2="$2"
  local col3="$3"
  local col4="$4"

  printf "| %-34s | %-6s | %-32s | %-12s |\n" "$col1" "$col2" "$col3" "$col4"
}

# Function to print a table separator line
print_table_separator() {
  printf "+%s+%s+%s+%s+\n" "$(printf -- '-%.0s' {1..36})" "$(printf -- '-%.0s' {1..8})" "$(printf -- '-%.0s' {1..34})" "$(printf -- '-%.0s' {1..14})"
}

# For TTL extraction, correctly parse the full dig output to get the TTL value
get_ttl() {
  local hostname="$1"
  local record_type="$2"
  local dns_server="$3"
  
  # Run a direct dig command and capture output
  local full_output=$(dig @"$dns_server" "$hostname" "$record_type" +noall +answer +ttlid)
  
  # Extract the TTL directly from the second field of the last non-empty line
  local ttl=$(echo "$full_output" | tail -1 | awk '{print $2}')
  
  # Check if TTL is valid
  if [ -n "$ttl" ] && [[ "$ttl" =~ ^[0-9]+$ ]]; then
    echo "$ttl"
  else
    echo "N/A"
  fi
}

# Function to perform a DNS query and store the results
perform_query() {
  local server="$1"
  local hostname="$2"
  local record_type="$3"
  local index="$4"
  
  # Store the server name for reference
  SERVER_NAMES[$index]="$server"
  
  # Get the actual DNS record with TTL if needed
  if [ "$VERBOSE" = true ]; then
    TTL=$(get_ttl "$hostname" "$record_type" "$server")
  else
    TTL="N/A"
  fi
  
  # Get the actual record value for comparison
  if [[ "$record_type" == "TXT" ]]; then
    # For TXT records, use +short to get the raw output
    ACTUAL=$(dig +short @$server "$hostname" TXT)
  elif [[ "$record_type" == "A" || "$record_type" == "AAAA" ]]; then
    # For A/AAAA records, join multiple IPs with commas
    ACTUAL=$(dig +short @$server "$hostname" "$record_type" | paste -sd "," -)
  else
    # For other record types
    ACTUAL=$(dig +short @$server "$hostname" "$record_type")
  fi
  
  # Store the raw output for display
  DISPLAY_ACTUAL="$ACTUAL"
  
  # Check if we got any results
  if [ -z "$ACTUAL" ]; then
    if [ "$VERBOSE" = true ]; then
      echo "  Warning: No results returned for $hostname ($record_type) on server $server"
    fi
    RESULTS[$index]=""
    TTLS[$index]="$TTL"
    return
  fi
  
  # If we got a result, at least one query succeeded
  ALL_QUERIES_FAILED=false
  
  # Store results for comparison
  RESULTS[$index]="$ACTUAL"
  TTLS[$index]="$TTL"
}

# Function to run a propagation test for a single domain
run_propagation_test() {
  local domain="$1"
  local record_type="$2"
  
  echo "===== DNS PROPAGATION TEST ====="
  echo "Testing domain: $domain"
  echo "Record type: $record_type"
  echo "Using ${#DEFAULT_DNS_SERVERS[@]} DNS servers"
  echo "Cache prevention: $([ "$FORCE_FRESH" = true ] && echo "Enabled" || echo "Disabled")"
  echo
  
  # Initialize arrays for results
  declare -a RESULTS
  declare -a TTLS
  declare -a SERVER_NAMES
  
  # Flag to track if all queries failed
  ALL_QUERIES_FAILED=true
  
  # Counter for query index
  QUERY_INDEX=0
  
  # Query all DNS servers
  for ((s=0; s<${#DEFAULT_DNS_SERVERS[@]}; s++)); do
    CURRENT_SERVER="${DEFAULT_DNS_SERVERS[$s]}"
    SERVER_NAME="${DNS_SERVER_NAMES[$s]}"
    
    ((QUERY_INDEX++))
    
    if [ "$VERBOSE" = true ]; then
      echo "  Querying $SERVER_NAME ($CURRENT_SERVER) for $domain..."
    fi
    
    # Perform the query
    perform_query "$CURRENT_SERVER" "$domain" "$record_type" "$QUERY_INDEX"
  done
  
  # Group results by value for better display
  # We'll use parallel arrays instead of associative arrays for better compatibility
  declare -a UNIQUE_RESULTS
  declare -a RESULT_COUNTS
  declare -a RESULT_TTLS
  declare -a RESULT_SERVERS
  
  # Process results
  for ((i=1; i<=QUERY_INDEX; i++)); do
    if [ -n "${RESULTS[$i]}" ]; then
      RESULT="${RESULTS[$i]}"
      TTL="${TTLS[$i]}"
      SERVER="${SERVER_NAMES[$i]}"
      
      # Check if this result is already in our list
      FOUND=false
      for ((j=0; j<${#UNIQUE_RESULTS[@]}; j++)); do
        if [ "${UNIQUE_RESULTS[$j]}" = "$RESULT" ]; then
          # Increment count
          RESULT_COUNTS[$j]=$((RESULT_COUNTS[$j] + 1))
          # Append server to list
          RESULT_SERVERS[$j]="${RESULT_SERVERS[$j]}, $SERVER"
          FOUND=true
          break
        fi
      done
      
      # If not found, add it
      if [ "$FOUND" = false ]; then
        UNIQUE_RESULTS+=("$RESULT")
        RESULT_COUNTS+=(1)
        RESULT_TTLS+=("$TTL")
        RESULT_SERVERS+=("$SERVER")
      fi
    fi
  done
  
  # Count total successful queries
  TOTAL_SUCCESSFUL=0
  for COUNT in "${RESULT_COUNTS[@]}"; do
    TOTAL_SUCCESSFUL=$((TOTAL_SUCCESSFUL + COUNT))
  done
  
  # Display results
  if [ "$ALL_QUERIES_FAILED" = true ]; then
    echo "No results returned from any DNS server for $domain ($record_type)"
    echo "Status: ❌ NOT PROPAGATED"
  else
    echo "Propagation Results for $domain ($record_type):"
    print_table_separator
    printf "| %-34s | %-6s | %-32s | %-12s |\n" "VALUE" "TTL" "CONSISTENCY" "SERVERS"
    print_table_separator
    
    # Sort results by count (most common first)
    # We'll create a sorted index array
    declare -a SORTED_INDICES
    for ((i=0; i<${#UNIQUE_RESULTS[@]}; i++)); do
      SORTED_INDICES[$i]=$i
    done
    
    # Simple bubble sort by count (descending)
    for ((i=0; i<${#UNIQUE_RESULTS[@]}-1; i++)); do
      for ((j=0; j<${#UNIQUE_RESULTS[@]}-i-1; j++)); do
        if [ "${RESULT_COUNTS[${SORTED_INDICES[$j]}]}" -lt "${RESULT_COUNTS[${SORTED_INDICES[$j+1]}]}" ]; then
          # Swap
          TEMP=${SORTED_INDICES[$j]}
          SORTED_INDICES[$j]=${SORTED_INDICES[$j+1]}
          SORTED_INDICES[$j+1]=$TEMP
        fi
      done
    done
    
    # Display sorted results in a table
    for IDX in "${SORTED_INDICES[@]}"; do
      RESULT="${UNIQUE_RESULTS[$IDX]}"
      COUNT="${RESULT_COUNTS[$IDX]}"
      TTL="${RESULT_TTLS[$IDX]}"
      SERVERS="${RESULT_SERVERS[$IDX]}"
      PERCENTAGE=$((COUNT * 100 / QUERY_INDEX))
      
      # Truncate value if too long
      VALUE="$RESULT"
      if [ ${#VALUE} -gt 34 ]; then
        VALUE="${VALUE:0:31}..."
      fi
      
      # Format TTL for display
      if [ "$TTL" = "N/A" ]; then
        DISPLAY_TTL="N/A"
      else
        DISPLAY_TTL="$TTL sec"
      fi
      
      # Format consistency for display
      CONSISTENCY="$COUNT/$QUERY_INDEX (${PERCENTAGE}%)"
      
      # Truncate servers list for display
      if [ "$VERBOSE" = true ]; then
        SERVER_DISPLAY="$SERVERS"
        if [ ${#SERVER_DISPLAY} -gt 32 ]; then
          SERVER_DISPLAY="${SERVER_DISPLAY:0:29}..."
        fi
      else
        SERVER_DISPLAY="$COUNT servers"
      fi
      
      print_table_row "$VALUE" "$DISPLAY_TTL" "$CONSISTENCY" "$SERVER_DISPLAY"
    done
    
    print_table_separator
    echo
    
    # Determine propagation status
    if [ ${#UNIQUE_RESULTS[@]} -eq 1 ]; then
      echo "Status: ✅ FULLY PROPAGATED (100% consistent)"
    else
      # Get the most common result (first in sorted array)
      MOST_COMMON_IDX=${SORTED_INDICES[0]}
      MOST_COMMON_COUNT="${RESULT_COUNTS[$MOST_COMMON_IDX]}"
      MOST_COMMON_PERCENTAGE=$((MOST_COMMON_COUNT * 100 / QUERY_INDEX))
      
      if [ $MOST_COMMON_PERCENTAGE -ge 80 ]; then
        echo "Status: ⚠️ MOSTLY PROPAGATED (${MOST_COMMON_PERCENTAGE}% consistent)"
      else
        echo "Status: ❌ INCONSISTENT (${MOST_COMMON_PERCENTAGE}% consistent)"
      fi
    fi
  fi
  
  echo
  echo "===== END OF PROPAGATION TEST ====="
}

# Function to display usage information
show_usage() {
  echo "Usage: ./DNS-check.sh [options] [config_file]"
  echo "Options:"
  echo "  -f, --fresh              Force fresh DNS lookups (bypass cache)"
  echo "  -s, --server SERVER      Specify DNS server to query (default: 1.1.1.1)"
  echo "  -q, --queries COUNT      Perform multiple queries and check consistency (default: 1)"
  echo "  -m, --multi-server       Use multiple DNS servers for queries"
  echo "  -p, --propagation DOMAIN Test DNS propagation for a specific domain"
  echo "  -t, --type TYPE          Record type for propagation test (default: A)"
  echo "  -d, --dns-file FILE      Specify a custom DNS servers file (default: dns-servers.txt)"
  echo "  -v, --verbose            Enable verbose output"
  echo "  -h, --help               Show this help message"
  echo ""
  echo "Configuration file format:"
  echo "  RECORD_TYPE | HOSTNAME | EXPECTED_VALUE"
  echo ""
  echo "Special configuration options (at the top of the config file):"
  echo "  #DNS_SERVER=x.x.x.x      Override default DNS server"
  echo ""
  echo "DNS servers file format:"
  echo "  NAME|IP_ADDRESS"
  echo ""
  echo "Notes:"
  echo "  - When using --multi-server, the --queries option specifies queries per server"
  echo "  - When using --multi-server, the --server option is ignored"
  echo "  - When using --propagation, the config file is ignored"
}

# Function to handle errors
handle_error() {
  local error_message="$1"
  local exit_code="${2:-1}"
  
  echo "ERROR: $error_message" >&2
  exit "$exit_code"
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--fresh)
      FORCE_FRESH=true
      shift
      ;;
    -s|--server)
      if [[ -z "$2" || "$2" == -* ]]; then
        handle_error "DNS server option requires an argument."
      fi
      DNS_SERVER="$2"
      DNS_SERVER_CLI=true
      shift 2
      ;;
    -q|--queries)
      if [[ -z "$2" || "$2" == -* ]]; then
        handle_error "Query count option requires a numeric argument."
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        handle_error "Query count must be a positive number."
      fi
      QUERY_COUNT="$2"
      shift 2
      ;;
    -m|--multi-server)
      MULTI_SERVER=true
      shift
      ;;
    -p|--propagation)
      if [[ -z "$2" || "$2" == -* ]]; then
        handle_error "Propagation test option requires a domain argument."
      fi
      PROPAGATION_TEST=true
      PROPAGATION_DOMAIN="$2"
      shift 2
      ;;
    -t|--type)
      if [[ -z "$2" || "$2" == -* ]]; then
        handle_error "Record type option requires an argument."
      fi
      PROPAGATION_TYPE="$2"
      shift 2
      ;;
    -d|--dns-file)
      if [[ -z "$2" || "$2" == -* ]]; then
        handle_error "DNS servers file option requires an argument."
      fi
      DNS_SERVERS_FILE="$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      # Assume it's the config file
      CONFIG_FILE="$1"
      shift
      ;;
  esac
done

# Load DNS servers from file
load_dns_servers "$DNS_SERVERS_FILE"

# Run propagation test if requested
if [ "$PROPAGATION_TEST" = true ]; then
  run_propagation_test "$PROPAGATION_DOMAIN" "$PROPAGATION_TYPE"
  exit 0
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  handle_error "Configuration file '$CONFIG_FILE' not found. Run './DNS-check.sh --help' for more information."
fi

# Check for DNS server override in config file (only if not using multi-server)
if [ "$MULTI_SERVER" = false ]; then
  DNS_SERVER_OVERRIDE=$(grep -E "^#DNS_SERVER=" "$CONFIG_FILE" | cut -d= -f2)
  if [ -n "$DNS_SERVER_OVERRIDE" ] && [ "$DNS_SERVER_CLI" = false ]; then
    # Only override if not specified on command line
    DNS_SERVER="$DNS_SERVER_OVERRIDE"
  fi

  # Validate DNS server format (basic check)
  if ! [[ "$DNS_SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && ! [[ "$DNS_SERVER" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    handle_error "Invalid DNS server format: $DNS_SERVER"
  fi
fi

echo "===== DNS VERIFICATION REPORT ====="
echo "Using configuration file: $CONFIG_FILE"
if [ "$MULTI_SERVER" = true ]; then
  echo "Using multiple DNS servers (${#DEFAULT_DNS_SERVERS[@]} servers):"
  if [ "$VERBOSE" = true ]; then
    for ((i=0; i<${#DEFAULT_DNS_SERVERS[@]}; i++)); do
      echo "  - ${DNS_SERVER_NAMES[$i]} (${DEFAULT_DNS_SERVERS[$i]})"
    done
  else
    echo "  (Use --verbose to see the full list)"
  fi
else
  echo "Using DNS server: $DNS_SERVER"
fi
echo "Cache prevention: $([ "$FORCE_FRESH" = true ] && echo "Enabled" || echo "Disabled")"
echo "Query count: $QUERY_COUNT per $([ "$MULTI_SERVER" = true ] && echo "server" || echo "record")"
echo

# Initialize counters
TOTAL_CHECKS=0
PASSED_CHECKS=0

# Function to compare DNS records
compare_records() {
  local expected="$1"
  local actual="$2"
  local record_type="$3"

  if [ "$record_type" = "TXT" ]; then
    # Remove quotes for comparison
    local clean_expected=$(echo "$expected" | tr -d '"')
    local clean_actual=$(echo "$actual" | tr -d '"')
    
    # For SPF records, ignore -all vs ~all difference
    if [[ "$clean_expected" == *"v=spf1"* ]]; then
      # Get the base part without the -all or ~all
      local expected_base="${clean_expected%-all*}"
      expected_base="${expected_base%~all*}"
      
      local actual_base="${clean_actual%-all*}"
      actual_base="${actual_base%~all*}"
      
      [ "$expected_base" = "$actual_base" ]
    else
      # For other TXT records
      [ "$clean_expected" = "$clean_actual" ]
    fi
  else
    # For non-TXT records
    [ "$expected" = "$actual" ]
  fi
}

# Initialize arrays to store check results for tabular display
declare -a CHECK_HOSTNAMES
declare -a CHECK_TYPES
declare -a CHECK_STATUSES
declare -a CHECK_VALUES

# Process each line in the configuration file
while IFS='|' read -r RECORD_TYPE HOSTNAME EXPECTED || [ -n "$RECORD_TYPE" ]; do
  # Skip empty lines and comments
  if [[ -z "$RECORD_TYPE" || "$RECORD_TYPE" == \#* ]]; then
    continue
  fi
  
  # Trim whitespace
  RECORD_TYPE=$(echo "$RECORD_TYPE" | xargs)
  HOSTNAME=$(echo "$HOSTNAME" | xargs)
  EXPECTED=$(echo "$EXPECTED" | xargs)
  
  # Skip if any required field is missing
  if [[ -z "$HOSTNAME" || -z "$RECORD_TYPE" || -z "$EXPECTED" ]]; then
    echo "Warning: Skipping invalid line: $RECORD_TYPE|$HOSTNAME|$EXPECTED"
    continue
  fi
  
  # Initialize variables for this record
  ACTUAL=""
  DISPLAY_ACTUAL=""
  TTL=""
  ALL_QUERIES_FAILED=true
  
  # Perform queries
  for ((i=1; i<=QUERY_COUNT; i++)); do
    if [ "$VERBOSE" = true ]; then
      echo "Query $i of $QUERY_COUNT for $RECORD_TYPE ($HOSTNAME)..."
    fi
    
    # Get the actual DNS record
    if [[ "$RECORD_TYPE" == "TXT" ]]; then
      # For TXT records, use +short to get the raw output
      RAW_ACTUAL=$(dig +short @$DNS_SERVER "$HOSTNAME" TXT)
      
      # Store the raw output for display
      DISPLAY_ACTUAL="$RAW_ACTUAL"
      
      # Process for comparison
      ACTUAL="$RAW_ACTUAL"
      
      # Make sure non-empty
      if [ -z "$ACTUAL" ]; then
        ACTUAL="NO_RECORDS_FOUND"
      fi
      
      # If verbose mode, also get the TTL
      if [ "$VERBOSE" = true ]; then
        TTL=$(get_ttl "$HOSTNAME" "TXT" "$DNS_SERVER")
      else
        TTL="N/A"
      fi
    elif [[ "$RECORD_TYPE" == "A" || "$RECORD_TYPE" == "AAAA" ]]; then
      # For A/AAAA records, join multiple IPs with commas
      ACTUAL=$(dig +short @$DNS_SERVER "$HOSTNAME" "$RECORD_TYPE" | paste -sd "," -)
      DISPLAY_ACTUAL="$ACTUAL"
      
      # If verbose mode, also get the TTL
      if [ "$VERBOSE" = true ]; then
        TTL=$(get_ttl "$HOSTNAME" "$RECORD_TYPE" "$DNS_SERVER")
      else
        TTL="N/A"
      fi
    else
      # For other record types
      ACTUAL=$(dig +short @$DNS_SERVER "$HOSTNAME" "$RECORD_TYPE")
      DISPLAY_ACTUAL="$ACTUAL"
      
      # If verbose mode, also get the TTL
      if [ "$VERBOSE" = true ]; then
        TTL=$(get_ttl "$HOSTNAME" "$RECORD_TYPE" "$DNS_SERVER")
      else
        TTL="N/A"
      fi
    fi
    
    # If we got a result, at least one query succeeded
    if [ -n "$ACTUAL" ] && [ "$ACTUAL" != "NO_RECORDS_FOUND" ]; then
      ALL_QUERIES_FAILED=false
    fi
  done
  
  # In verbose mode, display detailed output
  if [ "$VERBOSE" = true ]; then
    echo "Testing $HOSTNAME Records:"
    echo "$(printf -- '-%.0s' {1..40})"
    echo "$RECORD_TYPE:"
    echo "  Expected: $EXPECTED"
    echo "  Actual:   $DISPLAY_ACTUAL"
    if [ "$TTL" = "N/A" ]; then
      echo "  TTL:      N/A"
    else
      echo "  TTL:      $TTL seconds"
    fi
  fi
  
  # Determine match status
  MATCH_STATUS="❌ MISMATCH"
  
  # For TXT records, handle comparison differently
  if [[ "$RECORD_TYPE" == "TXT" ]]; then
    # Remove quotes from both expected and actual for comparison
    CLEAN_EXPECTED=$(echo "$EXPECTED" | tr -d '"')
    CLEAN_ACTUAL=$(echo "$ACTUAL" | tr -d '"')
    
    # For SPF records, special handling for -all vs ~all
    if [[ "$CLEAN_EXPECTED" == *"v=spf1"* ]]; then
      EXPECTED_BASE="${CLEAN_EXPECTED%-all*}"
      EXPECTED_BASE="${EXPECTED_BASE%~all*}"
      
      ACTUAL_BASE="${CLEAN_ACTUAL%-all*}"
      ACTUAL_BASE="${ACTUAL_BASE%~all*}"
      
      if [ "$EXPECTED_BASE" = "$ACTUAL_BASE" ]; then
        MATCH_STATUS="✅ MATCH (SPF)"
        ((PASSED_CHECKS++))
      fi
    elif [ "$CLEAN_EXPECTED" = "$CLEAN_ACTUAL" ]; then
      MATCH_STATUS="✅ MATCH"
      ((PASSED_CHECKS++))
    fi
  else
    # For non-TXT records
    if [ "$EXPECTED" = "$ACTUAL" ]; then
      MATCH_STATUS="✅ MATCH"
      ((PASSED_CHECKS++))
    fi
  fi
  
  # In verbose mode, display the status
  if [ "$VERBOSE" = true ]; then
    echo "  Status:   $MATCH_STATUS"
    echo
  fi
  
  # Store results for table display
  CHECK_HOSTNAMES+=("$HOSTNAME")
  CHECK_TYPES+=("$RECORD_TYPE")
  CHECK_STATUSES+=("$MATCH_STATUS")
  CHECK_VALUES+=("$DISPLAY_ACTUAL")
  
  ((TOTAL_CHECKS++))
done < "$CONFIG_FILE"

# For non-verbose mode, display results in a table
if [ "$VERBOSE" = false ]; then
  echo "DNS Check Results:"
  print_table_separator
  printf "| %-34s | %-6s | %-32s | %-12s |\n" "HOSTNAME" "TYPE" "VALUE" "STATUS"
  print_table_separator
  
  for ((i=0; i<${#CHECK_HOSTNAMES[@]}; i++)); do
    # Truncate hostname if too long
    HOSTNAME="${CHECK_HOSTNAMES[$i]}"
    if [ ${#HOSTNAME} -gt 34 ]; then
      HOSTNAME="${HOSTNAME:0:31}..."
    fi
    
    # Truncate value if it's too long to fit in the table
    VALUE="${CHECK_VALUES[$i]}"
    if [ ${#VALUE} -gt 32 ]; then
      VALUE="${VALUE:0:29}..."
    fi
    
    # For status, we'll keep the full text since it's important
    STATUS="${CHECK_STATUSES[$i]}"
    
    print_table_row "$HOSTNAME" "${CHECK_TYPES[$i]}" "$VALUE" "$STATUS"
  done
  
  print_table_separator
  echo
fi

# Display summary
echo "===== SUMMARY ====="
echo "Total checks: $TOTAL_CHECKS"
echo "Passed checks: $PASSED_CHECKS"
echo "Failed checks: $((TOTAL_CHECKS - PASSED_CHECKS))"
echo

echo "===== END OF REPORT ====="

